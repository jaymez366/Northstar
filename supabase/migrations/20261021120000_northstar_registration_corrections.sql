-- Store administrator-selected correction requirements with each immutable
-- rejection event and enforce them against that event's exact snapshot.

ALTER TABLE public.employee_registration_rejection_history
  ADD COLUMN correction_fields text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.employee_registration_rejection_history
  ADD CONSTRAINT employee_registration_rejection_history_correction_fields_check
  CHECK (correction_fields <@ ARRAY[
    'first_name', 'last_name', 'phone_number', 'department', 'job_title',
    'employee_id', 'employment_type', 'office_location', 'date_of_joining',
    'manager_name', 'bio'
  ]::text[]);

CREATE OR REPLACE FUNCTION public.admin_set_employee_approval(
  p_user_id uuid, p_approval_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users AS admin_user
    WHERE admin_user.id = auth.uid()
      AND pg_catalog.lower(admin_user.email) = 'northstaradmin34@gmail.com'
      AND admin_user.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Administrator authorization required.' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_approval_status IS NULL
     OR p_approval_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Approval status must be approved or rejected.' USING ERRCODE = '22023';
  END IF;
  IF p_approval_status = 'rejected' THEN
    RAISE EXCEPTION 'Use northstar_admin_update_employee_registration_status to reject a registration.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users AS employee_user
    JOIN public.profiles AS employee_profile ON employee_profile.id = employee_user.id
    WHERE employee_user.id = p_user_id
      AND employee_user.email_confirmed_at IS NOT NULL
      AND employee_profile.registration_completed IS TRUE
  ) THEN
    RAISE EXCEPTION 'Only a registered employee with a confirmed email can be approved or rejected.'
      USING ERRCODE = '22023';
  END IF;
  UPDATE public.profiles AS p
  SET approval_status = 'approved', employment_status = 'active'
  WHERE p.id = p_user_id AND p.registration_completed IS TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The submitted employee registration was not found.' USING ERRCODE = 'P0002';
  END IF;
END
$function$;

ALTER FUNCTION public.admin_set_employee_approval(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_set_employee_approval(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_employee_approval(uuid, text)
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.northstar_admin_update_employee_registration_status(
  p_user_id uuid, p_approval_status text, p_rejection_reason text,
  p_correction_fields text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_reason text;
  v_fields text[];
  v_employee_number text;
  v_employee_name text;
  v_employee_email text;
  v_admin_email text;
  v_snapshot public.employee_registration_snapshots%ROWTYPE;
  v_snapshot_id uuid;
  v_status text;
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may update registrations.'
      USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_approval_status IS NULL
     OR p_approval_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'A valid employee and approval status are required.' USING ERRCODE = '22023';
  END IF;

  IF p_approval_status = 'approved' THEN
    IF COALESCE(cardinality(p_correction_fields), 0) <> 0 THEN
      RAISE EXCEPTION 'Correction fields may only be supplied for a rejection.' USING ERRCODE = '22023';
    END IF;
    PERFORM public.admin_set_employee_approval(p_user_id, 'approved');
    UPDATE public.profiles SET rejection_reason = NULL WHERE id = p_user_id;
    RETURN;
  END IF;

  v_reason := NULLIF(pg_catalog.btrim(p_rejection_reason), '');
  IF v_reason IS NULL OR pg_catalog.length(v_reason) > 2000 THEN
    RAISE EXCEPTION 'A rejection reason of 1 to 2000 characters is required.' USING ERRCODE = '22023';
  END IF;
  IF p_correction_fields IS NULL OR cardinality(p_correction_fields) = 0 THEN
    RAISE EXCEPTION 'Select at least one registration field that requires correction.'
      USING ERRCODE = '22023';
  END IF;
  SELECT array_agg(field ORDER BY field) INTO v_fields
  FROM (
    SELECT DISTINCT pg_catalog.btrim(item) AS field
    FROM unnest(p_correction_fields) AS supplied(item)
  ) AS selected
  WHERE field = ANY (ARRAY[
    'first_name', 'last_name', 'phone_number', 'department', 'job_title',
    'employee_id', 'employment_type', 'office_location', 'date_of_joining',
    'manager_name', 'bio'
  ]::text[]);
  IF v_fields IS NULL OR cardinality(v_fields) <> cardinality(
    ARRAY(SELECT DISTINCT pg_catalog.btrim(item) FROM unnest(p_correction_fields) AS supplied(item))
  ) THEN
    RAISE EXCEPTION 'One or more selected correction fields are invalid.' USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.profiles AS p
  JOIN auth.users AS u ON u.id = p.id
  WHERE p.id = p_user_id AND u.email_confirmed_at IS NOT NULL
    AND p.registration_completed IS TRUE AND p.employment_status = 'inactive'
    AND (
      p.approval_status = 'pending'
      OR (
        p.approval_status = 'rejected'
        AND EXISTS (
          SELECT 1 FROM public.employee_registration_rejection_history AS old_event
          WHERE old_event.id = (
            SELECT h.id FROM public.employee_registration_rejection_history AS h
            WHERE h.employee_id = p.id ORDER BY h.rejected_at DESC, h.id DESC LIMIT 1
          )
          AND cardinality(old_event.correction_fields) = 0
        )
      )
    )
  FOR UPDATE OF p;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only a pending registration or a legacy rejection with no correction requirements can be rejected.'
      USING ERRCODE = '22023';
  END IF;

  SELECT p.approval_status::text INTO v_status
  FROM public.profiles AS p WHERE p.id = p_user_id;
  SELECT s.* INTO v_snapshot
  FROM public.employee_registration_snapshots AS s
  WHERE s.user_id = p_user_id
  ORDER BY s.submitted_at DESC, s.id DESC LIMIT 1;
  IF v_snapshot.id IS NULL THEN
    RAISE EXCEPTION 'The employee registration snapshot is missing; rejection was not recorded.'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_snapshot.is_original
     OR v_snapshot.registration_completed IS DISTINCT FROM TRUE
     OR v_snapshot.approval_status IS DISTINCT FROM 'pending'
     OR v_snapshot.employment_status IS DISTINCT FROM 'inactive'
     OR NOT EXISTS (
       SELECT 1
       FROM public.profiles AS p
       JOIN auth.users AS u ON u.id = p.id
       LEFT JOIN public.departments AS d ON d.id = p.department_id
       WHERE p.id = p_user_id AND p.registration_completed IS TRUE
         AND p.approval_status::text = v_status
         AND p.approval_status IN ('pending', 'rejected')
         AND p.employment_status = 'inactive'
         AND (
           p.approval_status = 'pending'
           OR EXISTS (
             SELECT 1 FROM public.employee_registration_rejection_history AS old_event
             WHERE old_event.id = (
               SELECT h.id FROM public.employee_registration_rejection_history AS h
               WHERE h.employee_id = p.id ORDER BY h.rejected_at DESC, h.id DESC LIMIT 1
             )
             AND cardinality(old_event.correction_fields) = 0
             AND (old_event.registration_snapshot_id IS NULL
                  OR old_event.registration_snapshot_id = v_snapshot.id)
           )
         )
         AND v_snapshot.first_name IS NOT DISTINCT FROM p.first_name::text
         AND v_snapshot.last_name IS NOT DISTINCT FROM p.last_name::text
         AND v_snapshot.email IS NOT DISTINCT FROM p.email::text
         AND v_snapshot.phone_number IS NOT DISTINCT FROM p.phone_number::text
         AND v_snapshot.department IS NOT DISTINCT FROM d.name::text
         AND v_snapshot.job_title IS NOT DISTINCT FROM p.job_title::text
         AND v_snapshot.employee_id IS NOT DISTINCT FROM p.employee_id::text
         AND v_snapshot.employment_type IS NOT DISTINCT FROM p.employment_type::text
         AND v_snapshot.office_location IS NOT DISTINCT FROM p.office_location::text
         AND v_snapshot.date_of_joining IS NOT DISTINCT FROM p.date_of_joining::text
         AND v_snapshot.manager_name IS NOT DISTINCT FROM p.manager_name::text
         AND v_snapshot.bio IS NOT DISTINCT FROM p.bio::text
     ) THEN
    RAISE EXCEPTION 'The latest original registration snapshot does not match the current registration profile; rejection was not recorded.'
      USING ERRCODE = '22023';
  END IF;
  v_snapshot_id := v_snapshot.id;

  SELECT p.employee_id::text,
         COALESCE(NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', p.first_name, p.last_name)), ''), 'Employee'),
         COALESCE(p.email::text, u.email, '')
  INTO v_employee_number, v_employee_name, v_employee_email
  FROM public.profiles AS p LEFT JOIN auth.users AS u ON u.id = p.id
  WHERE p.id = p_user_id;
  SELECT pg_catalog.lower(u.email) INTO v_admin_email
  FROM auth.users AS u
  WHERE u.id = auth.uid() AND u.email_confirmed_at IS NOT NULL;
  IF v_admin_email IS NULL THEN
    RAISE EXCEPTION 'The authenticated designated administrator account could not be verified.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET approval_status = 'rejected', employment_status = 'inactive', rejection_reason = v_reason
  WHERE id = p_user_id AND registration_completed IS TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee profile was not found.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.employee_registration_rejection_history (
    employee_id, employee_number, employee_name, employee_email, rejection_reason,
    rejected_by, rejected_by_email, registration_snapshot_id, status_at_event,
    is_legacy_snapshot, correction_fields
  ) VALUES (
    p_user_id, v_employee_number, v_employee_name, v_employee_email, v_reason,
    auth.uid(), v_admin_email, v_snapshot_id, 'rejected', false, v_fields
  );
END
$function$;

ALTER FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text, text[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text, text[])
  TO authenticated, postgres, service_role;

-- Preserve approvals on the deployed signature; it cannot reject without fields.
CREATE OR REPLACE FUNCTION public.northstar_admin_update_employee_registration_status(
  p_user_id uuid, p_approval_status text, p_rejection_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM public.northstar_admin_update_employee_registration_status(
    p_user_id, p_approval_status, p_rejection_reason, ARRAY[]::text[]
  );
END
$function$;

ALTER FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text)
  TO authenticated, postgres, service_role;

-- Lock approval and registration state against direct table updates. The
-- SECURITY DEFINER registration/admin RPCs run as postgres and use this gate.
CREATE OR REPLACE FUNCTION public.northstar_protect_profile_approval_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  changed_registration boolean;
BEGIN
  changed_registration :=
    NEW.first_name IS DISTINCT FROM OLD.first_name
    OR NEW.last_name IS DISTINCT FROM OLD.last_name
    OR NEW.phone_number IS DISTINCT FROM OLD.phone_number
    OR NEW.department_id IS DISTINCT FROM OLD.department_id
    OR NEW.job_title IS DISTINCT FROM OLD.job_title
    OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
    OR NEW.employment_type IS DISTINCT FROM OLD.employment_type
    OR NEW.office_location IS DISTINCT FROM OLD.office_location
    OR NEW.date_of_joining IS DISTINCT FROM OLD.date_of_joining
    OR NEW.manager_name IS DISTINCT FROM OLD.manager_name
    OR NEW.bio IS DISTINCT FROM OLD.bio;

  IF current_user IN ('authenticated', 'anon') THEN
    IF OLD.approval_status = 'rejected' AND changed_registration THEN
      RAISE EXCEPTION 'Rejected registration corrections must use the Northstar registration RPC.'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.approval_status IS DISTINCT FROM OLD.approval_status
       OR NEW.employment_status IS DISTINCT FROM OLD.employment_status
       OR NEW.registration_completed IS DISTINCT FROM OLD.registration_completed
       OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
       OR (
         NOT public.northstar_is_designated_admin()
         AND NEW.role IS DISTINCT FROM OLD.role
       ) THEN
      RAISE EXCEPTION 'Registration approval fields can only be changed by Northstar registration functions.'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

-- Keep the deployed validation routine intact, but make it private to a
-- guarded wrapper so no client can call around correction checks.
ALTER FUNCTION public.complete_my_employee_registration(
  text, text, text, text, text, text, text, text, date, text, text
) RENAME TO northstar_complete_employee_registration_validated;
REVOKE ALL ON FUNCTION public.northstar_complete_employee_registration_validated(
  text, text, text, text, text, text, text, text, date, text, text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.complete_my_employee_registration(
  p_first_name text, p_last_name text, p_phone_number text, p_department text,
  p_job_title text, p_employee_id text, p_employment_type text,
  p_office_location text, p_date_of_joining date, p_manager_name text, p_bio text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_status text;
  v_fields text[];
  v_snapshot public.employee_registration_snapshots%ROWTYPE;
  v_field text;
  v_new text;
  v_old text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to submit employee registration.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users AS u
    WHERE u.id = v_user_id AND u.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A confirmed email address is required to submit employee registration.'
      USING ERRCODE = '42501';
  END IF;
  SELECT p.approval_status::text INTO v_status
  FROM public.profiles AS p WHERE p.id = v_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Your employee profile is missing; contact an administrator.' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'approved' THEN
    RAISE EXCEPTION 'An approved employee registration cannot be resubmitted.' USING ERRCODE = '42501';
  END IF;

  IF v_status = 'rejected' THEN
    SELECT h.correction_fields INTO v_fields
    FROM public.employee_registration_rejection_history AS h
    WHERE h.employee_id = v_user_id
      AND h.id = (
        SELECT latest.id FROM public.employee_registration_rejection_history AS latest
        WHERE latest.employee_id = v_user_id
        ORDER BY latest.rejected_at DESC, latest.id DESC LIMIT 1
      );
    IF NOT FOUND OR v_fields IS NULL OR cardinality(v_fields) = 0 THEN
      RAISE EXCEPTION 'The latest rejection has no correction requirements or exact snapshot. Contact the administrator.'
        USING ERRCODE = '22023';
    END IF;
    SELECT s.* INTO v_snapshot
    FROM public.employee_registration_rejection_history AS h
    JOIN public.employee_registration_snapshots AS s
      ON s.id = h.registration_snapshot_id AND s.user_id = h.employee_id
    WHERE h.employee_id = v_user_id
      AND h.id = (
        SELECT latest.id FROM public.employee_registration_rejection_history AS latest
        WHERE latest.employee_id = v_user_id
        ORDER BY latest.rejected_at DESC, latest.id DESC LIMIT 1
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'The registration snapshot for the latest rejection is missing.'
        USING ERRCODE = 'P0002';
    END IF;

    FOREACH v_field IN ARRAY v_fields LOOP
      v_new := CASE v_field
        WHEN 'first_name' THEN pg_catalog.btrim(p_first_name)
        WHEN 'last_name' THEN pg_catalog.btrim(p_last_name)
        WHEN 'phone_number' THEN pg_catalog.btrim(p_phone_number)
        WHEN 'department' THEN pg_catalog.btrim(p_department)
        WHEN 'job_title' THEN pg_catalog.btrim(p_job_title)
        WHEN 'employee_id' THEN NULLIF(pg_catalog.btrim(COALESCE(p_employee_id, '')), '')
        WHEN 'employment_type' THEN p_employment_type
        WHEN 'office_location' THEN pg_catalog.btrim(p_office_location)
        WHEN 'date_of_joining' THEN p_date_of_joining::text
        WHEN 'manager_name' THEN NULLIF(pg_catalog.btrim(COALESCE(p_manager_name, '')), '')
        WHEN 'bio' THEN NULLIF(pg_catalog.btrim(COALESCE(p_bio, '')), '')
        ELSE NULL
      END;
      v_old := pg_catalog.to_jsonb(v_snapshot) ->> v_field;
      IF v_new IS NULL OR v_new = '' THEN
        RAISE EXCEPTION 'The selected correction field "%" must be completed.', v_field
          USING ERRCODE = '22023';
      END IF;
      IF (CASE WHEN v_field = 'department'
        THEN pg_catalog.lower(v_new) IS NOT DISTINCT FROM pg_catalog.lower(v_old)
        ELSE v_new IS NOT DISTINCT FROM v_old
      END) THEN
        RAISE EXCEPTION 'The selected correction field "%" must be changed from the rejected registration.', v_field
          USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END IF;

  PERFORM public.northstar_complete_employee_registration_validated(
    p_first_name, p_last_name, p_phone_number, p_department, p_job_title,
    p_employee_id, p_employment_type, p_office_location, p_date_of_joining,
    p_manager_name, p_bio
  );
  UPDATE public.profiles SET rejection_reason = NULL WHERE id = v_user_id;
END
$function$;

ALTER FUNCTION public.complete_my_employee_registration(text, text, text, text, text, text, text, text, date, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_my_employee_registration(text, text, text, text, text, text, text, text, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_my_employee_registration(text, text, text, text, text, text, text, text, date, text, text)
  TO authenticated, postgres, service_role;

CREATE FUNCTION public.northstar_get_my_registration_correction_requirements()
RETURNS TABLE (rejection_reason text, correction_fields text[], registration_snapshot jsonb)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT h.rejection_reason, h.correction_fields,
    pg_catalog.jsonb_build_object(
      'first_name', s.first_name, 'last_name', s.last_name,
      'phone_number', s.phone_number, 'department', s.department,
      'job_title', s.job_title, 'employee_id', s.employee_id,
      'employment_type', s.employment_type, 'office_location', s.office_location,
      'date_of_joining', s.date_of_joining, 'manager_name', s.manager_name, 'bio', s.bio
    )
  FROM public.employee_registration_rejection_history AS h
  JOIN public.employee_registration_snapshots AS s
    ON s.id = h.registration_snapshot_id AND s.user_id = h.employee_id
  JOIN public.profiles AS p ON p.id = h.employee_id
  WHERE h.employee_id = auth.uid() AND p.approval_status = 'rejected'
  ORDER BY h.rejected_at DESC, h.id DESC LIMIT 1;
END
$function$;

ALTER FUNCTION public.northstar_get_my_registration_correction_requirements() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_get_my_registration_correction_requirements() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_get_my_registration_correction_requirements() TO authenticated;

CREATE FUNCTION public.northstar_list_my_employee_rejection_history_with_corrections()
RETURNS TABLE (
  id uuid, employee_id uuid, employee_number text, employee_name text,
  employee_email text, rejection_reason text, rejected_by_email text,
  rejected_at timestamptz, registration_snapshot_id uuid, status_at_event text,
  current_approval_status text, correction_fields text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT h.id, h.employee_id, h.employee_number, h.employee_name, h.employee_email,
    h.rejection_reason, COALESCE(h.rejected_by_email, ''), h.rejected_at,
    h.registration_snapshot_id, h.status_at_event,
    COALESCE(p.approval_status::text, 'unknown'), h.correction_fields
  FROM public.employee_registration_rejection_history AS h
  LEFT JOIN public.profiles AS p ON p.id = h.employee_id
  WHERE auth.uid() IS NOT NULL AND h.employee_id = auth.uid()
  ORDER BY h.rejected_at DESC, h.id DESC;
$function$;

ALTER FUNCTION public.northstar_list_my_employee_rejection_history_with_corrections() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_list_my_employee_rejection_history_with_corrections() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_list_my_employee_rejection_history_with_corrections() TO authenticated;

CREATE FUNCTION public.northstar_admin_list_rejection_history()
RETURNS TABLE (
  id uuid, employee_id uuid, employee_number text, employee_name text,
  employee_email text, rejection_reason text, rejected_by_email text,
  rejected_at timestamptz, registration_snapshot_id uuid, status_at_event text,
  current_approval_status text, correction_fields text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may list rejection history.'
      USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT h.id, h.employee_id, h.employee_number, h.employee_name, h.employee_email,
    h.rejection_reason, COALESCE(h.rejected_by_email, ''), h.rejected_at,
    h.registration_snapshot_id, h.status_at_event,
    COALESCE(p.approval_status::text, 'unknown'), h.correction_fields
  FROM public.employee_registration_rejection_history AS h
  LEFT JOIN public.profiles AS p ON p.id = h.employee_id
  ORDER BY h.rejected_at DESC, h.id DESC;
END
$function$;

ALTER FUNCTION public.northstar_admin_list_rejection_history() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_list_rejection_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_rejection_history() TO authenticated;
