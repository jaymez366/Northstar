-- Fix the integer literal passed to the smallint department-level RPC.
-- Rewrites only the call expression in the installed function definition so
-- its authorization, eligibility checks, locking, and ACL remain unchanged.
BEGIN;

DO $migration$
DECLARE
  function_oid oid := to_regprocedure('public.northstar_admin_set_department_head(uuid,uuid,smallint)');
  original_definition text;
  corrected_definition text;
  broken_call text := 'northstar_admin_assign_department_level(p_user_id, p_department_id, 1);';
  corrected_call text := 'northstar_admin_assign_department_level(p_user_id, p_department_id, 1::smallint);';
BEGIN
  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'Required function public.northstar_admin_set_department_head(uuid,uuid,smallint) is missing.';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(function_oid) INTO original_definition;
  IF original_definition LIKE '%' || corrected_call || '%' THEN
    RETURN;
  END IF;
  IF original_definition NOT LIKE '%' || broken_call || '%' THEN
    RAISE EXCEPTION 'Department-head RPC differs from the reviewed definition; inspect it before applying the smallint correction.';
  END IF;

  corrected_definition := pg_catalog.replace(original_definition, broken_call, corrected_call);
  IF corrected_definition = original_definition
     OR pg_catalog.strpos(corrected_definition, broken_call) > 0 THEN
    RAISE EXCEPTION 'Could not safely rewrite the department-head RPC call.';
  END IF;

  EXECUTE corrected_definition;
END;
$migration$;

DO $validation$
DECLARE
  definition text := pg_catalog.pg_get_functiondef(
    'public.northstar_admin_set_department_head(uuid,uuid,smallint)'::regprocedure
  );
BEGIN
  IF definition NOT LIKE '%northstar_admin_assign_department_level(p_user_id, p_department_id, 1::smallint)%'
     OR definition LIKE '%northstar_admin_assign_department_level(p_user_id, p_department_id, 1);%' THEN
    RAISE EXCEPTION 'Department-head RPC smallint call validation failed.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    JOIN pg_roles AS owner_role ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = 'public.northstar_admin_set_department_head(uuid,uuid,smallint)'::regprocedure
      AND procedure_row.prosecdef IS TRUE
      AND owner_role.rolname = 'postgres'
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) THEN
    RAISE EXCEPTION 'Department-head RPC security configuration changed unexpectedly.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Department-head RPC execution grants changed unexpectedly.';
  END IF;
END;
$validation$;

COMMIT;
