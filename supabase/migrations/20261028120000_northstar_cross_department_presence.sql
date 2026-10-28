BEGIN;

-- Preserve the live presence-list implementation and remove only the confirmed
-- department visibility predicate. Abort if the live function has drifted.
DO $migration$
DECLARE
  function_oid oid := to_regprocedure('public.northstar_list_employee_presence(uuid[])');
  function_definition text;
  updated_definition text;
  function_settings text[];
  function_is_security_definer boolean;
  function_owner oid;
  existing_acl aclitem[];
  authenticated_role oid := to_regrole('authenticated');
  anonymous_role oid := to_regrole('anon');
  post_function_owner oid;
  filter_clause constant text := 'AND public.can_access_department(target_profile.department_id)';
BEGIN
  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'Expected public.northstar_list_employee_presence(uuid[]) to exist before this migration.';
  END IF;
  IF authenticated_role IS NULL THEN
    RAISE EXCEPTION 'Expected the authenticated role to exist.';
  END IF;
  IF anonymous_role IS NULL THEN
    RAISE EXCEPTION 'Expected the anon role to exist so its effective EXECUTE privilege can be verified.';
  END IF;

  SELECT p.prosecdef, p.proconfig, p.proowner,
         coalesce(p.proacl, acldefault('f', p.proowner))
    INTO function_is_security_definer, function_settings, function_owner, existing_acl
  FROM pg_proc AS p
  WHERE p.oid = function_oid;

  RAISE NOTICE 'Existing northstar_list_employee_presence ACL: %', existing_acl;

  IF NOT function_is_security_definer
     OR NOT coalesce(function_settings @> ARRAY['search_path=""'], false)
     OR NOT coalesce(function_settings @> ARRAY['row_security=off'], false) THEN
    RAISE EXCEPTION 'Presence-list function security settings differ from the reviewed SECURITY DEFINER, empty search_path, row_security=off contract.';
  END IF;

  SELECT pg_get_functiondef(function_oid) INTO function_definition;
  IF position('auth.uid()' IN lower(function_definition)) = 0
     OR position('target_profile.approval_status' IN lower(function_definition)) = 0
     OR position('target_profile.employment_status' IN lower(function_definition)) = 0
     OR position('target_profile.role' IN lower(function_definition)) = 0 THEN
    RAISE EXCEPTION 'Presence-list function is missing an expected authentication or target-profile eligibility check; review the live definition before applying this migration.';
  END IF;
  IF length(function_definition) - length(replace(function_definition, filter_clause, '')) <> length(filter_clause) THEN
    RAISE EXCEPTION 'Expected exactly one occurrence of the confirmed department filter in the live presence-list definition.';
  END IF;

  updated_definition := replace(function_definition, filter_clause, '');
  EXECUTE updated_definition;

  -- Preserve all other role grants. Remove function execution only from the
  -- public and anonymous roles, then ensure authenticated can call the RPC.
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_list_employee_presence(uuid[]) FROM PUBLIC';
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.northstar_list_employee_presence(uuid[]) FROM anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.northstar_list_employee_presence(uuid[]) TO authenticated';

  SELECT pg_get_functiondef(p.oid), p.proowner
    INTO function_definition, post_function_owner
  FROM pg_proc AS p
  WHERE p.oid = function_oid;

  IF post_function_owner IS DISTINCT FROM function_owner THEN
    RAISE EXCEPTION 'Post-migration verification failed: the presence-list function owner changed.';
  END IF;
  IF position(filter_clause IN function_definition) > 0 THEN
    RAISE EXCEPTION 'Post-migration verification failed: department filter remains in the presence-list function.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc AS p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl
    WHERE p.oid = function_oid
      AND acl.grantee = 0
      AND acl.privilege_type = 'EXECUTE'
  )
     OR NOT has_function_privilege(authenticated_role, function_oid, 'EXECUTE')
     OR has_function_privilege(anonymous_role, function_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Post-migration verification failed: PUBLIC still has EXECUTE, authenticated lacks EXECUTE, or anon can execute directly or through inherited role membership.';
  END IF;
END;
$migration$;

NOTIFY pgrst, 'reload schema';

COMMIT;
