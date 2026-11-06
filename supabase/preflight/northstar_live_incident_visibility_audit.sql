-- NorthStar live incident visibility audit
-- READ ONLY: catalog inspection and SELECT statements only.
-- Run as one script in the verified NorthStar project's Supabase SQL Editor.
-- Results contain complete routine definitions and policy expressions, but
-- no incident descriptions, locations, or personal incident identifiers.

-- 00. Execution context (does not identify or expose connection secrets).
SELECT '00_execution_context' AS section,
       current_database() AS database_name,
       current_user AS executing_role,
       current_setting('server_version') AS server_version;

-- 01. Relation presence, RLS flags, and all columns, types, defaults, nullability.
SELECT '01_incident_table_columns' AS section,
       n.nspname AS table_schema,
       c.relname AS table_name,
       CASE WHEN c.oid IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS object_status,
       CASE WHEN c.oid IS NULL THEN NULL ELSE c.relrowsecurity END AS rls_enabled,
       CASE WHEN c.oid IS NULL THEN NULL ELSE c.relforcerowsecurity END AS force_row_level_security,
       a.attnum AS ordinal_position,
       a.attname AS column_name,
       CASE WHEN a.attnum IS NULL THEN NULL ELSE pg_catalog.format_type(a.atttypid, a.atttypmod) END AS data_type,
       CASE WHEN a.attnum IS NULL THEN NULL ELSE NOT a.attnotnull END AS is_nullable,
       pg_catalog.pg_get_expr(d.adbin, d.adrelid) AS column_default,
       CASE WHEN a.attnum IS NULL THEN NULL ELSE a.attidentity END AS identity_kind,
       CASE WHEN a.attnum IS NULL THEN NULL ELSE a.attgenerated END AS generated_kind
FROM (VALUES ('public','northstar_incidents'),
             ('public','northstar_incident_updates')) AS target(schema_name, table_name)
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = target.schema_name
LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid AND c.relname = target.table_name
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
ORDER BY target.table_name, a.attnum;

-- 02. Primary keys, foreign keys, unique/check/exclusion constraints.
SELECT '02_incident_table_constraints' AS section,
       n.nspname AS table_schema,
       c.relname AS table_name,
       con.conname AS constraint_name,
       con.contype AS constraint_type_code,
       CASE con.contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
         WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK' WHEN 'x' THEN 'EXCLUSION'
         ELSE con.contype::text END AS constraint_type,
       pg_catalog.pg_get_constraintdef(con.oid, true) AS exact_definition,
       con.convalidated AS is_validated,
       con.condeferrable AS is_deferrable,
       con.condeferred AS initially_deferred
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_constraint con ON con.conrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('northstar_incidents','northstar_incident_updates')
ORDER BY c.relname, con.conname;

-- 03. Index definitions and validity, including indexes not owned by constraints.
SELECT '03_incident_table_indexes' AS section,
       n.nspname AS table_schema,
       tbl.relname AS table_name,
       idx.relname AS index_name,
       pg_catalog.pg_get_indexdef(i.indexrelid) AS exact_definition,
       i.indisprimary AS is_primary,
       i.indisunique AS is_unique,
       i.indisvalid AS is_valid,
       i.indisready AS is_ready,
       i.indislive AS is_live
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class tbl ON tbl.oid = i.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid = tbl.relnamespace
JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
WHERE n.nspname = 'public'
  AND tbl.relname IN ('northstar_incidents','northstar_incident_updates')
ORDER BY tbl.relname, idx.relname;

-- 04. Every policy on both tables, with full expressions (NULL means absent).
SELECT '04_incident_rls_policies' AS section,
       n.nspname AS table_schema,
       c.relname AS table_name,
       CASE WHEN c.oid IS NULL THEN 'NO TABLE / NO POLICIES' ELSE 'POLICIES BELOW' END AS object_status,
       p.polname AS policy_name,
       CASE p.polcmd WHEN '*' THEN 'ALL' WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
         WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' ELSE p.polcmd::text END AS command,
       CASE WHEN p.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END AS policy_mode,
       ARRAY(SELECT CASE WHEN role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_oid) END
             FROM unnest(p.polroles) AS role_oid) AS roles,
       pg_catalog.pg_get_expr(p.polqual, p.polrelid, true) AS using_expression,
       pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid, true) AS with_check_expression
FROM (VALUES ('public','northstar_incidents'),
             ('public','northstar_incident_updates')) AS target(schema_name, table_name)
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = target.schema_name
LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid AND c.relname = target.table_name
LEFT JOIN pg_catalog.pg_policy p ON p.polrelid = c.oid
ORDER BY target.table_name, p.polname;

-- 05a. Effective table privileges for expected roles and direct table ACL entries.
SELECT '05a_incident_table_privileges' AS section,
       n.nspname AS table_schema,
       c.relname AS table_name,
       role_check.role_name,
       privilege_check.privilege_name,
       CASE WHEN c.oid IS NULL THEN NULL
            WHEN NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = role_check.role_name) THEN NULL
            ELSE pg_catalog.has_table_privilege(role_check.role_name, c.oid, privilege_check.privilege_name) END AS effective_privilege,
       acl.grantee_name AS direct_acl_grantee,
       acl.grantor_name AS direct_acl_grantor,
       acl.privilege_type AS direct_acl_privilege,
       acl.is_grantable AS direct_acl_grantable
FROM (VALUES ('public','northstar_incidents'),
             ('public','northstar_incident_updates')) AS target(schema_name, table_name)
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = target.schema_name
LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid AND c.relname = target.table_name
CROSS JOIN (VALUES ('authenticated'),('service_role'),('anon')) AS role_check(role_name)
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) AS privilege_check(privilege_name)
LEFT JOIN LATERAL (
  SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee_name,
         pg_catalog.pg_get_userbyid(x.grantor) AS grantor_name,
         x.privilege_type,
         x.is_grantable
  FROM pg_catalog.aclexplode(COALESCE(c.relacl, pg_catalog.acldefault('r', c.relowner))) AS x
) acl ON acl.privilege_type = privilege_check.privilege_name
ORDER BY target.table_name, role_check.role_name, privilege_check.privilege_name, acl.grantee_name, acl.privilege_type;

-- 05b. Effective column privileges and explicit column ACL entries.
SELECT '05b_incident_column_privileges' AS section,
       n.nspname AS table_schema,
       c.relname AS table_name,
       a.attname AS column_name,
       role_check.role_name,
       privilege_check.privilege_name,
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = role_check.role_name) THEN NULL
            ELSE pg_catalog.has_column_privilege(role_check.role_name, c.oid, a.attname, privilege_check.privilege_name) END AS effective_privilege,
       acl.grantee_name AS direct_acl_grantee,
       acl.grantor_name AS direct_acl_grantor,
       acl.privilege_type AS direct_acl_privilege,
       acl.is_grantable AS direct_acl_grantable
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
CROSS JOIN (VALUES ('authenticated'),('service_role'),('anon')) AS role_check(role_name)
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES')) AS privilege_check(privilege_name)
LEFT JOIN LATERAL (
  SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee_name,
         pg_catalog.pg_get_userbyid(x.grantor) AS grantor_name,
         x.privilege_type,
         x.is_grantable
  FROM pg_catalog.aclexplode(a.attacl) AS x
) acl ON acl.privilege_type = privilege_check.privilege_name
WHERE n.nspname = 'public'
  AND c.relname IN ('northstar_incidents','northstar_incident_updates')
ORDER BY c.relname, a.attnum, role_check.role_name, privilege_check.privilege_name, acl.grantee_name;

-- 06. Full definitions/security metadata/ACLs for incident RPCs, their helpers,
-- and trigger functions. PUBLIC direct grants appear as acl_grantee='PUBLIC'.
SELECT '06a_expected_incident_rpc_presence' AS section,
       expected.routine_name,
       CASE WHEN found.oid IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS object_status,
       found.identity_arguments
FROM (VALUES ('northstar_department_list_incidents'),
             ('northstar_department_list_incident_history'),
             ('northstar_report_incident'),
             ('northstar_admin_report_company_incident'),
             ('northstar_admin_update_incident'),
             ('northstar_department_report_incident'),
             ('northstar_department_head_update_incident'),
             ('northstar_reporter_edit_incident'),
             ('northstar_reporter_soft_delete_incident')) AS expected(routine_name)
LEFT JOIN LATERAL (
  SELECT p.oid, pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='public' AND p.proname=expected.routine_name
  ORDER BY p.oid
) found ON true
ORDER BY expected.routine_name;

SELECT '06a2_authorization_helper_presence' AS section,
       expected.helper_group,
       CASE WHEN found.oid IS NULL THEN 'NOT FOUND' ELSE 'PRESENT' END AS object_status,
       found.routine_schema,
       found.routine_name,
       found.identity_arguments
FROM (VALUES
  ('workspace eligibility helper','workspace_eligibility_helper'),
  ('workspace eligibility function','%eligible_workspace_user%'),
  ('department eligibility helper','department_eligibility_helper'),
  ('department eligibility function','%eligible_department_member%'),
  ('department head helper','department_head_helper'),
  ('department head function','%is_department_head%'),
  ('designated admin helper','designated_admin_helper'),
  ('designated admin function','%designated_admin%'),
  ('northstar_is_designated_admin','northstar_is_designated_admin'),
  ('has_any_role','has_any_role')
) AS expected(helper_group, name_pattern)
LEFT JOIN LATERAL (
  SELECT ns.nspname AS routine_schema,
         p.proname AS routine_name,
         p.oid,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname IN ('public','northstar_private')
    AND (p.proname=expected.name_pattern OR p.proname ILIKE expected.name_pattern)
  ORDER BY ns.nspname,p.proname,p.oid
) found ON true
ORDER BY expected.helper_group, found.routine_schema, found.routine_name, found.identity_arguments;

SELECT '06b_incident_routine_definitions_and_security' AS section,
       ns.nspname AS routine_schema,
       p.proname AS routine_name,
       pg_catalog.oidvectortypes(p.proargtypes) AS argument_types,
       pg_catalog.pg_get_function_arguments(p.oid) AS argument_names_and_defaults,
       pg_catalog.pg_get_function_result(p.oid) AS return_type,
       p.prokind AS routine_kind,
       owner_role.rolname AS owner,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility_code,
       CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE' WHEN 's' THEN 'STABLE' WHEN 'v' THEN 'VOLATILE' END AS volatility,
       p.proconfig AS configuration_settings,
       (SELECT setting FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config(setting)
        WHERE setting LIKE 'search_path=%' LIMIT 1) AS search_path_setting,
       (SELECT setting FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config(setting)
        WHERE setting LIKE 'row_security=%' LIMIT 1) AS row_security_setting,
       p.proconfig @> ARRAY['search_path=""'] AS has_empty_search_path_setting,
       p.proconfig @> ARRAY['row_security=off'] AS has_row_security_off_setting,
       pg_catalog.pg_get_functiondef(p.oid) AS complete_definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace ns ON ns.oid = p.pronamespace
JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
WHERE ns.nspname IN ('public','northstar_private')
  AND (
    p.proname ILIKE '%incident%'
    OR p.proname ILIKE '%eligible%'
    OR p.proname ILIKE '%department_head%'
    OR p.proname ILIKE '%designated_admin%'
    OR p.proname ILIKE '%workspace%eligib%'
    OR p.proname ILIKE '%department%eligib%'
    OR p.proname ILIKE '%department%head%'
    OR p.proname IN ('workspace_eligibility_helper','department_eligibility_helper',
                     'department_head_helper','designated_admin_helper',
                     'northstar_is_designated_admin','has_any_role')
    OR pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'northstar_incidents') > 0
    OR pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'northstar_incident_updates') > 0
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgfoid = p.oid AND NOT t.tgisinternal
               AND t.tgrelid IN (SELECT c.oid FROM pg_catalog.pg_class c
                                 JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                                 WHERE n.nspname = 'public' AND c.relname IN ('northstar_incidents','northstar_incident_updates')))
  )
ORDER BY ns.nspname, p.proname, p.oid;

-- 06c. Effective EXECUTE and all direct ACL entries, without duplicating source.
SELECT '06c_incident_routine_execute_permissions' AS section,
       ns.nspname AS routine_schema,
       p.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       role_exec.role_name,
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = role_exec.role_name) THEN NULL
            ELSE pg_catalog.has_function_privilege(role_exec.role_name, p.oid, 'EXECUTE') END AS effective_execute,
       acl.grantee_name AS direct_acl_grantee,
       acl.grantor_name AS direct_acl_grantor,
       acl.privilege_type AS direct_acl_privilege,
       acl.is_grantable AS direct_acl_grantable
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace ns ON ns.oid = p.pronamespace
CROSS JOIN (VALUES ('authenticated'),('service_role'),('anon')) AS role_exec(role_name)
LEFT JOIN LATERAL (
  SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee_name,
         pg_catalog.pg_get_userbyid(x.grantor) AS grantor_name,
         x.privilege_type,
         x.is_grantable
  FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS x
) acl ON true
WHERE ns.nspname IN ('public','northstar_private')
  AND (
    p.proname ILIKE '%incident%'
    OR p.proname ILIKE '%eligible%'
    OR p.proname ILIKE '%department_head%'
    OR p.proname ILIKE '%designated_admin%'
    OR p.proname ILIKE '%workspace%eligib%'
    OR p.proname ILIKE '%department%eligib%'
    OR p.proname ILIKE '%department%head%'
    OR p.proname IN ('workspace_eligibility_helper','department_eligibility_helper',
                     'department_head_helper','designated_admin_helper',
                     'northstar_is_designated_admin','has_any_role')
    OR pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'northstar_incidents') > 0
    OR pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'northstar_incident_updates') > 0
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgfoid = p.oid AND NOT t.tgisinternal
               AND t.tgrelid IN (SELECT c.oid FROM pg_catalog.pg_class c
                                 JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                                 WHERE n.nspname = 'public' AND c.relname IN ('northstar_incidents','northstar_incident_updates')))
  )
ORDER BY ns.nspname, p.proname, p.oid, role_exec.role_name, acl.grantee_name;

-- 07. All triggers on the two incident tables and their complete trigger SQL.
SELECT '07_incident_triggers' AS section,
       n.nspname AS table_schema,
       tbl.relname AS table_name,
       t.tgname AS trigger_name,
       t.tgenabled AS enabled_code,
       CASE t.tgenabled WHEN 'O' THEN 'ORIGIN_AND_LOCAL' WHEN 'D' THEN 'DISABLED'
         WHEN 'R' THEN 'REPLICA' WHEN 'A' THEN 'ALWAYS' END AS enabled_mode,
       t.tgisinternal AS is_internal,
       pg_catalog.pg_get_triggerdef(t.oid, true) AS complete_trigger_definition,
       fn_ns.nspname AS function_schema,
       fn.proname AS function_name,
       pg_catalog.pg_get_functiondef(fn.oid) AS complete_trigger_function_definition
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class tbl ON tbl.oid = t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid = tbl.relnamespace
JOIN pg_catalog.pg_proc fn ON fn.oid = t.tgfoid
JOIN pg_catalog.pg_namespace fn_ns ON fn_ns.oid = fn.pronamespace
WHERE n.nspname = 'public'
  AND tbl.relname IN ('northstar_incidents','northstar_incident_updates')
ORDER BY tbl.relname, t.tgname;

-- Optional columns are catalog-checked. XML is expanded to ordinary result
-- columns so counts are readable; only aggregates enter the generated SELECT.
WITH target AS (
  SELECT n.nspname, c.relname, c.oid,
         c.relrowsecurity, c.relforcerowsecurity
  FROM pg_catalog.pg_namespace n
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname='northstar_incidents'
  WHERE n.nspname='public'
), aggregate_xml AS (
  SELECT target.*,
         CASE WHEN target.oid IS NULL THEN 'MISSING TABLE'
              WHEN NOT pg_catalog.has_table_privilege(current_user, target.oid, 'SELECT') THEN 'NO SELECT PRIVILEGE'
              WHEN pg_catalog.row_security_active(format('%I.%I',target.nspname,target.relname)) THEN 'RLS ACTIVE: counts may reflect only rows visible to this role'
              ELSE 'AGGREGATES BELOW' END AS result_status,
         CASE WHEN target.oid IS NULL OR NOT pg_catalog.has_table_privilege(current_user,target.oid,'SELECT') THEN NULL
              ELSE pg_catalog.query_to_xml(
                pg_catalog.format(
                  'SELECT count(*)::bigint AS total_incidents, %s AS deleted_incidents, %s AS with_department, %s AS without_department, %s AS with_resolution_details, %s AS counts_by_status, %s AS counts_by_severity FROM %I.%I',
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='deleted_at' AND attnum>0 AND NOT attisdropped) THEN 'count(*) FILTER (WHERE deleted_at IS NOT NULL)::bigint' ELSE 'NULL::bigint' END,
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='department_id' AND attnum>0 AND NOT attisdropped) THEN 'count(*) FILTER (WHERE department_id IS NOT NULL)::bigint' ELSE 'NULL::bigint' END,
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='department_id' AND attnum>0 AND NOT attisdropped) THEN 'count(*) FILTER (WHERE department_id IS NULL)::bigint' ELSE 'NULL::bigint' END,
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='resolution_details' AND attnum>0 AND NOT attisdropped) THEN 'count(*) FILTER (WHERE resolution_details IS NOT NULL)::bigint' ELSE 'NULL::bigint' END,
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='status' AND attnum>0 AND NOT attisdropped) THEN '(SELECT jsonb_object_agg(COALESCE(''VALUE:'' || status::text, ''[NULL]''), row_count) FROM (SELECT status, count(*)::bigint AS row_count FROM public.northstar_incidents GROUP BY status) s)' ELSE 'NULL::jsonb' END,
                  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=target.oid AND attname='severity' AND attnum>0 AND NOT attisdropped) THEN '(SELECT jsonb_object_agg(COALESCE(''VALUE:'' || severity::text, ''[NULL]''), row_count) FROM (SELECT severity, count(*)::bigint AS row_count FROM public.northstar_incidents GROUP BY severity) v)' ELSE 'NULL::jsonb' END,
                  target.nspname,target.relname
                ), true, false, '') END AS aggregate_result_xml
  FROM target
)
SELECT '08_incident_aggregate_counts' AS section,
       a.nspname AS table_schema,
       COALESCE(a.relname,'northstar_incidents') AS table_name,
       a.result_status,
       x.total_incidents,
       x.deleted_incidents,
       x.with_department,
       x.without_department,
       x.with_resolution_details,
       x.counts_by_status,
       x.counts_by_severity
FROM aggregate_xml a
LEFT JOIN LATERAL XMLTABLE(
  '/table/row' PASSING a.aggregate_result_xml
  COLUMNS total_incidents bigint PATH 'total_incidents',
          deleted_incidents bigint PATH 'deleted_incidents',
          with_department bigint PATH 'with_department',
          without_department bigint PATH 'without_department',
          with_resolution_details bigint PATH 'with_resolution_details',
          counts_by_status text PATH 'counts_by_status',
          counts_by_severity text PATH 'counts_by_severity'
) AS x ON true;

-- 09a. Locate plausible migration-history relations and their version columns.
-- A missing candidate is not evidence that any migration is pending.
SELECT '09a_migration_history_relation_candidates' AS section,
       n.nspname AS schema_name,
       c.relname AS relation_name,
       c.relkind AS relation_kind_code,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_row_level_security,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS version_column_type,
       CASE WHEN a.attname IS NULL THEN 'NO version column found'
            WHEN NOT pg_catalog.has_table_privilege(current_user, c.oid, 'SELECT') THEN 'version column found; no SELECT privilege'
            ELSE 'version column readable' END AS inspection_status
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attname='version' AND a.attnum>0 AND NOT a.attisdropped
WHERE c.relkind IN ('r','p')
  AND (n.nspname ILIKE '%migration%' OR c.relname ILIKE '%migration%' OR c.relname='schema_migrations')
ORDER BY n.nspname, c.relname;

-- 09b. Read expected versions from every detected candidate relation having a
-- version column and SELECT access. query_to_xml executes only a SELECT and
-- returns version identifiers only. Unrecognized ledger formats remain unknown.
SELECT '09b_november_3_migration_version_status' AS section,
       n.nspname AS ledger_schema,
       c.relname AS ledger_relation,
       expected.version AS migration_version,
       expected.migration_file,
       CASE WHEN a.attname IS NULL THEN 'CANNOT CHECK: no version column'
            WHEN NOT pg_catalog.has_table_privilege(current_user, c.oid, 'SELECT') THEN 'CANNOT CHECK: no SELECT privilege'
            WHEN pg_catalog.row_security_active(c.oid::regclass::text) THEN 'CANNOT CONFIRM ABSENCE: row security is active for this role'
            ELSE 'CHECKED IN XML BELOW' END AS check_status,
       CASE WHEN a.attname IS NULL OR NOT pg_catalog.has_table_privilege(current_user, c.oid, 'SELECT')
                 OR pg_catalog.row_security_active(c.oid::regclass::text) THEN NULL
            ELSE pg_catalog.query_to_xml(
              pg_catalog.format('SELECT version::text AS version FROM %I.%I WHERE version::text = %L', n.nspname, c.relname, expected.version),
              true, false, '') END AS matching_version_rows_xml
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attname='version' AND a.attnum>0 AND NOT a.attisdropped
CROSS JOIN (VALUES ('20261103120000','20261103120000_northstar_cross_department_direct_messaging.sql'),
                   ('20261103130000','20261103130000_northstar_companywide_incident_visibility.sql'),
                   ('20261103140000','20261103140000_northstar_department_head_smallint_call.sql'))
  AS expected(version,migration_file)
WHERE c.relkind IN ('r','p')
  AND (n.nspname ILIKE '%migration%' OR c.relname ILIKE '%migration%' OR c.relname='schema_migrations')
ORDER BY n.nspname,c.relname,expected.version;

-- 09c. Explicitly distinguish no recognized ledger from a checked ledger.
SELECT '09c_migration_history_overall_status' AS section,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_catalog.pg_class c
         JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
         JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attname='version' AND a.attnum>0 AND NOT a.attisdropped
         WHERE c.relkind IN ('r','p')
           AND (n.nspname ILIKE '%migration%' OR c.relname ILIKE '%migration%' OR c.relname='schema_migrations')
       ) THEN 'Candidate ledger table(s) found; interpret 09a/09b output, check privileges/RLS, and confirm authoritative mechanism.'
         ELSE 'No recognized migration ledger table with a version column found; this does NOT establish that migrations are pending.' END AS result;

-- End of read-only audit.
