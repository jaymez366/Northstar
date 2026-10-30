-- NorthStar department levels, department scoped collaboration, and access.
-- Apply after reviewing the live schema. This migration deliberately fails
-- closed when the existing application table contract differs.
BEGIN;

DO $preflight$
DECLARE
  missing text;
  restrictive_policies text;
BEGIN
  SELECT string_agg(required.table_name || '.' || required.column_name, ', ' ORDER BY required.table_name, required.column_name)
  INTO missing
  FROM (VALUES
    ('profiles', 'id'), ('profiles', 'department_id'), ('profiles', 'role'),
    ('profiles', 'approval_status'), ('profiles', 'employment_status'), ('profiles', 'registration_completed'),
    ('departments', 'id'), ('departments', 'name'),
    ('announcements', 'id'), ('announcements', 'title'), ('announcements', 'content'), ('announcements', 'author_id'), ('announcements', 'department_id'), ('announcements', 'created_at'), ('announcements', 'is_pinned'),
    ('events', 'id'), ('events', 'title'), ('events', 'organizer_id'), ('events', 'department_id'), ('events', 'start_time'), ('events', 'created_at'),
    ('event_attendees', 'event_id'), ('event_attendees', 'user_id'), ('event_attendees', 'attendance_status'),
    ('resources', 'id'), ('resources', 'title'), ('resources', 'storage_path'), ('resources', 'uploaded_by'), ('resources', 'department_id'), ('resources', 'created_at'),
    ('northstar_incidents', 'id'), ('northstar_incidents', 'reported_by'), ('northstar_incidents', 'status'), ('northstar_incidents', 'deleted_at'), ('northstar_incident_updates', 'id'), ('northstar_incident_updates', 'incident_id')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS actual
    WHERE actual.table_schema = 'public' AND actual.table_name = required.table_name AND actual.column_name = required.column_name
  );
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'NorthStar department migration preflight failed; missing public columns: %', missing;
  END IF;
  IF to_regclass('storage.objects') IS NULL OR to_regclass('storage.buckets') IS NULL THEN
    RAISE EXCEPTION 'NorthStar department migration preflight failed; Supabase Storage is unavailable.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'storage.objects'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'NorthStar department migration requires RLS enabled on storage.objects.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.polrelid = 'storage.objects'::regclass
      AND policy.polpermissive IS FALSE
      AND EXISTS (
        SELECT 1 FROM unnest(policy.polroles) AS target_role(role_oid)
        WHERE target_role.role_oid = 0
          OR pg_has_role('authenticated', target_role.role_oid, 'USAGE')
          OR pg_has_role('anon', target_role.role_oid, 'USAGE')
      )
      AND policy.polname <> ALL(ARRAY[
        'northstar_company_resources_department_guard',
        'northstar_company_resources_department_insert_guard',
        'northstar_company_resources_department_update_guard',
        'northstar_company_resources_department_delete_guard',
        'northstar_company_resources_anon_select_guard',
        'northstar_company_resources_anon_insert_guard',
        'northstar_company_resources_anon_update_guard',
        'northstar_company_resources_anon_delete_guard',
        'northstar_company_resources_insert_guard',
        'northstar_company_resources_update_guard',
        'northstar_company_resources_delete_guard',
        'northstar_message_attachments_upload_guard',
        'northstar_message_attachments_read_guard',
        'northstar_message_attachments_anon_read_guard',
        'northstar_message_attachments_anon_upload_guard',
        'northstar_message_attachments_no_update_guard',
        'northstar_message_attachments_no_delete_guard',
        'northstar_message_attachments_anon_no_update_guard',
        'northstar_message_attachments_anon_no_delete_guard',
        'northstar_profile_avatars_select_guard',
        'northstar_profile_avatars_anon_select_guard',
        'northstar_profile_avatars_insert_guard',
        'northstar_profile_avatars_anon_insert_guard'
      ])
  ) THEN
    RAISE EXCEPTION 'NorthStar department migration found an unreviewed restrictive Storage policy; inspect storage.objects policies before continuing.';
  END IF;
  -- Named Storage guards are accepted only when their table, command, role,
  -- restrictive status, bucket scope, and policy-specific security markers
  -- still match the definitions reviewed in the earlier NorthStar migrations.
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('northstar_company_resources_insert_guard', 'a'::char, 'authenticated'::name, 'company-resources', 'northstar_is_designated_admin', NULL::text),
      ('northstar_company_resources_update_guard', 'w'::char, 'authenticated'::name, 'company-resources', 'northstar_is_designated_admin', NULL::text),
      ('northstar_company_resources_delete_guard', 'd'::char, 'authenticated'::name, 'company-resources', 'northstar_is_designated_admin', NULL::text),
      ('northstar_message_attachments_upload_guard', 'a'::char, 'authenticated'::name, 'northstar-message-attachments', 'message_attachment_path_allowed', NULL::text),
      ('northstar_message_attachments_read_guard', 'r'::char, 'authenticated'::name, 'northstar-message-attachments', 'message_attachment_object_readable', NULL::text),
      ('northstar_message_attachments_anon_read_guard', 'r'::char, 'anon'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_message_attachments_anon_upload_guard', 'a'::char, 'anon'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_message_attachments_no_update_guard', 'w'::char, 'authenticated'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_message_attachments_no_delete_guard', 'd'::char, 'authenticated'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_message_attachments_anon_no_update_guard', 'w'::char, 'anon'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_message_attachments_anon_no_delete_guard', 'd'::char, 'anon'::name, 'northstar-message-attachments', NULL::text, NULL::text),
      ('northstar_profile_avatars_select_guard', 'r'::char, 'authenticated'::name, 'profile-avatars', 'northstar_is_designated_admin', 'avatar_url'),
      ('northstar_profile_avatars_anon_select_guard', 'r'::char, 'anon'::name, 'profile-avatars', NULL::text, NULL::text),
      ('northstar_profile_avatars_insert_guard', 'a'::char, 'authenticated'::name, 'profile-avatars', 'split_part', 'owner_id'),
      ('northstar_profile_avatars_anon_insert_guard', 'a'::char, 'anon'::name, 'profile-avatars', NULL::text, NULL::text)
    ) AS expected(policy_name, command, role_name, bucket_name, marker_one, marker_two)
    LEFT JOIN pg_policy AS policy ON policy.polrelid = 'storage.objects'::regclass
      AND policy.polname = expected.policy_name
    WHERE policy.oid IS NULL OR policy.polpermissive IS TRUE
      OR policy.polcmd <> expected.command
      OR policy.polroles <> ARRAY[expected.role_name::regrole::oid]
      OR CASE expected.command
        WHEN 'a' THEN pg_get_expr(policy.polwithcheck, policy.polrelid)
        WHEN 'w' THEN coalesce(pg_get_expr(policy.polqual, policy.polrelid), '') || ' ' || coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ELSE pg_get_expr(policy.polqual, policy.polrelid)
      END NOT ILIKE '%' || expected.bucket_name || '%'
      OR (expected.marker_one IS NOT NULL AND CASE expected.command
        WHEN 'a' THEN coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        WHEN 'w' THEN coalesce(pg_get_expr(policy.polqual, policy.polrelid), '') || ' ' || coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ELSE coalesce(pg_get_expr(policy.polqual, policy.polrelid), '')
      END NOT ILIKE '%' || expected.marker_one || '%')
      OR (expected.marker_two IS NOT NULL AND CASE expected.command
        WHEN 'a' THEN coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        WHEN 'w' THEN coalesce(pg_get_expr(policy.polqual, policy.polrelid), '') || ' ' || coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ELSE coalesce(pg_get_expr(policy.polqual, policy.polrelid), '')
      END NOT ILIKE '%' || expected.marker_two || '%')
  ) THEN
    RAISE EXCEPTION 'A recognized NorthStar Storage policy is missing or differs from its reviewed table, command, role, bucket, or security markers.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'company-resources' AND public IS FALSE) THEN
    RAISE EXCEPTION 'NorthStar department migration requires the existing company-resources bucket to exist and remain private.';
  END IF;
  IF to_regprocedure('public.northstar_is_designated_admin()') IS NULL THEN
    RAISE EXCEPTION 'NorthStar department migration requires public.northstar_is_designated_admin().';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.announcements'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.events'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.resources'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.northstar_incidents'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.northstar_incident_updates'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'NorthStar department migration requires RLS enabled on the existing content and incident tables.';
  END IF;
  SELECT string_agg(format('%s.%s', relation.relname, policy.polname), ', ' ORDER BY relation.relname, policy.polname)
  INTO restrictive_policies
  FROM pg_policy AS policy
  JOIN pg_class AS relation ON relation.oid = policy.polrelid
  WHERE policy.polrelid IN (
      'public.announcements'::regclass, 'public.events'::regclass, 'public.resources'::regclass,
      'public.event_attendees'::regclass, 'public.northstar_incidents'::regclass,
      'public.northstar_incident_updates'::regclass
    )
    AND policy.polpermissive IS FALSE
    AND EXISTS (
      SELECT 1 FROM unnest(policy.polroles) AS target_role(role_oid)
      WHERE target_role.role_oid = 0 OR pg_has_role('authenticated', target_role.role_oid, 'USAGE')
    )
    AND NOT (
      (relation.relname = 'events' AND policy.polname = ANY(ARRAY[
        'northstar_events_designated_admin_insert_guard',
        'northstar_events_designated_admin_update_guard',
        'northstar_events_designated_admin_delete_guard'
      ]))
      OR (relation.relname = 'resources' AND policy.polname = ANY(ARRAY[
        'northstar_resources_designated_admin_insert_guard',
        'northstar_resources_designated_admin_update_guard',
        'northstar_resources_designated_admin_delete_guard'
      ]))
    );
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('events', 'northstar_events_designated_admin_insert_guard', 'a'::char),
      ('events', 'northstar_events_designated_admin_update_guard', 'w'::char),
      ('events', 'northstar_events_designated_admin_delete_guard', 'd'::char),
      ('resources', 'northstar_resources_designated_admin_insert_guard', 'a'::char),
      ('resources', 'northstar_resources_designated_admin_update_guard', 'w'::char),
      ('resources', 'northstar_resources_designated_admin_delete_guard', 'd'::char)
    ) AS expected(table_name, policy_name, command)
    LEFT JOIN pg_class AS relation ON relation.relnamespace = 'public'::regnamespace
      AND relation.relname = expected.table_name
    LEFT JOIN pg_policy AS policy ON policy.polrelid = relation.oid AND policy.polname = expected.policy_name
    WHERE policy.oid IS NULL OR policy.polpermissive IS TRUE
      OR policy.polcmd <> expected.command
      OR policy.polroles <> ARRAY['authenticated'::regrole::oid]
      OR CASE expected.command
        WHEN 'a' THEN CASE
          WHEN expected.table_name = 'resources' THEN replace(
            replace(
              replace(regexp_replace(lower(pg_get_expr(policy.polwithcheck, policy.polrelid)), '[[:space:]()]', '', 'g'), 'public.', ''),
              'select', ''
            ),
            'asuid', ''
          )
          ELSE replace(regexp_replace(lower(pg_get_expr(policy.polwithcheck, policy.polrelid)), '[[:space:]()]', '', 'g'), 'public.', '')
        END
                    IS DISTINCT FROM CASE
                      WHEN expected.table_name = 'resources' THEN 'uploaded_by=auth.uidandnorthstar_is_designated_admin'
                      ELSE 'northstar_is_designated_admin'
                    END
        WHEN 'w' THEN replace(regexp_replace(lower(pg_get_expr(policy.polqual, policy.polrelid)), '[[:space:]()]', '', 'g'), 'public.', '')
                    IS DISTINCT FROM 'northstar_is_designated_admin'
                  OR replace(regexp_replace(lower(pg_get_expr(policy.polwithcheck, policy.polrelid)), '[[:space:]()]', '', 'g'), 'public.', '')
                    IS DISTINCT FROM 'northstar_is_designated_admin'
        WHEN 'd' THEN replace(regexp_replace(lower(pg_get_expr(policy.polqual, policy.polrelid)), '[[:space:]()]', '', 'g'), 'public.', '')
                    IS DISTINCT FROM 'northstar_is_designated_admin'
      END
  ) THEN
    RAISE EXCEPTION 'Expected six authenticated restrictive guards on events and resources with designated-admin-only predicates; a named guard is missing or has an unexpected table, command, role, predicate, or permissive setting.';
  END IF;
  IF restrictive_policies IS NOT NULL THEN
    RAISE EXCEPTION 'NorthStar department migration found additional restrictive client policies that must be reviewed before continuing: %', restrictive_policies;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE oid IN (
    'public.profiles'::regclass, 'public.departments'::regclass, 'public.resources'::regclass,
    'public.northstar_incidents'::regclass, 'public.northstar_incident_updates'::regclass
  ) AND relforcerowsecurity) THEN
    RAISE EXCEPTION 'NorthStar department migration requires the SECURITY DEFINER helper tables not to FORCE ROW LEVEL SECURITY.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE department_id IS NULL AND COALESCE(approval_status::text, '') = 'approved'
      AND COALESCE(employment_status::text, '') = 'active' AND registration_completed IS TRUE
  ) THEN
    RAISE NOTICE 'Some active profiles have no department. They will remain outside department collaboration until assigned by the designated administrator.';
  END IF;
END;
$preflight$;

-- Create the incident department column before any migration object can refer
-- to it, including provenance functions and UPDATE OF triggers.
ALTER TABLE public.northstar_incidents
  ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES public.departments(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS northstar_incidents_department_time_idx
  ON public.northstar_incidents(department_id, reported_at DESC);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS department_level smallint;
DO $level_constraint$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.profiles'::regclass AND conname = 'northstar_profiles_department_level_check') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT northstar_profiles_department_level_check
      CHECK (department_level IS NULL OR department_level BETWEEN 1 AND 5);
  END IF;
END;
$level_constraint$;

CREATE UNIQUE INDEX IF NOT EXISTS northstar_one_active_department_head_uidx
  ON public.profiles (department_id)
  WHERE department_id IS NOT NULL AND department_level = 1
    AND role::text IN ('employee', 'manager')
    AND approval_status::text = 'approved' AND employment_status::text = 'active'
    AND registration_completed IS TRUE;

CREATE SCHEMA IF NOT EXISTS northstar_private;
REVOKE ALL ON SCHEMA northstar_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA northstar_private TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.protect_department_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $function$
BEGIN
  IF NEW.department_level IS NOT NULL AND (
    COALESCE(NEW.role::text, '') NOT IN ('employee', 'manager')
    OR NEW.approval_status::text IS DISTINCT FROM 'approved'
    OR NEW.employment_status::text IS DISTINCT FROM 'active' OR NEW.registration_completed IS NOT TRUE
  ) THEN
    NEW.department_level := NULL;
  END IF;

  IF current_user IN ('authenticated', 'anon') AND TG_OP = 'INSERT' THEN
    IF NEW.department_level IS NOT NULL THEN
      RAISE EXCEPTION 'Department levels can only be assigned by the designated administrator.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF current_user IN ('authenticated', 'anon')
     AND TG_OP = 'UPDATE'
     AND (NEW.department_id IS DISTINCT FROM OLD.department_id OR NEW.department_level IS DISTINCT FROM OLD.department_level) THEN
    IF OLD.registration_completed IS FALSE
       AND OLD.approval_status::text = 'pending'
       AND NEW.approval_status::text = 'pending'
       AND NEW.employment_status::text = 'inactive'
       AND NEW.department_level IS NULL THEN
      RETURN NEW;
    END IF;
    IF OLD.approval_status::text = 'rejected'
       AND NEW.approval_status::text = 'pending'
       AND NEW.employment_status::text = 'inactive'
       AND NEW.department_level IS NULL THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Department and level assignments can only be changed by the designated administrator.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION northstar_private.protect_department_assignment() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS northstar_profiles_protect_department_assignment ON public.profiles;
CREATE TRIGGER northstar_profiles_protect_department_assignment BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION northstar_private.protect_department_assignment();

CREATE OR REPLACE FUNCTION northstar_private.is_eligible_department_member(p_department_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT auth.uid() IS NOT NULL AND p_department_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.profiles AS p JOIN auth.users AS u ON u.id = p.id
    WHERE p.id = auth.uid() AND p.role::text IN ('employee', 'manager') AND p.department_id = p_department_id
      AND p.department_level BETWEEN 1 AND 5 AND p.registration_completed IS TRUE
      AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active'
      AND u.email_confirmed_at IS NOT NULL
  );
$function$;
ALTER FUNCTION northstar_private.is_eligible_department_member(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_eligible_department_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_eligible_department_member(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.is_eligible_workspace_user()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.profiles p JOIN auth.users u ON u.id = p.id
    WHERE p.id = auth.uid() AND p.role::text IN ('employee', 'manager')
      AND p.registration_completed IS TRUE AND p.approval_status::text = 'approved'
      AND p.employment_status::text = 'active' AND u.email_confirmed_at IS NOT NULL
  );
$function$;
ALTER FUNCTION northstar_private.is_eligible_workspace_user() OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_eligible_workspace_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_eligible_workspace_user() TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.is_department_head(p_department_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT northstar_private.is_eligible_department_member(p_department_id) AND EXISTS (
    SELECT 1 FROM public.profiles AS p WHERE p.id = auth.uid() AND p.department_id = p_department_id AND p.department_level = 1
  );
$function$;
ALTER FUNCTION northstar_private.is_department_head(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_department_head(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_department_head(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.is_department_member_or_admin(p_department_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT public.northstar_is_designated_admin() OR northstar_private.is_eligible_department_member(p_department_id);
$function$;
ALTER FUNCTION northstar_private.is_department_member_or_admin(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_department_member_or_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_department_member_or_admin(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_admin_list_department_assignments()
RETURNS TABLE (department_id uuid, department_name text, user_id uuid, display_name text, role text, department_level smallint, approval_status text, employment_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN RAISE EXCEPTION 'Only the designated administrator may manage department assignments.' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  WITH assignment_rows AS (
    SELECT d.id AS department_id, d.name::text AS department_name, p.id AS user_id,
      NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', p.first_name, p.last_name)), '') AS display_name,
      p.role::text AS role, p.department_level, p.approval_status::text AS approval_status, p.employment_status::text AS employment_status
    FROM public.profiles AS p LEFT JOIN public.departments AS d ON d.id = p.department_id
    WHERE p.role::text IN ('employee', 'manager')
    UNION ALL
    SELECT d.id, d.name::text, NULL::uuid, NULL::text, NULL::text, NULL::smallint, NULL::text, NULL::text
    FROM public.departments AS d
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles AS p WHERE p.department_id = d.id)
  )
  SELECT * FROM assignment_rows ORDER BY department_name NULLS LAST, display_name NULLS LAST;
END;
$function$;
ALTER FUNCTION public.northstar_admin_list_department_assignments() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_list_department_assignments() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_department_assignments() TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_admin_assign_department_level(p_user_id uuid, p_department_id uuid, p_department_level smallint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN RAISE EXCEPTION 'Only the designated administrator may change department assignments.' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL OR (p_department_id IS NULL) <> (p_department_level IS NULL)
     OR (p_department_level IS NOT NULL AND p_department_level NOT BETWEEN 1 AND 5) THEN
    RAISE EXCEPTION 'Choose a valid employee, department, and level.' USING ERRCODE = '22023';
  END IF;
  IF p_department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id = p_department_id) THEN
    RAISE EXCEPTION 'Department was not found.' USING ERRCODE = 'P0002';
  END IF;
  IF p_department_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles AS p JOIN auth.users AS u ON u.id = p.id
    WHERE p.id = p_user_id AND p.registration_completed IS TRUE AND p.approval_status::text = 'approved'
      AND p.employment_status::text = 'active' AND p.role::text IN ('employee', 'manager') AND u.email_confirmed_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'Only confirmed, approved, active employees and managers can receive department levels.' USING ERRCODE = '22023'; END IF;
  UPDATE public.profiles SET department_id = p_department_id, department_level = p_department_level WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Employee profile was not found.' USING ERRCODE = 'P0002'; END IF;
END;
$function$;
ALTER FUNCTION public.northstar_admin_assign_department_level(uuid, uuid, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_assign_department_level(uuid, uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_assign_department_level(uuid, uuid, smallint) TO authenticated;

-- Extend the verified administrator guards instead of adding restrictive
-- policies that would be ANDed with them and continue to block department
-- heads. Preserve each complete existing predicate as one branch.
DO $extend_department_head_guards$
DECLARE
  guard_row record;
  head_predicate text;
BEGIN
  FOR guard_row IN
    SELECT expected.table_name, expected.policy_name, expected.command,
           pg_get_expr(policy.polqual, policy.polrelid) AS old_using,
           pg_get_expr(policy.polwithcheck, policy.polrelid) AS old_check
    FROM (VALUES
      ('events', 'northstar_events_designated_admin_insert_guard', 'a'::char),
      ('events', 'northstar_events_designated_admin_update_guard', 'w'::char),
      ('events', 'northstar_events_designated_admin_delete_guard', 'd'::char),
      ('resources', 'northstar_resources_designated_admin_insert_guard', 'a'::char),
      ('resources', 'northstar_resources_designated_admin_update_guard', 'w'::char),
      ('resources', 'northstar_resources_designated_admin_delete_guard', 'd'::char)
    ) AS expected(table_name, policy_name, command)
    JOIN pg_class AS relation ON relation.relnamespace = 'public'::regnamespace
      AND relation.relname = expected.table_name
    JOIN pg_policy AS policy ON policy.polrelid = relation.oid
      AND policy.polname = expected.policy_name
  LOOP
    head_predicate := CASE
      WHEN guard_row.table_name = 'events' AND guard_row.command = 'a' THEN
        '(organizer_id = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id))'
      WHEN guard_row.table_name = 'resources' AND guard_row.command = 'a' THEN
        '(uploaded_by = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id))'
      ELSE 'northstar_private.is_department_head(department_id)'
    END;

    IF guard_row.command = 'a' THEN
      EXECUTE format(
        'ALTER POLICY %I ON public.%I WITH CHECK ((%s) OR (%s))',
        guard_row.policy_name, guard_row.table_name, guard_row.old_check, head_predicate
      );
    ELSIF guard_row.command = 'w' THEN
      EXECUTE format(
        'ALTER POLICY %I ON public.%I USING ((%s) OR (%s)) WITH CHECK ((%s) OR (%s))',
        guard_row.policy_name, guard_row.table_name,
        guard_row.old_using, head_predicate,
        guard_row.old_check, head_predicate
      );
    ELSE
      EXECUTE format(
        'ALTER POLICY %I ON public.%I USING ((%s) OR (%s))',
        guard_row.policy_name, guard_row.table_name, guard_row.old_using, head_predicate
      );
    END IF;
  END LOOP;
END;
$extend_department_head_guards$;

CREATE TABLE IF NOT EXISTS public.northstar_department_discussion_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  parent_id uuid REFERENCES public.northstar_department_discussion_posts(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (length(btrim(content)) BETWEEN 1 AND 10000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS northstar_department_discussion_timeline_idx
  ON public.northstar_department_discussion_posts (department_id, created_at DESC);

CREATE OR REPLACE FUNCTION northstar_private.guard_department_discussion_post()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.author_id IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'Discussion author must be the authenticated user.' USING ERRCODE = '42501';
    END IF;
  ELSIF NOT public.northstar_is_designated_admin() THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.department_id IS DISTINCT FROM OLD.department_id
       OR NEW.author_id IS DISTINCT FROM OLD.author_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Discussion identity, department, and creation time cannot be changed.' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF NEW.parent_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.northstar_department_discussion_posts AS parent
    WHERE parent.id = NEW.parent_id AND parent.department_id = NEW.department_id
  ) THEN
    RAISE EXCEPTION 'A discussion reply must belong to the same department thread.' USING ERRCODE = '22023';
  END IF;
  NEW.updated_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION northstar_private.guard_department_discussion_post() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS northstar_department_discussion_post_guard ON public.northstar_department_discussion_posts;
CREATE TRIGGER northstar_department_discussion_post_guard
BEFORE INSERT OR UPDATE ON public.northstar_department_discussion_posts
FOR EACH ROW EXECUTE FUNCTION northstar_private.guard_department_discussion_post();

ALTER TABLE public.northstar_department_discussion_posts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_department_discussion_posts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.northstar_department_discussion_posts TO authenticated;
DROP POLICY IF EXISTS northstar_department_discussion_read ON public.northstar_department_discussion_posts;
CREATE POLICY northstar_department_discussion_read ON public.northstar_department_discussion_posts FOR SELECT TO authenticated
USING (northstar_private.is_department_member_or_admin(department_id));
DROP POLICY IF EXISTS northstar_department_discussion_insert ON public.northstar_department_discussion_posts;
CREATE POLICY northstar_department_discussion_insert ON public.northstar_department_discussion_posts FOR INSERT TO authenticated
WITH CHECK (author_id = (SELECT auth.uid()) AND northstar_private.is_eligible_department_member(department_id)
  AND (parent_id IS NULL OR EXISTS (SELECT 1 FROM public.northstar_department_discussion_posts AS parent
    WHERE parent.id = northstar_department_discussion_posts.parent_id AND parent.department_id = northstar_department_discussion_posts.department_id)));
DROP POLICY IF EXISTS northstar_department_discussion_update ON public.northstar_department_discussion_posts;
CREATE POLICY northstar_department_discussion_update ON public.northstar_department_discussion_posts FOR UPDATE TO authenticated
USING ((author_id = (SELECT auth.uid()) AND northstar_private.is_eligible_department_member(department_id))
  OR northstar_private.is_department_head(department_id) OR public.northstar_is_designated_admin())
WITH CHECK (northstar_private.is_department_member_or_admin(department_id)
  AND (author_id = (SELECT auth.uid()) OR northstar_private.is_department_head(department_id) OR public.northstar_is_designated_admin()));
DROP POLICY IF EXISTS northstar_department_discussion_delete ON public.northstar_department_discussion_posts;
CREATE POLICY northstar_department_discussion_delete ON public.northstar_department_discussion_posts FOR DELETE TO authenticated
USING ((author_id = (SELECT auth.uid()) AND northstar_private.is_eligible_department_member(department_id))
  OR northstar_private.is_department_head(department_id) OR public.northstar_is_designated_admin());

-- Existing company-wide records remain readable subject to their prior RLS.
-- These restrictive policies add department boundaries without replacing the
-- existing permissive policies or granting new table access to anon.
DO $content_policy_preflight$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('announcements', 'northstar_department_announcements_guard'),
      ('announcements', 'northstar_department_announcements_select'),
      ('announcements', 'northstar_department_announcements_insert_guard'),
      ('announcements', 'northstar_department_announcements_insert_policy'),
      ('announcements', 'northstar_department_announcements_update_policy'),
      ('announcements', 'northstar_department_announcements_delete_policy'),
      ('announcements', 'northstar_department_announcements_delete_guard'),
      ('announcements', 'northstar_department_announcements_update_guard'),
      ('events', 'northstar_department_events_guard'),
      ('events', 'northstar_department_events_select_policy'),
      ('events', 'northstar_department_events_insert_policy'),
      ('events', 'northstar_department_events_update_policy'),
      ('events', 'northstar_department_events_delete_policy'),
      ('events', 'northstar_department_events_insert_guard'),
      ('events', 'northstar_department_events_update_guard'),
      ('events', 'northstar_department_events_delete_guard'),
      ('resources', 'northstar_department_resources_guard'),
      ('resources', 'northstar_department_resources_select_policy'),
      ('resources', 'northstar_department_resources_insert_policy'),
      ('resources', 'northstar_department_resources_update_policy'),
      ('resources', 'northstar_department_resources_delete_policy'),
      ('resources', 'northstar_department_resources_insert_guard'),
      ('resources', 'northstar_department_resources_update_guard'),
      ('resources', 'northstar_department_resources_delete_guard'),
      ('event_attendees', 'northstar_department_event_attendees_select'),
      ('event_attendees', 'northstar_department_event_attendees_insert'),
      ('event_attendees', 'northstar_department_event_attendees_update'),
      ('event_attendees', 'northstar_department_event_attendees_delete'),
      ('event_attendees', 'northstar_department_event_attendees_guard'),
      ('northstar_incidents', 'northstar_incidents_department_guard'),
      ('northstar_incident_updates', 'northstar_incident_updates_department_guard')
    ) AS expected(table_name, policy_name)
    JOIN pg_class AS relation ON relation.relnamespace = 'public'::regnamespace
      AND relation.relname = expected.table_name
    JOIN pg_policy AS policy ON policy.polrelid = relation.oid
      AND policy.polname = expected.policy_name
  ) THEN
    RAISE EXCEPTION 'A NorthStar department policy name is already in use; verify migration history and inspect the conflicting policy before continuing.';
  END IF;
END;
$content_policy_preflight$;

CREATE POLICY northstar_department_announcements_guard ON public.announcements AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_announcements_select ON public.announcements FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_announcements_insert_guard ON public.announcements AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (author_id = (SELECT auth.uid()) AND
  ((department_id IS NULL AND northstar_private.is_eligible_workspace_user()
      AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role::text = 'employee'))
   OR (department_id IS NOT NULL AND northstar_private.is_department_head(department_id)))));
CREATE POLICY northstar_department_announcements_insert_policy ON public.announcements FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (author_id = (SELECT auth.uid()) AND
  ((department_id IS NULL AND northstar_private.is_eligible_workspace_user()
      AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role::text = 'employee'))
   OR (department_id IS NOT NULL AND northstar_private.is_department_head(department_id)))));
CREATE POLICY northstar_department_announcements_update_policy ON public.announcements FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role::text = 'manager')) OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR department_id IS NULL OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_announcements_delete_policy ON public.announcements FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_announcements_delete_guard ON public.announcements AS RESTRICTIVE FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
REVOKE ALL ON public.announcements FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.announcements TO authenticated;
REVOKE UPDATE ON public.announcements FROM authenticated;
DO $announcement_column_update_acl$
DECLARE
  all_columns text;
  restricted_columns text;
BEGIN
  SELECT string_agg(format('%I', attribute.attname), ', ' ORDER BY attribute.attnum)
  INTO all_columns
  FROM pg_attribute AS attribute
  WHERE attribute.attrelid = 'public.announcements'::regclass
    AND attribute.attnum > 0 AND NOT attribute.attisdropped;

  IF all_columns IS NOT NULL THEN
    EXECUTE format('REVOKE ALL PRIVILEGES (%s) ON public.announcements FROM PUBLIC, anon', all_columns);
  END IF;

  SELECT string_agg(format('%I', attribute.attname), ', ' ORDER BY attribute.attnum)
  INTO restricted_columns
  FROM pg_attribute AS attribute
  WHERE attribute.attrelid = 'public.announcements'::regclass
    AND attribute.attnum > 0 AND NOT attribute.attisdropped
    AND attribute.attname <> 'is_pinned'
    AND has_column_privilege('authenticated', attribute.attrelid, attribute.attnum, 'UPDATE');

  IF restricted_columns IS NOT NULL THEN
    EXECUTE format('REVOKE UPDATE (%s) ON public.announcements FROM authenticated', restricted_columns);
  END IF;
END;
$announcement_column_update_acl$;
GRANT UPDATE (is_pinned) ON public.announcements TO authenticated;
CREATE POLICY northstar_department_announcements_update_guard ON public.announcements AS RESTRICTIVE FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role::text = 'manager')) OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR department_id IS NULL OR northstar_private.is_department_head(department_id));

CREATE POLICY northstar_department_events_guard ON public.events AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_events_select_policy ON public.events FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_events_insert_policy ON public.events FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (organizer_id = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id)));
CREATE POLICY northstar_department_events_update_policy ON public.events FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_events_delete_policy ON public.events FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
REVOKE ALL ON public.events FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO authenticated;
CREATE POLICY northstar_department_events_insert_guard ON public.events AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (organizer_id = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id)));
CREATE POLICY northstar_department_events_update_guard ON public.events AS RESTRICTIVE FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_events_delete_guard ON public.events AS RESTRICTIVE FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));

ALTER TABLE public.event_attendees ENABLE ROW LEVEL SECURITY;
CREATE POLICY northstar_department_event_attendees_select ON public.event_attendees FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  (public.northstar_is_designated_admin() OR (e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))));
CREATE POLICY northstar_department_event_attendees_insert ON public.event_attendees FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()) AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  ((e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))));
CREATE POLICY northstar_department_event_attendees_update ON public.event_attendees FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()) AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  ((e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))))
WITH CHECK (user_id = (SELECT auth.uid()) AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  ((e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))));
CREATE POLICY northstar_department_event_attendees_delete ON public.event_attendees FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()) AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  ((e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))));
CREATE POLICY northstar_department_event_attendees_guard ON public.event_attendees AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  (public.northstar_is_designated_admin() OR (e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))))
WITH CHECK (user_id = (SELECT auth.uid()) AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_id AND
  ((e.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
   OR northstar_private.is_eligible_department_member(e.department_id))));
REVOKE ALL ON public.event_attendees FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_attendees TO authenticated;

CREATE POLICY northstar_department_resources_guard ON public.resources AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_resources_select_policy ON public.resources FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (department_id IS NULL AND northstar_private.is_eligible_workspace_user()) OR northstar_private.is_eligible_department_member(department_id));
CREATE POLICY northstar_department_resources_insert_policy ON public.resources FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (uploaded_by = (SELECT auth.uid())
  AND northstar_private.is_department_head(department_id)
  AND storage_path LIKE ('departments/' || department_id::text || '/resources/%')));
CREATE POLICY northstar_department_resources_update_policy ON public.resources FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_resources_delete_policy ON public.resources FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
REVOKE ALL ON public.resources FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.resources TO authenticated;

DO $content_column_acl$
DECLARE
  target_table text;
  column_list text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'events', 'resources', 'event_attendees', 'northstar_department_discussion_posts'
  ] LOOP
    SELECT string_agg(format('%I', attribute.attname), ', ' ORDER BY attribute.attnum)
    INTO column_list
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = format('public.%I', target_table)::regclass
      AND attribute.attnum > 0 AND NOT attribute.attisdropped;

    IF column_list IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL PRIVILEGES (%s) ON public.%I FROM PUBLIC, anon',
        column_list, target_table
      );
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_class AS relation
    WHERE relation.oid IN (
      'public.events'::regclass, 'public.resources'::regclass, 'public.event_attendees'::regclass,
      'public.northstar_department_discussion_posts'::regclass
    )
      AND (has_table_privilege('anon', relation.oid, 'SELECT')
        OR has_table_privilege('anon', relation.oid, 'INSERT')
        OR has_table_privilege('anon', relation.oid, 'UPDATE')
        OR has_table_privilege('anon', relation.oid, 'DELETE'))
  ) OR EXISTS (
    SELECT 1 FROM pg_attribute AS attribute
    WHERE attribute.attrelid IN (
      'public.events'::regclass, 'public.resources'::regclass, 'public.event_attendees'::regclass,
      'public.northstar_department_discussion_posts'::regclass
    )
      AND attribute.attnum > 0 AND NOT attribute.attisdropped
      AND (has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'SELECT')
        OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'INSERT')
        OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'UPDATE')
        OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'REFERENCES'))
  ) THEN
    RAISE EXCEPTION 'Anonymous table or column grants remain on department events, resources, event attendees, or discussion posts.';
  END IF;
END;
$content_column_acl$;

CREATE POLICY northstar_department_resources_insert_guard ON public.resources AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (public.northstar_is_designated_admin() OR (uploaded_by = (SELECT auth.uid())
  AND northstar_private.is_department_head(department_id)
  AND storage_path LIKE ('departments/' || department_id::text || '/resources/%')));
CREATE POLICY northstar_department_resources_update_guard ON public.resources AS RESTRICTIVE FOR UPDATE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id))
WITH CHECK (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));
CREATE POLICY northstar_department_resources_delete_guard ON public.resources AS RESTRICTIVE FOR DELETE TO authenticated
USING (public.northstar_is_designated_admin() OR northstar_private.is_department_head(department_id));

DO $announcement_update_acl_verify$
BEGIN
  IF has_table_privilege('anon', 'public.announcements', 'SELECT')
     OR has_table_privilege('anon', 'public.announcements', 'INSERT')
     OR has_table_privilege('anon', 'public.announcements', 'UPDATE')
     OR has_table_privilege('anon', 'public.announcements', 'DELETE')
     OR EXISTS (
       SELECT 1 FROM pg_attribute AS attribute
       WHERE attribute.attrelid = 'public.announcements'::regclass
         AND attribute.attnum > 0 AND NOT attribute.attisdropped
         AND (has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'SELECT')
           OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'INSERT')
           OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'UPDATE')
           OR has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'REFERENCES'))
     )
     OR NOT has_column_privilege('authenticated', 'public.announcements', 'is_pinned', 'UPDATE')
     OR EXISTS (
       SELECT 1 FROM pg_attribute AS attribute
       WHERE attribute.attrelid = 'public.announcements'::regclass
         AND attribute.attnum > 0 AND NOT attribute.attisdropped
         AND has_column_privilege('anon', attribute.attrelid, attribute.attnum, 'UPDATE')
     )
     OR NOT has_column_privilege('authenticated', 'public.announcements', 'is_pinned', 'UPDATE')
     OR EXISTS (
       SELECT 1 FROM pg_attribute AS attribute
       WHERE attribute.attrelid = 'public.announcements'::regclass
         AND attribute.attnum > 0 AND NOT attribute.attisdropped
         AND attribute.attname <> 'is_pinned'
         AND has_column_privilege('authenticated', attribute.attrelid, attribute.attnum, 'UPDATE')
     ) THEN
    RAISE EXCEPTION 'Announcement UPDATE grants must allow is_pinned only for authenticated clients.';
  END IF;
END;
$announcement_update_acl_verify$;

CREATE OR REPLACE FUNCTION northstar_private.protect_department_content_provenance()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $function$
BEGIN
  IF public.northstar_is_designated_admin() THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME = 'announcements' THEN
    IF NEW.author_id IS DISTINCT FROM OLD.author_id OR NEW.department_id IS DISTINCT FROM OLD.department_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Announcement author, department, and creation time cannot be changed.' USING ERRCODE = '42501';
    END IF;
  ELSIF TG_TABLE_NAME = 'events' THEN
    IF NEW.organizer_id IS DISTINCT FROM OLD.organizer_id OR NEW.department_id IS DISTINCT FROM OLD.department_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Event organizer, department, and creation time cannot be changed.' USING ERRCODE = '42501';
    END IF;
  ELSIF TG_TABLE_NAME = 'resources' THEN
    IF NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by OR NEW.department_id IS DISTINCT FROM OLD.department_id
       OR NEW.storage_path IS DISTINCT FROM OLD.storage_path OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Resource ownership, department, storage path, and creation time cannot be changed.' USING ERRCODE = '42501';
    END IF;
  ELSIF TG_TABLE_NAME = 'northstar_incidents' THEN
    IF NEW.reported_by IS DISTINCT FROM OLD.reported_by OR NEW.department_id IS DISTINCT FROM OLD.department_id THEN
      RAISE EXCEPTION 'Incident reporter and department cannot be changed.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION northstar_private.protect_department_content_provenance() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS northstar_announcement_provenance_guard ON public.announcements;
CREATE TRIGGER northstar_announcement_provenance_guard BEFORE UPDATE ON public.announcements
FOR EACH ROW EXECUTE FUNCTION northstar_private.protect_department_content_provenance();
DROP TRIGGER IF EXISTS northstar_event_provenance_guard ON public.events;
CREATE TRIGGER northstar_event_provenance_guard BEFORE UPDATE ON public.events
FOR EACH ROW EXECUTE FUNCTION northstar_private.protect_department_content_provenance();
DROP TRIGGER IF EXISTS northstar_resource_provenance_guard ON public.resources;
CREATE TRIGGER northstar_resource_provenance_guard BEFORE UPDATE ON public.resources
FOR EACH ROW EXECUTE FUNCTION northstar_private.protect_department_content_provenance();
DROP TRIGGER IF EXISTS northstar_incident_department_guard ON public.northstar_incidents;
CREATE TRIGGER northstar_incident_department_guard BEFORE UPDATE OF reported_by, department_id ON public.northstar_incidents
FOR EACH ROW EXECUTE FUNCTION northstar_private.protect_department_content_provenance();

-- File access is tied to resource metadata. Department heads upload beneath a
-- department-specific prefix so Storage can authorize the initial upload
-- before the metadata row exists. Company-root paths retain existing policy.
CREATE OR REPLACE FUNCTION northstar_private.resource_object_allowed(p_object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT public.northstar_is_designated_admin()
    OR EXISTS (SELECT 1 FROM public.resources r WHERE r.storage_path = p_object_name
      AND ((r.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
        OR northstar_private.is_eligible_department_member(r.department_id)))
    OR EXISTS (SELECT 1 FROM public.profiles p JOIN auth.users u ON u.id = p.id
      WHERE p.id = auth.uid() AND p.department_level = 1 AND p.department_id IS NOT NULL
        AND p.role::text IN ('employee', 'manager')
        AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active'
        AND p.registration_completed IS TRUE AND u.email_confirmed_at IS NOT NULL
        AND p_object_name LIKE ('departments/' || p.department_id::text || '/resources/%'));
$function$;
ALTER FUNCTION northstar_private.resource_object_allowed(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.resource_object_allowed(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.resource_object_allowed(text) TO authenticated;
CREATE OR REPLACE FUNCTION northstar_private.resource_object_managed_by_department_head(p_object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT public.northstar_is_designated_admin()
    OR EXISTS (
      SELECT 1 FROM public.resources AS resource_row
      WHERE resource_row.storage_path = p_object_name
        AND northstar_private.is_department_head(resource_row.department_id)
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles AS profile
      WHERE profile.id = auth.uid()
        AND northstar_private.is_department_head(profile.department_id)
        AND p_object_name LIKE ('departments/' || profile.department_id::text || '/resources/%')
    );
$function$;
ALTER FUNCTION northstar_private.resource_object_managed_by_department_head(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.resource_object_managed_by_department_head(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.resource_object_managed_by_department_head(text) TO authenticated;

-- The three pre-existing company-resource restrictive guards are retained.
-- Add a department-head branch to each catalogued predicate while preserving
-- its complete original expression for admins and every other existing case.
DO $extend_company_resource_guards$
DECLARE
  guard_row record;
  old_using text;
  old_check text;
  head_insert text := $predicate$
    bucket_id = 'company-resources' AND EXISTS (
      SELECT 1 FROM public.profiles AS profile
      JOIN auth.users AS account ON account.id = profile.id
      WHERE profile.id = auth.uid() AND profile.department_level = 1
        AND profile.department_id IS NOT NULL
        AND profile.role::text IN ('employee', 'manager')
        AND profile.approval_status::text = 'approved'
        AND profile.employment_status::text = 'active'
        AND profile.registration_completed IS TRUE
        AND account.email_confirmed_at IS NOT NULL
        AND name LIKE ('departments/' || profile.department_id::text || '/resources/%')
    )
  $predicate$;
  head_manage text := $predicate$
    bucket_id = 'company-resources'
    AND northstar_private.resource_object_managed_by_department_head(name)
  $predicate$;
BEGIN
  FOR guard_row IN
    SELECT policy.polname, policy.polcmd
    FROM pg_policy AS policy
    WHERE policy.polrelid = 'storage.objects'::regclass
      AND policy.polname = ANY(ARRAY[
        'northstar_company_resources_insert_guard',
        'northstar_company_resources_update_guard',
        'northstar_company_resources_delete_guard'
      ])
  LOOP
    IF guard_row.polcmd = 'a' THEN
      old_check := pg_get_expr((SELECT polwithcheck FROM pg_policy
        WHERE polrelid = 'storage.objects'::regclass AND polname = guard_row.polname), 'storage.objects'::regclass);
      EXECUTE format('ALTER POLICY %I ON storage.objects WITH CHECK ((%s) OR (%s))',
        guard_row.polname, old_check, head_insert);
    ELSIF guard_row.polcmd = 'w' THEN
      SELECT pg_get_expr(polqual, polrelid), pg_get_expr(polwithcheck, polrelid)
        INTO old_using, old_check
      FROM pg_policy
      WHERE polrelid = 'storage.objects'::regclass AND polname = guard_row.polname;
      EXECUTE format('ALTER POLICY %I ON storage.objects USING ((%s) OR (%s)) WITH CHECK ((%s) OR (%s))',
        guard_row.polname, old_using, head_manage, old_check, head_manage);
    ELSIF guard_row.polcmd = 'd' THEN
      old_using := pg_get_expr((SELECT polqual FROM pg_policy
        WHERE polrelid = 'storage.objects'::regclass AND polname = guard_row.polname), 'storage.objects'::regclass);
      EXECUTE format('ALTER POLICY %I ON storage.objects USING ((%s) OR (%s))',
        guard_row.polname, old_using, head_manage);
    END IF;
  END LOOP;
END;
$extend_company_resource_guards$;

DROP POLICY IF EXISTS northstar_company_resources_department_guard ON storage.objects;
CREATE POLICY northstar_company_resources_department_guard ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
USING (bucket_id <> 'company-resources' OR northstar_private.resource_object_allowed(name));
DROP POLICY IF EXISTS northstar_company_resources_department_insert_guard ON storage.objects;
CREATE POLICY northstar_company_resources_department_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (bucket_id <> 'company-resources' OR public.northstar_is_designated_admin() OR EXISTS (
  SELECT 1 FROM public.profiles p JOIN auth.users u ON u.id = p.id
  WHERE p.id = auth.uid() AND p.department_level = 1 AND p.department_id IS NOT NULL
    AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active'
    AND p.registration_completed IS TRUE AND u.email_confirmed_at IS NOT NULL
    AND name LIKE ('departments/' || p.department_id::text || '/resources/%')
));
DROP POLICY IF EXISTS northstar_company_resources_department_update_guard ON storage.objects;
CREATE POLICY northstar_company_resources_department_update_guard ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
USING (bucket_id <> 'company-resources' OR northstar_private.resource_object_managed_by_department_head(name))
WITH CHECK (bucket_id <> 'company-resources' OR northstar_private.resource_object_managed_by_department_head(name));
DROP POLICY IF EXISTS northstar_company_resources_department_delete_guard ON storage.objects;
CREATE POLICY northstar_company_resources_department_delete_guard ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
USING (bucket_id <> 'company-resources' OR northstar_private.resource_object_managed_by_department_head(name));
-- A private bucket should not become anonymous through a pre-existing Storage
-- permissive policy. These restrictive guards affect only this bucket.
DROP POLICY IF EXISTS northstar_company_resources_anon_select_guard ON storage.objects;
CREATE POLICY northstar_company_resources_anon_select_guard ON storage.objects AS RESTRICTIVE FOR SELECT TO anon
USING (bucket_id <> 'company-resources');
DROP POLICY IF EXISTS northstar_company_resources_anon_insert_guard ON storage.objects;
CREATE POLICY northstar_company_resources_anon_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO anon
WITH CHECK (bucket_id <> 'company-resources');
DROP POLICY IF EXISTS northstar_company_resources_anon_update_guard ON storage.objects;
CREATE POLICY northstar_company_resources_anon_update_guard ON storage.objects AS RESTRICTIVE FOR UPDATE TO anon
USING (bucket_id <> 'company-resources') WITH CHECK (bucket_id <> 'company-resources');
DROP POLICY IF EXISTS northstar_company_resources_anon_delete_guard ON storage.objects;
CREATE POLICY northstar_company_resources_anon_delete_guard ON storage.objects AS RESTRICTIVE FOR DELETE TO anon
USING (bucket_id <> 'company-resources');

-- Populate incident department from the authenticated reporter's protected
-- profile. Ignore any caller-supplied department value.
CREATE OR REPLACE FUNCTION northstar_private.set_incident_department()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.northstar_is_designated_admin() THEN
    SELECT p.department_id INTO NEW.department_id FROM public.profiles p WHERE p.id = auth.uid()
      AND p.role::text IN ('employee', 'manager') AND p.department_level BETWEEN 1 AND 5
      AND p.registration_completed IS TRUE AND p.approval_status::text = 'approved'
      AND p.employment_status::text = 'active';
    IF NEW.department_id IS NULL THEN RAISE EXCEPTION 'An assigned department level is required to report an incident.' USING ERRCODE = '42501'; END IF;
    NEW.reported_by := auth.uid();
  END IF;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION northstar_private.set_incident_department() OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.set_incident_department() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS northstar_incident_set_department ON public.northstar_incidents;
CREATE TRIGGER northstar_incident_set_department BEFORE INSERT ON public.northstar_incidents
FOR EACH ROW EXECUTE FUNCTION northstar_private.set_incident_department();

CREATE POLICY northstar_incidents_department_guard ON public.northstar_incidents AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (deleted_at IS NULL AND
  (northstar_private.is_eligible_department_member(department_id)
   OR (reported_by = (SELECT auth.uid()) AND northstar_private.is_eligible_workspace_user()))));
CREATE POLICY northstar_incident_updates_department_guard ON public.northstar_incident_updates AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.northstar_is_designated_admin() OR (
  visibility <> 'admin' AND event_type <> 'admin_update' AND EXISTS (
    SELECT 1 FROM public.northstar_incidents i WHERE i.id = incident_id
      AND northstar_private.is_eligible_department_member(i.department_id)
      AND (visibility <> 'response_team' OR i.assigned_responder = (SELECT auth.uid()))
  )
));

CREATE OR REPLACE FUNCTION public.northstar_department_head_update_incident(
  p_incident_id uuid, p_status text, p_severity text, p_assigned_responder uuid,
  p_resolution_details text, p_update text, p_visibility text DEFAULT 'reporter'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE actor_id uuid := auth.uid(); actor_department uuid; incident public.northstar_incidents%ROWTYPE; event_name text;
BEGIN
  SELECT p.department_id INTO actor_department FROM public.profiles p WHERE p.id = actor_id
    AND p.department_level = 1 AND p.registration_completed IS TRUE
    AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active';
  IF actor_id IS NULL OR NOT northstar_private.is_department_head(actor_department) THEN RAISE EXCEPTION 'Only the assigned department head may manage department incidents.' USING ERRCODE = '42501'; END IF;
  IF p_incident_id IS NULL OR p_status NOT IN ('open', 'investigating', 'resolved', 'closed')
     OR p_severity NOT IN ('low', 'medium', 'high', 'critical') OR p_visibility NOT IN ('reporter', 'response_team')
     OR p_update IS NULL OR length(btrim(p_update)) NOT BETWEEN 1 AND 10000
     OR (p_resolution_details IS NOT NULL AND length(btrim(p_resolution_details)) > 10000)
     OR (p_status IN ('resolved', 'closed') AND NULLIF(btrim(p_resolution_details), '') IS NULL) THEN
    RAISE EXCEPTION 'Incident update fields are invalid or incomplete.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO incident FROM public.northstar_incidents i WHERE i.id = p_incident_id AND i.department_id = actor_department FOR UPDATE;
  IF NOT FOUND OR incident.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Incident was not found in your department.' USING ERRCODE = '42501'; END IF;
  IF p_assigned_responder IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles p JOIN auth.users u ON u.id = p.id
    WHERE p.id = p_assigned_responder AND p.department_id = actor_department AND p.department_level BETWEEN 1 AND 5
      AND p.role::text IN ('employee','manager') AND p.registration_completed IS TRUE
      AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active' AND u.email_confirmed_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'Responder must be an eligible employee in this department.' USING ERRCODE = '22023'; END IF;
  event_name := CASE WHEN incident.status IS DISTINCT FROM p_status THEN 'status_changed'
    WHEN incident.severity IS DISTINCT FROM p_severity THEN 'severity_changed'
    WHEN incident.assigned_responder IS DISTINCT FROM p_assigned_responder THEN 'responder_changed'
    WHEN incident.resolution_details IS DISTINCT FROM NULLIF(btrim(p_resolution_details), '') THEN 'resolution_changed'
    ELSE 'reporter_update' END;
  UPDATE public.northstar_incidents SET status = p_status, severity = p_severity,
    assigned_responder = p_assigned_responder, resolution_details = NULLIF(btrim(p_resolution_details), ''), updated_at = clock_timestamp()
  WHERE id = incident.id;
  INSERT INTO public.northstar_incident_updates (incident_id, actor_id, event_type, visibility,
    old_status, new_status, old_severity, new_severity, old_assigned_responder, new_assigned_responder,
    old_resolution_details, new_resolution_details, details)
  VALUES (incident.id, actor_id, event_name, p_visibility, incident.status, p_status, incident.severity, p_severity,
    incident.assigned_responder, p_assigned_responder, incident.resolution_details,
    NULLIF(btrim(p_resolution_details), ''), btrim(p_update));
END;
$function$;
ALTER FUNCTION public.northstar_department_head_update_incident(uuid, text, text, uuid, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_head_update_incident(uuid, text, text, uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_head_update_incident(uuid, text, text, uuid, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_department_report_incident(p_title text, p_description text, p_category text, p_severity text, p_location text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE incident_id uuid;
BEGIN
  IF NOT northstar_private.is_eligible_department_member((SELECT p.department_id FROM public.profiles p WHERE p.id = auth.uid())) THEN
    RAISE EXCEPTION 'An approved employee with an assigned department level is required.' USING ERRCODE = '42501';
  END IF;
  incident_id := public.northstar_report_incident(p_title, p_description, p_category, p_severity, p_location);
  RETURN incident_id;
END;
$function$;
ALTER FUNCTION public.northstar_department_report_incident(text, text, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_report_incident(text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_report_incident(text, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_department_list_incidents()
RETURNS TABLE (id uuid, title text, description text, category text, severity text, location text, reported_by uuid, reporter_name text, reported_at timestamptz, status text, assigned_responder uuid, resolution_details text, department_id uuid, deleted_at timestamptz, is_reporter boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE actor_id uuid := auth.uid(); actor_department uuid;
BEGIN
  SELECT p.department_id INTO actor_department FROM public.profiles p JOIN auth.users u ON u.id = p.id WHERE p.id = actor_id
    AND p.role::text IN ('employee', 'manager')
    AND p.department_level BETWEEN 1 AND 5 AND p.registration_completed IS TRUE
    AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active' AND u.email_confirmed_at IS NOT NULL;
  IF actor_id IS NULL OR (actor_department IS NULL AND NOT public.northstar_is_designated_admin() AND NOT northstar_private.is_eligible_workspace_user()) THEN
    RAISE EXCEPTION 'An approved employee with a department assignment is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT i.id, i.title, i.description, i.category, i.severity, i.location,
    CASE WHEN public.northstar_is_designated_admin() OR i.reported_by = actor_id THEN i.reported_by ELSE NULL END,
    CASE WHEN public.northstar_is_designated_admin() OR i.reported_by = actor_id THEN NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', reporter.first_name, reporter.last_name)), '') ELSE NULL END,
    i.reported_at, i.status,
    CASE WHEN public.northstar_is_designated_admin() OR i.reported_by = actor_id OR i.assigned_responder = actor_id
      OR northstar_private.is_department_head(i.department_id) THEN i.assigned_responder ELSE NULL END,
    i.resolution_details, i.department_id, i.deleted_at, i.reported_by = actor_id
  FROM public.northstar_incidents i JOIN public.profiles reporter ON reporter.id = i.reported_by
  WHERE (public.northstar_is_designated_admin() OR (i.deleted_at IS NULL AND (i.department_id = actor_department OR i.reported_by = actor_id)))
  ORDER BY i.reported_at DESC;
END;
$function$;
ALTER FUNCTION public.northstar_department_list_incidents() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_list_incidents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_list_incidents() TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_department_list_incident_history(p_incident_ids uuid[])
RETURNS TABLE (id uuid, incident_id uuid, event_type text, old_status text, new_status text, old_severity text, new_severity text, details text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE actor_id uuid := auth.uid(); actor_department uuid;
BEGIN
  SELECT p.department_id INTO actor_department FROM public.profiles p JOIN auth.users u ON u.id = p.id WHERE p.id = actor_id
    AND p.role::text IN ('employee', 'manager')
    AND p.department_level BETWEEN 1 AND 5 AND p.registration_completed IS TRUE
    AND p.approval_status::text = 'approved' AND p.employment_status::text = 'active' AND u.email_confirmed_at IS NOT NULL;
  IF actor_id IS NULL OR (actor_department IS NULL AND NOT public.northstar_is_designated_admin() AND NOT northstar_private.is_eligible_workspace_user()) THEN RAISE EXCEPTION 'Department access is required.' USING ERRCODE = '42501'; END IF;
  RETURN QUERY SELECT u.id, u.incident_id, u.event_type, u.old_status, u.new_status, u.old_severity, u.new_severity,
    CASE WHEN public.northstar_is_designated_admin() OR i.assigned_responder = actor_id
      OR (u.visibility = 'reporter' AND i.reported_by = actor_id) THEN u.details ELSE NULL END,
    u.created_at
  FROM public.northstar_incident_updates u JOIN public.northstar_incidents i ON i.id = u.incident_id
  WHERE u.incident_id = ANY(p_incident_ids) AND (public.northstar_is_designated_admin() OR (i.deleted_at IS NULL AND (i.department_id = actor_department OR i.reported_by = actor_id)))
    AND (public.northstar_is_designated_admin() OR (u.visibility <> 'admin' AND u.event_type <> 'admin_update'))
    AND (u.visibility <> 'response_team' OR public.northstar_is_designated_admin() OR i.assigned_responder = actor_id)
  ORDER BY u.created_at, u.id;
END;
$function$;
ALTER FUNCTION public.northstar_department_list_incident_history(uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_list_incident_history(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_list_incident_history(uuid[]) TO authenticated;

-- Normal employee clients use the department-scoped RPCs. Revoke direct access
-- to legacy company-wide lists and the unscoped report entry point so manual
-- RPC calls cannot bypass department eligibility. SECURITY DEFINER wrappers
-- retain owner execution.
DO $legacy_list_acl$
BEGIN
  IF to_regprocedure('public.northstar_report_incident(text,text,text,text,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_report_incident(text, text, text, text, text) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.northstar_list_company_incidents()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_list_company_incidents() FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.northstar_list_active_company_incidents()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_list_active_company_incidents() FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.northstar_list_company_incident_history(uuid[])') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_list_company_incident_history(uuid[]) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$legacy_list_acl$;

DO $legacy_list_acl_verify$
DECLARE target_function regprocedure;
BEGIN
  FOREACH target_function IN ARRAY ARRAY[
    to_regprocedure('public.northstar_list_company_incidents()'),
    to_regprocedure('public.northstar_list_active_company_incidents()'),
    to_regprocedure('public.northstar_list_company_incident_history(uuid[])')
  ] LOOP
    IF target_function IS NOT NULL AND (
      has_function_privilege('anon', target_function, 'EXECUTE')
      OR has_function_privilege('authenticated', target_function, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE p.oid = target_function AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    ) THEN RAISE EXCEPTION 'Legacy company-wide incident list remains executable by a client role or PUBLIC: %', target_function; END IF;
  END LOOP;
  IF to_regprocedure('public.northstar_report_incident(text,text,text,text,text)') IS NOT NULL
     AND (
       has_function_privilege('anon', 'public.northstar_report_incident(text,text,text,text,text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.northstar_report_incident(text,text,text,text,text)', 'EXECUTE')
       OR EXISTS (
         SELECT 1 FROM pg_proc p
         CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE p.oid = to_regprocedure('public.northstar_report_incident(text,text,text,text,text)')
           AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
       )
     ) THEN
    RAISE EXCEPTION 'Legacy incident-report RPC remains executable by a client role or PUBLIC; callers must use the department-eligible wrapper.';
  END IF;
END;
$legacy_list_acl_verify$;

DO $acl_check$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_admin_assign_department_level(uuid,uuid,smallint)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.oid = 'public.northstar_admin_assign_department_level(uuid,uuid,smallint)'::regprocedure
         AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Department assignment RPC is executable by anon directly or PUBLIC.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_admin_assign_department_level(uuid,uuid,smallint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated role must be able to call the guarded department assignment RPC.';
  END IF;
END;
$acl_check$;

COMMIT;
