-- Make organization-wide incidents visible to eligible workspace users while
-- preserving department boundaries, reporter filtering, and update visibility.
-- Apply after 20261102130000_northstar_messaging_attachment_upload_eligibility.sql.
BEGIN;

DO $preflight$
DECLARE
  incident_policy oid;
  updates_policy oid;
  incident_using text;
  updates_using text;
  list_definition text;
  history_definition text;
BEGIN
  IF to_regclass('public.northstar_incidents') IS NULL
     OR to_regclass('public.northstar_incident_updates') IS NULL
     OR to_regprocedure('northstar_private.is_eligible_workspace_user()') IS NULL
     OR to_regprocedure('northstar_private.is_eligible_department_member(uuid)') IS NULL
     OR to_regprocedure('public.northstar_is_designated_admin()') IS NULL
     OR to_regprocedure('public.northstar_department_list_incidents()') IS NULL
     OR to_regprocedure('public.northstar_department_list_incident_history(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'Company-wide incident visibility requires the existing incident tables, authorization helpers, and department incident RPCs.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class AS relation
    WHERE relation.oid IN ('public.northstar_incidents'::regclass, 'public.northstar_incident_updates'::regclass)
      AND relation.relrowsecurity IS FALSE
  ) THEN
    RAISE EXCEPTION 'Incident visibility migration requires RLS enabled on both incident tables.';
  END IF;

  SELECT policy.oid, pg_get_expr(policy.polqual, policy.polrelid)
  INTO incident_policy, incident_using
  FROM pg_policy AS policy
  WHERE policy.polrelid = 'public.northstar_incidents'::regclass
    AND policy.polname = 'northstar_incidents_department_guard';
  SELECT policy.oid, pg_get_expr(policy.polqual, policy.polrelid)
  INTO updates_policy, updates_using
  FROM pg_policy AS policy
  WHERE policy.polrelid = 'public.northstar_incident_updates'::regclass
    AND policy.polname = 'northstar_incident_updates_department_guard';

  IF incident_policy IS NULL OR updates_policy IS NULL THEN
    RAISE EXCEPTION 'The expected restrictive incident SELECT guards are missing.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.oid IN (incident_policy, updates_policy)
      AND (policy.polcmd <> 'r'::char OR policy.polpermissive IS TRUE
        OR policy.polroles <> ARRAY['authenticated'::regrole::oid])
  ) THEN
    RAISE EXCEPTION 'Incident SELECT guards differ from the expected restrictive authenticated SELECT policy contract.';
  END IF;

  IF incident_using NOT ILIKE '%northstar_is_designated_admin%'
     OR incident_using NOT ILIKE '%deleted_at IS NULL%'
     OR incident_using NOT ILIKE '%is_eligible_department_member%'
     OR incident_using NOT ILIKE '%reported_by%'
     OR incident_using NOT ILIKE '%is_eligible_workspace_user%'
     OR incident_using ILIKE '%department_id IS NULL%is_eligible_workspace_user%' THEN
    RAISE EXCEPTION 'The existing incident guard expression is unexpected or the company-wide visibility branch is already present; inspect before continuing.';
  END IF;
  IF updates_using NOT ILIKE '%northstar_is_designated_admin%'
     OR updates_using NOT ILIKE '%visibility%admin%'
     OR updates_using NOT ILIKE '%admin_update%'
     OR updates_using NOT ILIKE '%is_eligible_department_member%'
     OR updates_using NOT ILIKE '%response_team%'
     OR updates_using NOT ILIKE '%assigned_responder%'
     OR updates_using ILIKE '%i.department_id IS NULL%northstar_private.is_eligible_workspace_user%' THEN
    RAISE EXCEPTION 'The existing incident-update guard expression is unexpected or the company-wide visibility branch is already present; inspect before continuing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    WHERE procedure_row.oid = 'public.northstar_department_list_incidents()'::regprocedure
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.prorettype = 'record'::regtype
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    WHERE procedure_row.oid = 'public.northstar_department_list_incident_history(uuid[])'::regprocedure
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.prorettype = 'record'::regtype
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) THEN
    RAISE EXCEPTION 'Incident list/history RPC signatures or SECURITY DEFINER configurations differ from the reviewed department migration.';
  END IF;

  list_definition := pg_get_functiondef('public.northstar_department_list_incidents()'::regprocedure);
  history_definition := pg_get_functiondef('public.northstar_department_list_incident_history(uuid[])'::regprocedure);
  IF list_definition NOT ILIKE '%northstar_is_designated_admin%'
     OR list_definition NOT ILIKE '%department_id = actor_department%'
     OR list_definition NOT ILIKE '%reported_by = actor_id%'
     OR list_definition NOT ILIKE '%assigned_responder%'
     OR history_definition NOT ILIKE '%northstar_is_designated_admin%'
     OR history_definition NOT ILIKE '%department_id = actor_department%'
     OR history_definition NOT ILIKE '%reported_by = actor_id%'
     OR history_definition NOT ILIKE '%visibility <> ''admin''%'
     OR history_definition NOT ILIKE '%event_type <> ''admin_update''%'
     OR history_definition NOT ILIKE '%visibility <> ''response_team''%'
     OR history_definition NOT ILIKE '%assigned_responder = actor_id%' THEN
    RAISE EXCEPTION 'The installed incident list/history RPC bodies differ from the reviewed reporter, admin, department, or response-team contract.';
  END IF;
END;
$preflight$;

-- Preserve the full deployed restrictive predicate and add only an eligible,
-- non-deleted, null-department company-wide incident branch.
DO $extend_incident_guard$
DECLARE
  old_using text;
BEGIN
  SELECT pg_get_expr(policy.polqual, policy.polrelid) INTO old_using
  FROM pg_policy AS policy
  WHERE policy.polrelid = 'public.northstar_incidents'::regclass
    AND policy.polname = 'northstar_incidents_department_guard';

  EXECUTE format(
    'ALTER POLICY northstar_incidents_department_guard ON public.northstar_incidents USING ((%s) OR (deleted_at IS NULL AND department_id IS NULL AND northstar_private.is_eligible_workspace_user()))',
    old_using
  );
END;
$extend_incident_guard$;

-- Keep admin-only events hidden and response-team events limited to the
-- assigned responder. Only the incident-membership predicate gains the
-- company-wide, eligible-user case.
DO $extend_incident_updates_guard$
DECLARE
  old_using text;
BEGIN
  SELECT pg_get_expr(policy.polqual, policy.polrelid) INTO old_using
  FROM pg_policy AS policy
  WHERE policy.polrelid = 'public.northstar_incident_updates'::regclass
    AND policy.polname = 'northstar_incident_updates_department_guard';

  EXECUTE format(
    'ALTER POLICY northstar_incident_updates_department_guard ON public.northstar_incident_updates USING ((%s) OR (visibility <> ''admin'' AND event_type <> ''admin_update'' AND EXISTS (SELECT 1 FROM public.northstar_incidents AS i WHERE i.id = incident_id AND i.deleted_at IS NULL AND i.department_id IS NULL AND northstar_private.is_eligible_workspace_user() AND (visibility <> ''response_team'' OR i.assigned_responder = (SELECT auth.uid())))))',
    old_using
  );
END;
$extend_incident_updates_guard$;

CREATE OR REPLACE FUNCTION public.northstar_department_list_incidents()
RETURNS TABLE (
  id uuid, title text, description text, category text, severity text, location text,
  reported_by uuid, reporter_name text, reported_at timestamptz, status text,
  assigned_responder uuid, resolution_details text, department_id uuid,
  deleted_at timestamptz, is_reporter boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  actor_department uuid;
BEGIN
  SELECT profile.department_id INTO actor_department
  FROM public.profiles AS profile
  JOIN auth.users AS account ON account.id = profile.id
  WHERE profile.id = actor_id
    AND profile.role::text IN ('employee', 'manager')
    AND profile.department_level BETWEEN 1 AND 5
    AND profile.registration_completed IS TRUE
    AND profile.approval_status::text = 'approved'
    AND profile.employment_status::text = 'active'
    AND account.email_confirmed_at IS NOT NULL;

  IF actor_id IS NULL
     OR (actor_department IS NULL AND NOT public.northstar_is_designated_admin()
       AND NOT northstar_private.is_eligible_workspace_user()) THEN
    RAISE EXCEPTION 'An approved employee account is required to view incidents.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT incident.id, incident.title, incident.description, incident.category,
    incident.severity, incident.location,
    CASE WHEN public.northstar_is_designated_admin() OR incident.reported_by = actor_id
      THEN incident.reported_by ELSE NULL END,
    CASE WHEN public.northstar_is_designated_admin() OR incident.reported_by = actor_id
      THEN NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ', reporter.first_name, reporter.last_name)), '') ELSE NULL END,
    incident.reported_at, incident.status,
    CASE WHEN public.northstar_is_designated_admin() OR incident.reported_by = actor_id
      OR incident.assigned_responder = actor_id
      OR northstar_private.is_department_head(incident.department_id)
      THEN incident.assigned_responder ELSE NULL END,
    incident.resolution_details, incident.department_id, incident.deleted_at,
    incident.reported_by = actor_id
  FROM public.northstar_incidents AS incident
  JOIN public.profiles AS reporter ON reporter.id = incident.reported_by
  WHERE public.northstar_is_designated_admin()
    OR (incident.deleted_at IS NULL AND (
      incident.department_id = actor_department
      OR incident.reported_by = actor_id
      OR (incident.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
    ))
  ORDER BY incident.reported_at DESC;
END;
$function$;
ALTER FUNCTION public.northstar_department_list_incidents() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_list_incidents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_list_incidents() TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_department_list_incident_history(p_incident_ids uuid[])
RETURNS TABLE (
  id uuid, incident_id uuid, event_type text, old_status text, new_status text,
  old_severity text, new_severity text, details text, created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  actor_department uuid;
BEGIN
  SELECT profile.department_id INTO actor_department
  FROM public.profiles AS profile
  JOIN auth.users AS account ON account.id = profile.id
  WHERE profile.id = actor_id
    AND profile.role::text IN ('employee', 'manager')
    AND profile.department_level BETWEEN 1 AND 5
    AND profile.registration_completed IS TRUE
    AND profile.approval_status::text = 'approved'
    AND profile.employment_status::text = 'active'
    AND account.email_confirmed_at IS NOT NULL;

  IF actor_id IS NULL
     OR (actor_department IS NULL AND NOT public.northstar_is_designated_admin()
       AND NOT northstar_private.is_eligible_workspace_user()) THEN
    RAISE EXCEPTION 'Eligible workspace access is required to view incident history.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT update_row.id, update_row.incident_id, update_row.event_type,
    update_row.old_status, update_row.new_status, update_row.old_severity,
    update_row.new_severity,
    CASE WHEN public.northstar_is_designated_admin()
      OR incident.assigned_responder = actor_id
      OR (update_row.visibility = 'reporter' AND incident.reported_by = actor_id)
      THEN update_row.details ELSE NULL END,
    update_row.created_at
  FROM public.northstar_incident_updates AS update_row
  JOIN public.northstar_incidents AS incident ON incident.id = update_row.incident_id
  WHERE update_row.incident_id = ANY(p_incident_ids)
    AND (public.northstar_is_designated_admin() OR (
      incident.deleted_at IS NULL AND (
        incident.department_id = actor_department
        OR incident.reported_by = actor_id
        OR (incident.department_id IS NULL AND northstar_private.is_eligible_workspace_user())
      )
    ))
    AND (public.northstar_is_designated_admin()
      OR (update_row.visibility <> 'admin' AND update_row.event_type <> 'admin_update'))
    AND (update_row.visibility <> 'response_team'
      OR public.northstar_is_designated_admin()
      OR incident.assigned_responder = actor_id)
  ORDER BY update_row.created_at, update_row.id;
END;
$function$;
ALTER FUNCTION public.northstar_department_list_incident_history(uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_department_list_incident_history(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_department_list_incident_history(uuid[]) TO authenticated;

DO $postflight$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.northstar_department_list_incidents()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_department_list_incidents()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.northstar_department_list_incident_history(uuid[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_department_list_incident_history(uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'Incident list/history RPC permissions do not match the authenticated-only contract.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege_row
    WHERE procedure_row.oid IN (
      'public.northstar_department_list_incidents()'::regprocedure,
      'public.northstar_department_list_incident_history(uuid[])'::regprocedure
    ) AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    WHERE procedure_row.oid = 'public.northstar_department_list_incidents()'::regprocedure
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    WHERE procedure_row.oid = 'public.northstar_department_list_incident_history(uuid[])'::regprocedure
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) THEN
    RAISE EXCEPTION 'Incident list/history RPC ownership, SECURITY DEFINER configuration, or PUBLIC ACL differs from the expected contract.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.polrelid = 'public.northstar_incidents'::regclass
      AND policy.polname = 'northstar_incidents_department_guard'
      AND policy.polcmd = 'r'::char AND policy.polpermissive IS FALSE
      AND policy.polroles = ARRAY['authenticated'::regrole::oid]
      AND pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%department_id IS NULL%is_eligible_workspace_user%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.polrelid = 'public.northstar_incident_updates'::regclass
      AND policy.polname = 'northstar_incident_updates_department_guard'
      AND policy.polcmd = 'r'::char AND policy.polpermissive IS FALSE
      AND policy.polroles = ARRAY['authenticated'::regrole::oid]
      AND pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%i.department_id IS NULL%northstar_private.is_eligible_workspace_user%'
      AND pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%visibility%response_team%assigned_responder%'
      AND pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%admin_update%'
  ) THEN
    RAISE EXCEPTION 'Incident restrictive policies did not retain their original contract and the scoped company-wide branch.';
  END IF;
END;
$postflight$;

COMMIT;

-- Read-only post-migration verification:
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE (schemaname, tablename, policyname) IN (
--   ('public', 'northstar_incidents', 'northstar_incidents_department_guard'),
--   ('public', 'northstar_incident_updates', 'northstar_incident_updates_department_guard')
-- ) ORDER BY tablename, policyname;
-- SELECT p.oid::regprocedure AS signature, pg_get_userbyid(p.proowner) AS owner,
--        p.prosecdef AS security_definer, p.proconfig,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute
-- FROM pg_proc AS p
-- WHERE p.oid IN (
--   to_regprocedure('public.northstar_department_list_incidents()'),
--   to_regprocedure('public.northstar_department_list_incident_history(uuid[])')
-- );
-- SELECT pg_get_functiondef('public.northstar_department_list_incidents()'::regprocedure),
--        pg_get_functiondef('public.northstar_department_list_incident_history(uuid[])'::regprocedure);
