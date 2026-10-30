-- NorthStar: reporter-owned incident editing, audited soft deletion, and safe
-- company incident history. This migration keeps the existing incident-list
-- RPC as the source of visibility and privacy rules.
BEGIN;

DO $preflight$
DECLARE
  list_function regprocedure := to_regprocedure('public.northstar_list_company_incidents()');
  list_result text;
  normalized_result text;
  missing_columns text;
  has_reporter_update_check boolean;
BEGIN
  IF to_regclass('public.northstar_incidents') IS NULL
     OR to_regclass('public.northstar_incident_updates') IS NULL THEN
    RAISE EXCEPTION 'NorthStar incident tables must exist before applying this migration.';
  END IF;

  SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
  INTO missing_columns
  FROM (VALUES
    ('northstar_incidents', 'id'),
    ('northstar_incidents', 'title'),
    ('northstar_incidents', 'description'),
    ('northstar_incidents', 'category'),
    ('northstar_incidents', 'severity'),
    ('northstar_incidents', 'location'),
    ('northstar_incidents', 'reported_by'),
    ('northstar_incidents', 'reported_at'),
    ('northstar_incidents', 'status'),
    ('northstar_incidents', 'assigned_responder'),
    ('northstar_incidents', 'resolution_details'),
    ('northstar_incidents', 'updated_at'),
    ('northstar_incident_updates', 'id'),
    ('northstar_incident_updates', 'incident_id'),
    ('northstar_incident_updates', 'actor_id'),
    ('northstar_incident_updates', 'event_type'),
    ('northstar_incident_updates', 'visibility'),
    ('northstar_incident_updates', 'old_status'),
    ('northstar_incident_updates', 'new_status'),
    ('northstar_incident_updates', 'old_severity'),
    ('northstar_incident_updates', 'new_severity'),
    ('northstar_incident_updates', 'details'),
    ('northstar_incident_updates', 'created_at')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS actual
    WHERE actual.table_schema = 'public'
      AND actual.table_name = required.table_name
      AND actual.column_name = required.column_name
  );
  IF missing_columns IS NOT NULL THEN
    RAISE EXCEPTION 'Incident schema differs from the reviewed contract; missing columns: %', missing_columns;
  END IF;

  IF list_function IS NULL THEN
    RAISE EXCEPTION 'Expected public.northstar_list_company_incidents() to exist.';
  END IF;
  list_result := pg_get_function_result(list_function);
  normalized_result := regexp_replace(lower(list_result), '[[:space:]]', '', 'g');
  IF normalized_result <> 'table(iduuid,titletext,descriptiontext,categorytext,severitytext,locationtext,reporter_nametext,reported_attimestampwithtimezone,statustext,assigned_responder_nametext,resolution_detailstext,is_reporterboolean)' THEN
    RAISE EXCEPTION 'northstar_list_company_incidents() return columns differ from the reviewed contract: %', list_result;
  END IF;
  IF NOT has_function_privilege(current_user, list_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'Migration role % cannot invoke northstar_list_company_incidents() from the new SECURITY DEFINER wrapper.', current_user;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = 'public.northstar_incident_updates'::regclass
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE '%event_type%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE '%reporter_update%'
  ) INTO has_reporter_update_check;
  IF NOT has_reporter_update_check THEN
    RAISE EXCEPTION 'northstar_incident_updates must allow event_type reporter_update before reporter edit/delete can be enabled.';
  END IF;

  IF (to_regprocedure('public.northstar_list_active_company_incidents()') IS NOT NULL
      AND coalesce(obj_description(to_regprocedure('public.northstar_list_active_company_incidents()'), 'pg_proc'), '')
          NOT LIKE 'NorthStar employee incident list.%')
     OR (to_regprocedure('public.northstar_list_company_incident_history(uuid[])') IS NOT NULL
      AND coalesce(obj_description(to_regprocedure('public.northstar_list_company_incident_history(uuid[])'), 'pg_proc'), '')
          NOT LIKE 'NorthStar company incident history.%')
     OR (to_regprocedure('public.northstar_reporter_edit_incident(uuid,text,text,text,text,text)') IS NOT NULL
      AND coalesce(obj_description(to_regprocedure('public.northstar_reporter_edit_incident(uuid,text,text,text,text,text)'), 'pg_proc'), '')
          NOT LIKE 'NorthStar reporter-owned incident edit%')
     OR (to_regprocedure('public.northstar_reporter_soft_delete_incident(uuid)') IS NOT NULL
      AND coalesce(obj_description(to_regprocedure('public.northstar_reporter_soft_delete_incident(uuid)'), 'pg_proc'), '')
          NOT LIKE 'NorthStar reporter-owned soft deletion%') THEN
    RAISE EXCEPTION 'A NorthStar incident RPC name is already in use by a function not marked as managed by this migration.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class AS relation
    WHERE relation.oid = 'public.northstar_incidents'::regclass
      AND relation.relrowsecurity IS TRUE
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_class AS relation
    WHERE relation.oid = 'public.northstar_incident_updates'::regclass
      AND relation.relrowsecurity IS TRUE
  ) THEN
    RAISE EXCEPTION 'Incident table RLS must remain enabled.';
  END IF;
END;
$preflight$;

ALTER TABLE public.northstar_incidents
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

DO $deleted_column_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'northstar_incidents'
      AND column_name = 'deleted_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'public.northstar_incidents.deleted_at must be timestamptz.';
  END IF;
END;
$deleted_column_check$;

CREATE INDEX IF NOT EXISTS northstar_incidents_active_time_idx
  ON public.northstar_incidents (reported_at DESC)
  WHERE deleted_at IS NULL;

-- Preserve the existing company-list function's confirmed authentication,
-- approval, active-employment, role, and privacy behavior. This wrapper only
-- removes soft-deleted rows from the normal employee-facing list.
CREATE OR REPLACE FUNCTION public.northstar_list_active_company_incidents()
RETURNS TABLE (
  id uuid,
  title text,
  description text,
  category text,
  severity text,
  location text,
  reporter_name text,
  reported_at timestamptz,
  status text,
  assigned_responder_name text,
  resolution_details text,
  is_reporter boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
BEGIN
  IF actor_id IS NULL OR public.northstar_is_designated_admin() OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Only confirmed, approved, active Northstar employees may list company incidents.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT listed.id, listed.title, listed.description, listed.category,
         listed.severity, listed.location, listed.reporter_name,
         listed.reported_at, listed.status, listed.assigned_responder_name,
         listed.resolution_details, listed.is_reporter
  FROM public.northstar_list_company_incidents() AS listed
  JOIN public.northstar_incidents AS incident ON incident.id = listed.id
  WHERE incident.deleted_at IS NULL
  ORDER BY listed.reported_at DESC;
END;
$function$;

-- Admin notes and response-team messages retain their existing narrower
-- audiences. Companywide history includes reporter-visible events; response
-- team events are visible only to the incident's assigned responder.
CREATE OR REPLACE FUNCTION public.northstar_list_company_incident_history(p_incident_ids uuid[])
RETURNS TABLE (
  id uuid,
  incident_id uuid,
  event_type text,
  old_status text,
  new_status text,
  old_severity text,
  new_severity text,
  details text,
  created_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
BEGIN
  IF actor_id IS NULL OR public.northstar_is_designated_admin() OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Only confirmed, approved, active Northstar employees may list company incident history.' USING ERRCODE = '42501';
  END IF;

  IF p_incident_ids IS NULL OR cardinality(p_incident_ids) = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT update_row.id, update_row.incident_id, update_row.event_type,
         update_row.old_status, update_row.new_status,
         update_row.old_severity, update_row.new_severity,
         CASE
           WHEN update_row.visibility = 'response_team' THEN update_row.details
           WHEN incident.reported_by = actor_id THEN update_row.details
           ELSE NULL
         END,
         update_row.created_at
  FROM public.northstar_incident_updates AS update_row
  JOIN public.northstar_incidents AS incident ON incident.id = update_row.incident_id
  WHERE update_row.incident_id = ANY (p_incident_ids)
    AND update_row.event_type <> 'admin_update'
    AND update_row.visibility <> 'admin'
    AND (
      update_row.visibility = 'reporter'
      OR (
        update_row.visibility = 'response_team'
        AND EXISTS (
        SELECT 1 FROM public.northstar_incidents AS assigned_incident
          WHERE assigned_incident.id = update_row.incident_id
            AND assigned_incident.assigned_responder = actor_id
            AND assigned_incident.deleted_at IS NULL
        )
      )
    )
    AND EXISTS (
      SELECT 1
      FROM public.northstar_list_active_company_incidents() AS visible_incident
      WHERE visible_incident.id = update_row.incident_id
    )
  ORDER BY update_row.created_at, update_row.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.northstar_reporter_edit_incident(
  p_incident_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_severity text,
  p_location text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  incident public.northstar_incidents%ROWTYPE;
  changed_fields text[];
BEGIN
  IF actor_id IS NULL OR public.northstar_is_designated_admin() OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Only confirmed, approved, active Northstar employees may edit incident reports.' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL
     OR p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 5 AND 180
     OR p_description IS NULL OR length(btrim(p_description)) NOT BETWEEN 10 AND 10000
     OR p_location IS NULL OR length(btrim(p_location)) NOT BETWEEN 2 AND 500
     OR p_category IS NULL OR p_category NOT IN ('fire', 'medical', 'security', 'natural_disaster', 'hazardous_material', 'infrastructure', 'other')
     OR p_severity IS NULL OR p_severity NOT IN ('low', 'medium', 'high', 'critical') THEN
    RAISE EXCEPTION 'Incident fields are invalid or incomplete.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO incident
  FROM public.northstar_incidents AS target
  WHERE target.id = p_incident_id
  FOR UPDATE;
  IF NOT FOUND OR incident.reported_by IS DISTINCT FROM actor_id OR incident.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Incident was not found or is not available for editing.' USING ERRCODE = '42501';
  END IF;

  changed_fields := array_remove(ARRAY[
    CASE WHEN incident.title IS DISTINCT FROM btrim(p_title) THEN 'title' END,
    CASE WHEN incident.description IS DISTINCT FROM btrim(p_description) THEN 'description' END,
    CASE WHEN incident.category IS DISTINCT FROM p_category THEN 'category' END,
    CASE WHEN incident.severity IS DISTINCT FROM p_severity THEN 'severity' END,
    CASE WHEN incident.location IS DISTINCT FROM btrim(p_location) THEN 'location' END
  ], NULL);
  IF cardinality(changed_fields) = 0 THEN
    RAISE EXCEPTION 'No incident fields were changed.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.northstar_incidents AS target
  SET title = btrim(p_title),
      description = btrim(p_description),
      category = p_category,
      severity = p_severity,
      location = btrim(p_location),
      updated_at = clock_timestamp()
  WHERE target.id = incident.id;

  INSERT INTO public.northstar_incident_updates (
    incident_id, actor_id, event_type, visibility,
    old_severity, new_severity, details
  ) VALUES (
    incident.id, actor_id, 'reporter_update', 'reporter',
    incident.severity, p_severity,
    'Reporter edited incident fields: ' || array_to_string(changed_fields, ', ') || '.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.northstar_reporter_soft_delete_incident(p_incident_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  incident public.northstar_incidents%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR public.northstar_is_designated_admin() OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Only confirmed, approved, active Northstar employees may delete incident reports.' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL THEN
    RAISE EXCEPTION 'An incident ID is required.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO incident
  FROM public.northstar_incidents AS target
  WHERE target.id = p_incident_id
  FOR UPDATE;
  IF NOT FOUND OR incident.reported_by IS DISTINCT FROM actor_id OR incident.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Incident was not found or is not available for deletion.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.northstar_incidents AS target
  SET deleted_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE target.id = incident.id;

  INSERT INTO public.northstar_incident_updates (
    incident_id, actor_id, event_type, visibility, details
  ) VALUES (
    incident.id, actor_id, 'reporter_update', 'reporter', 'Reporter deleted this incident report.'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.northstar_list_active_company_incidents() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.northstar_list_company_incident_history(uuid[]) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.northstar_reporter_edit_incident(uuid, text, text, text, text, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.northstar_reporter_soft_delete_incident(uuid) FROM PUBLIC, anon, service_role;
-- The legacy list has no deleted_at filter. Keep it callable only inside the
-- SECURITY DEFINER wrapper above so client RPC calls cannot reveal deleted rows.
REVOKE ALL ON FUNCTION public.northstar_list_company_incidents() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_list_active_company_incidents() TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_list_company_incident_history(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_reporter_edit_incident(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_reporter_soft_delete_incident(uuid) TO authenticated;

COMMENT ON FUNCTION public.northstar_list_active_company_incidents() IS
  'NorthStar employee incident list. Delegates visibility and field privacy to northstar_list_company_incidents and excludes soft-deleted rows.';
COMMENT ON FUNCTION public.northstar_list_company_incident_history(uuid[]) IS
  'NorthStar company incident history. Excludes admin-only events and preserves response-team visibility restrictions.';
COMMENT ON FUNCTION public.northstar_reporter_edit_incident(uuid, text, text, text, text, text) IS
  'NorthStar reporter-owned incident edit with eligibility, ownership, locking, validation, and audit-event checks.';
COMMENT ON FUNCTION public.northstar_reporter_soft_delete_incident(uuid) IS
  'NorthStar reporter-owned soft deletion; incident history and foreign-key relationships are retained.';

DO $acl_check$
DECLARE
  target_function regprocedure;
BEGIN
  FOREACH target_function IN ARRAY ARRAY[
    'public.northstar_list_active_company_incidents()'::regprocedure,
    'public.northstar_list_company_incident_history(uuid[])'::regprocedure,
    'public.northstar_reporter_edit_incident(uuid,text,text,text,text,text)'::regprocedure,
    'public.northstar_reporter_soft_delete_incident(uuid)'::regprocedure
  ] LOOP
    IF has_function_privilege('anon', target_function, 'EXECUTE')
       OR has_function_privilege('service_role', target_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'ACL verification failed: anon or service_role can execute %.', target_function;
    END IF;
    IF NOT has_function_privilege('authenticated', target_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'ACL verification failed: authenticated cannot execute %.', target_function;
    END IF;
    IF EXISTS (
      SELECT 1
      FROM pg_proc AS procedure_row
      CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege
      WHERE procedure_row.oid = target_function
        AND privilege.privilege_type = 'EXECUTE'
        AND privilege.grantee NOT IN (
          procedure_row.proowner,
          (SELECT authenticated_role.oid FROM pg_roles AS authenticated_role WHERE authenticated_role.rolname = 'authenticated')
        )
    ) THEN
      RAISE EXCEPTION 'ACL verification failed: a role other than the function owner or authenticated has direct EXECUTE on %.', target_function;
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.northstar_list_company_incidents()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.northstar_list_company_incidents()', 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_proc AS procedure_row
       CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege
       WHERE procedure_row.oid = 'public.northstar_list_company_incidents()'::regprocedure
         AND privilege.privilege_type = 'EXECUTE'
         AND privilege.grantee = 0
     ) THEN
    RAISE EXCEPTION 'ACL verification failed: the legacy unfiltered incident list remains executable by a client role or PUBLIC.';
  END IF;
END;
$acl_check$;

NOTIFY pgrst, 'reload schema';
COMMIT;
