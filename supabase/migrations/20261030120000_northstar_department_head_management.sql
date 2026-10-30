-- Atomic administrator workflows for rank assignment, approval, and head changes.
-- Apply after 20261029120000_northstar_department_hierarchy_and_collaboration.sql.
BEGIN;

DO $preflight$
BEGIN
  IF to_regprocedure('public.northstar_is_designated_admin()') IS NULL
     OR to_regprocedure('public.northstar_admin_update_employee_registration_status(uuid,text,text,text[])') IS NULL
     OR to_regprocedure('public.northstar_admin_assign_department_level(uuid,uuid,smallint)') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('public.departments') IS NULL THEN
    RAISE EXCEPTION 'Department head management requires the NorthStar hierarchy and registration migrations first.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'department_level'
      AND data_type = 'smallint'
  ) OR to_regclass('public.northstar_one_active_department_head_uidx') IS NULL THEN
    RAISE EXCEPTION 'Department head management requires the smallint rank column and unique active-head index from the hierarchy migration.';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.northstar_admin_list_department_management()
RETURNS TABLE (
  department_id uuid, department_name text, user_id uuid, display_name text,
  role text, department_level smallint, approval_status text,
  employment_status text, registration_completed boolean, email_verified boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated administrator may view department assignments.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  WITH assignment_rows AS (
    SELECT d.id AS department_id, d.name::text AS department_name, p.id AS user_id,
           NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', p.first_name, p.last_name)), '') AS display_name,
           p.role::text AS role, p.department_level, p.approval_status::text AS approval_status,
           p.employment_status::text AS employment_status, p.registration_completed,
           u.email_confirmed_at IS NOT NULL AS email_verified
    FROM public.departments AS d
    LEFT JOIN public.profiles AS p ON p.department_id = d.id AND p.role::text IN ('employee', 'manager')
    LEFT JOIN auth.users AS u ON u.id = p.id
    UNION ALL
    SELECT NULL::uuid, NULL::text, p.id,
           NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', p.first_name, p.last_name)), ''),
           p.role::text, p.department_level, p.approval_status::text,
           p.employment_status::text, p.registration_completed,
           u.email_confirmed_at IS NOT NULL
    FROM public.profiles AS p
    LEFT JOIN auth.users AS u ON u.id = p.id
    WHERE p.department_id IS NULL AND p.role::text IN ('employee', 'manager')
  )
  SELECT * FROM assignment_rows
  ORDER BY department_name NULLS FIRST, display_name NULLS LAST, user_id;
END;
$function$;
ALTER FUNCTION public.northstar_admin_list_department_management() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_list_department_management() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_department_management() TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_admin_set_department_head(
  p_department_id uuid, p_user_id uuid, p_outgoing_department_level smallint
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE
  current_head_id uuid;
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated administrator may change department heads.' USING ERRCODE = '42501';
  END IF;
  IF p_department_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'Choose a department and an eligible employee.' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_department_id::text, 0));
  PERFORM 1 FROM public.departments WHERE id = p_department_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Department was not found.' USING ERRCODE = 'P0002'; END IF;

  PERFORM 1 FROM public.profiles AS candidate
  JOIN auth.users AS user_row ON user_row.id = candidate.id
  WHERE candidate.id = p_user_id AND candidate.department_id = p_department_id
    AND candidate.role::text IN ('employee', 'manager')
    AND candidate.registration_completed IS TRUE
    AND candidate.approval_status::text = 'approved'
    AND candidate.employment_status::text = 'active'
    AND user_row.email_confirmed_at IS NOT NULL
  FOR UPDATE OF candidate;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The proposed head must be a confirmed, approved, active employee or manager assigned to this department.' USING ERRCODE = '22023';
  END IF;

  SELECT profile.id INTO current_head_id
  FROM public.profiles AS profile
  WHERE profile.department_id = p_department_id AND profile.department_level = 1
    AND profile.role::text IN ('employee', 'manager')
    AND profile.registration_completed IS TRUE
    AND profile.approval_status::text = 'approved'
    AND profile.employment_status::text = 'active'
  FOR UPDATE;

  IF current_head_id = p_user_id THEN
    IF p_outgoing_department_level IS NOT NULL THEN
      RAISE EXCEPTION 'The selected employee is already this department head.' USING ERRCODE = '22023';
    END IF;
    RETURN;
  END IF;
  IF current_head_id IS NOT NULL THEN
    IF p_outgoing_department_level IS NULL OR p_outgoing_department_level NOT BETWEEN 2 AND 5 THEN
      RAISE EXCEPTION 'Choose a replacement rank from Level 2 to Level 5 for the current head.' USING ERRCODE = '22023';
    END IF;
    PERFORM public.northstar_admin_assign_department_level(current_head_id, p_department_id, p_outgoing_department_level);
  ELSIF p_outgoing_department_level IS NOT NULL THEN
    RAISE EXCEPTION 'There is no current head to replace.' USING ERRCODE = '22023';
  END IF;

  PERFORM public.northstar_admin_assign_department_level(p_user_id, p_department_id, 1);
END;
$function$;
ALTER FUNCTION public.northstar_admin_set_department_head(uuid, uuid, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_set_department_head(uuid, uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_set_department_head(uuid, uuid, smallint) TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_admin_approve_employee_with_department_level(
  p_user_id uuid, p_department_level smallint,
  p_replace_current_head boolean, p_outgoing_department_level smallint
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE
  candidate_department_id uuid;
  current_head_id uuid;
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated administrator may approve registrations and assign department levels.' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_department_level IS NULL OR p_department_level NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Select a department rank from Level 1 to Level 5 before approving.' USING ERRCODE = '22023';
  END IF;
  IF p_replace_current_head IS DISTINCT FROM (p_outgoing_department_level IS NOT NULL) THEN
    RAISE EXCEPTION 'The current department head replacement details are incomplete.' USING ERRCODE = '22023';
  END IF;

  SELECT candidate.department_id INTO candidate_department_id
  FROM public.profiles AS candidate
  JOIN auth.users AS user_row ON user_row.id = candidate.id
  WHERE candidate.id = p_user_id AND candidate.registration_completed IS TRUE
    AND candidate.approval_status::text = 'pending'
    AND candidate.employment_status::text = 'inactive'
    AND candidate.role::text IN ('employee', 'manager')
    AND candidate.department_id IS NOT NULL
    AND user_row.email_confirmed_at IS NOT NULL
  FOR UPDATE OF candidate;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an email-confirmed, completed pending registration with an assigned department can be approved.' USING ERRCODE = '22023';
  END IF;

  IF p_department_level = 1 THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(candidate_department_id::text, 0));
    PERFORM 1 FROM public.departments WHERE id = candidate_department_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'The employee assigned department no longer exists.' USING ERRCODE = 'P0002'; END IF;
    SELECT profile.id INTO current_head_id
    FROM public.profiles AS profile
    WHERE profile.department_id = candidate_department_id AND profile.department_level = 1
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
    FOR UPDATE;
    IF current_head_id IS NOT NULL AND NOT p_replace_current_head THEN
      RAISE EXCEPTION 'This department already has a head. Confirm the replacement and choose the outgoing head rank.' USING ERRCODE = '23505';
    END IF;
    IF current_head_id IS NULL AND p_replace_current_head THEN
      RAISE EXCEPTION 'The department head changed while this approval was open. Refresh and review the assignment again.' USING ERRCODE = '40001';
    END IF;
    IF current_head_id IS NOT NULL THEN
      IF p_outgoing_department_level IS NULL OR p_outgoing_department_level NOT BETWEEN 2 AND 5 THEN
        RAISE EXCEPTION 'Choose a replacement rank from Level 2 to Level 5 for the current head.' USING ERRCODE = '22023';
      END IF;
      PERFORM public.northstar_admin_assign_department_level(current_head_id, candidate_department_id, p_outgoing_department_level);
    END IF;
  ELSIF p_replace_current_head OR p_outgoing_department_level IS NOT NULL THEN
    RAISE EXCEPTION 'Head replacement details may only be supplied when approving a Level 1 department head.' USING ERRCODE = '22023';
  END IF;

  PERFORM public.northstar_admin_update_employee_registration_status(
    p_user_id, 'approved', NULL, ARRAY[]::text[]
  );
  PERFORM public.northstar_admin_assign_department_level(p_user_id, candidate_department_id, p_department_level);
END;
$function$;
ALTER FUNCTION public.northstar_admin_approve_employee_with_department_level(uuid, smallint, boolean, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_approve_employee_with_department_level(uuid, smallint, boolean, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_approve_employee_with_department_level(uuid, smallint, boolean, smallint) TO authenticated;

DO $acl_check$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_admin_list_department_management()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_admin_approve_employee_with_department_level(uuid,smallint,boolean,smallint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Department management RPCs must not be executable by anon.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_admin_list_department_management()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.northstar_admin_approve_employee_with_department_level(uuid,smallint,boolean,smallint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated callers must be able to invoke the guarded department management RPCs.';
  END IF;
END;
$acl_check$;

COMMIT;
