-- NorthStar live backend audit. This file contains one read-only SELECT.
-- Run only after confirming the SQL Editor is connected to the NorthStar project.
-- It returns catalog metadata and routine definitions, never employee rows.

WITH
expected_routines(label, signature, schema_name, routine_name) AS (
  VALUES
    ('department_head_set', 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'public', 'northstar_admin_set_department_head'),
    ('department_level_assign', 'public.northstar_admin_assign_department_level(uuid,uuid,smallint)', 'public', 'northstar_admin_assign_department_level'),
    ('direct_conversation_create', 'public.northstar_create_direct_conversation(uuid[])', 'public', 'northstar_create_direct_conversation'),
    ('department_incident_list', 'public.northstar_department_list_incidents()', 'public', 'northstar_department_list_incidents'),
    ('department_incident_history', 'public.northstar_department_list_incident_history(uuid[])', 'public', 'northstar_department_list_incident_history'),
    ('role_helper', 'public.has_any_role(text[])', 'public', 'has_any_role'),
    ('workspace_eligibility_helper', 'northstar_private.is_eligible_workspace_user()', 'northstar_private', 'is_eligible_workspace_user'),
    ('department_eligibility_helper', 'northstar_private.is_eligible_department_member(uuid)', 'northstar_private', 'is_eligible_department_member'),
    ('department_head_helper', 'northstar_private.is_department_head(uuid)', 'northstar_private', 'is_department_head'),
    ('designated_admin_helper', 'public.northstar_is_designated_admin()', 'public', 'northstar_is_designated_admin')
),
resolved_routines AS (
  SELECT expected.*, pg_catalog.to_regprocedure(expected.signature) AS routine_oid
  FROM expected_routines AS expected
),
routine_report AS (
  SELECT
    resolved.label,
    resolved.signature,
    (procedure_row.oid IS NOT NULL) AS object_exists,
    CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_userbyid(procedure_row.proowner) END AS owner,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS configuration,
    CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_result(procedure_row.oid) END AS result_type,
    CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) END AS identity_arguments,
    CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(procedure_row.oid) END AS full_definition,
    CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE procedure_row.prosrc END AS source_body,
    grants.direct_execute_grants,
    grants.effective_role_permissions,
    dependencies.catalog_dependencies
  FROM resolved_routines AS resolved
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid = resolved.routine_oid
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN privilege.grantee = 0 THEN 'PUBLIC' ELSE role_row.rolname END,
            'privilege', privilege.privilege_type,
            'grantable', privilege.is_grantable,
            'grantor', grantor_row.rolname
          ) ORDER BY CASE WHEN privilege.grantee = 0 THEN '' ELSE role_row.rolname END, privilege.privilege_type
        ), '[]'::jsonb
      ) AS direct_execute_grants,
      (
        SELECT COALESCE(
          pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'role', requested.role_name,
              'role_exists', requested.role_name = 'PUBLIC' OR role_check.oid IS NOT NULL,
              'effective_execute', CASE
                WHEN procedure_row.oid IS NULL THEN NULL
                WHEN requested.role_name = 'PUBLIC' THEN EXISTS (
                  SELECT 1 FROM pg_catalog.aclexplode(
                    COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
                  ) AS public_acl
                  WHERE public_acl.grantee = 0 AND public_acl.privilege_type = 'EXECUTE'
                )
                WHEN role_check.oid IS NULL THEN NULL
                ELSE pg_catalog.has_function_privilege(role_check.oid, procedure_row.oid, 'EXECUTE')
              END
            ) ORDER BY requested.role_name
          ), '[]'::jsonb
        )
        FROM (VALUES ('PUBLIC'), ('anon'), ('authenticated'), ('service_role')) AS requested(role_name)
        LEFT JOIN pg_catalog.pg_roles AS role_check ON role_check.rolname = requested.role_name
      ) AS effective_role_permissions
    FROM pg_catalog.aclexplode(
      COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
    ) AS privilege
    LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.oid = privilege.grantee
    LEFT JOIN pg_catalog.pg_roles AS grantor_row ON grantor_row.oid = privilege.grantor
    WHERE procedure_row.oid IS NOT NULL
      AND privilege.privilege_type = 'EXECUTE'
  ) AS grants ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'referenced_object', pg_catalog.pg_describe_object(dependency.refclassid, dependency.refobjid, dependency.refobjsubid),
          'dependency_type', dependency.deptype
        ) ORDER BY pg_catalog.pg_describe_object(dependency.refclassid, dependency.refobjid, dependency.refobjsubid)
      ), '[]'::jsonb
    ) AS catalog_dependencies
    FROM pg_catalog.pg_depend AS dependency
    WHERE procedure_row.oid IS NOT NULL
      AND dependency.classid = 'pg_catalog.pg_proc'::regclass
      AND dependency.objid = procedure_row.oid
      AND dependency.refclassid IN ('pg_catalog.pg_class'::regclass, 'pg_catalog.pg_proc'::regclass)
  ) AS dependencies ON true
),
roles AS (
  SELECT role_name, role_name = 'PUBLIC' OR role_oid IS NOT NULL AS role_exists
  FROM (VALUES
    ('PUBLIC', NULL::oid),
    ('anon', pg_catalog.to_regrole('anon')::oid),
    ('authenticated', pg_catalog.to_regrole('authenticated')::oid),
    ('service_role', pg_catalog.to_regrole('service_role')::oid)
  ) AS requested(role_name, role_oid)
),
target_tables(schema_name, table_name) AS (
  VALUES
    ('public', 'profiles'),
    ('auth', 'users'),
    ('public', 'departments'),
    ('public', 'conversations'),
    ('public', 'conversation_members'),
    ('public', 'northstar_incidents'),
    ('public', 'northstar_incident_updates')
),
table_columns AS (
  SELECT
    table_ref.schema_name,
    table_ref.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'column', attribute.attname,
          'type', pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
          'nullable', NOT attribute.attnotnull,
          'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid)
        ) ORDER BY attribute.attnum
      ) FILTER (WHERE attribute.attnum IS NOT NULL), '[]'::jsonb
    ) AS columns
  FROM target_tables AS table_ref
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.nspname = table_ref.schema_name
  LEFT JOIN pg_catalog.pg_class AS relation ON relation.relnamespace = namespace_row.oid AND relation.relname = table_ref.table_name
  LEFT JOIN pg_catalog.pg_attribute AS attribute ON attribute.attrelid = relation.oid AND attribute.attnum > 0 AND NOT attribute.attisdropped
  LEFT JOIN pg_catalog.pg_attrdef AS default_row ON default_row.adrelid = relation.oid AND default_row.adnum = attribute.attnum
  GROUP BY table_ref.schema_name, table_ref.table_name
),
table_constraints AS (
  SELECT
    table_ref.schema_name,
    table_ref.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', constraint_row.conname,
          'type', CASE constraint_row.contype
            WHEN 'p' THEN 'primary_key' WHEN 'f' THEN 'foreign_key' WHEN 'u' THEN 'unique'
            WHEN 'c' THEN 'check' WHEN 'x' THEN 'exclusion' ELSE constraint_row.contype::text END,
          'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true),
          'validated', constraint_row.convalidated
        ) ORDER BY constraint_row.conname
      ) FILTER (WHERE constraint_row.oid IS NOT NULL), '[]'::jsonb
    ) AS constraints
  FROM target_tables AS table_ref
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.nspname = table_ref.schema_name
  LEFT JOIN pg_catalog.pg_class AS relation ON relation.relnamespace = namespace_row.oid AND relation.relname = table_ref.table_name
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row ON constraint_row.conrelid = relation.oid
  GROUP BY table_ref.schema_name, table_ref.table_name
),
table_indexes AS (
  SELECT
    table_ref.schema_name,
    table_ref.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', index_relation.relname,
          'unique', index_row.indisunique,
          'primary', index_row.indisprimary,
          'valid', index_row.indisvalid,
          'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid)
        ) ORDER BY index_relation.relname
      ) FILTER (WHERE index_row.indexrelid IS NOT NULL), '[]'::jsonb
    ) AS indexes
  FROM target_tables AS table_ref
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.nspname = table_ref.schema_name
  LEFT JOIN pg_catalog.pg_class AS relation ON relation.relnamespace = namespace_row.oid AND relation.relname = table_ref.table_name
  LEFT JOIN pg_catalog.pg_index AS index_row ON index_row.indrelid = relation.oid
  LEFT JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid = index_row.indexrelid
  GROUP BY table_ref.schema_name, table_ref.table_name
),
table_security AS (
  SELECT
    table_ref.schema_name,
    table_ref.table_name,
    relation.oid IS NOT NULL AS object_exists,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS rls_forced,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', policy.polname,
          'permissive', policy.polpermissive,
          'command_code', policy.polcmd,
          'roles', ARRAY(
            SELECT CASE WHEN policy_role.role_oid = 0 THEN 'PUBLIC' ELSE role_row.rolname END
            FROM unnest(policy.polroles) AS policy_role(role_oid)
            LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.oid = policy_role.role_oid
          ),
          'using', pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
          'check', pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
        ) ORDER BY policy.polname
      ) FILTER (WHERE policy.oid IS NOT NULL), '[]'::jsonb
    ) AS policies
  FROM target_tables AS table_ref
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.nspname = table_ref.schema_name
  LEFT JOIN pg_catalog.pg_class AS relation ON relation.relnamespace = namespace_row.oid AND relation.relname = table_ref.table_name
  LEFT JOIN pg_catalog.pg_policy AS policy ON policy.polrelid = relation.oid
  GROUP BY table_ref.schema_name, table_ref.table_name, relation.oid, relation.relrowsecurity, relation.relforcerowsecurity
),
incident_visibility AS (
  SELECT pg_catalog.jsonb_build_object(
    'companywide_incident_branch_present', COALESCE(bool_or(
      policy.polrelid = pg_catalog.to_regclass('public.northstar_incidents')
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%department_id IS NULL%is_eligible_workspace_user%'
    ), false),
    'companywide_update_branch_present', COALESCE(bool_or(
      policy.polrelid = pg_catalog.to_regclass('public.northstar_incident_updates')
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%i.department_id IS NULL%northstar_private.is_eligible_workspace_user%'
    ), false),
    'admin_update_exclusion_present', COALESCE(bool_or(
      policy.polrelid = pg_catalog.to_regclass('public.northstar_incident_updates')
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%admin_update%'
    ), false),
    'response_team_guard_present', COALESCE(bool_or(
      policy.polrelid = pg_catalog.to_regclass('public.northstar_incident_updates')
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ILIKE '%response_team%assigned_responder%'
    ), false)
  ) AS report
  FROM pg_catalog.pg_policy AS policy
  WHERE policy.polrelid IN (
    pg_catalog.to_regclass('public.northstar_incidents'),
    pg_catalog.to_regclass('public.northstar_incident_updates')
  )
),
migration_ledger AS (
  SELECT CASE
    WHEN pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NULL
      THEN pg_catalog.jsonb_build_object('status', 'not_available', 'reason', 'Ledger table not found')
    WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations' AND column_name = 'version'
    ) THEN pg_catalog.jsonb_build_object('status', 'unrecognized', 'reason', 'Ledger table has no version column')
    ELSE (
      SELECT pg_catalog.jsonb_build_object(
        'status', 'available',
        'versions', COALESCE(
          (
            SELECT pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object('version', ledger_rows.version, 'applied', ledger_rows.applied)
              ORDER BY ledger_rows.version
            )
            FROM XMLTABLE(
              '/table/row'
              PASSING pg_catalog.query_to_xml(
                'SELECT expected.version, EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations AS migration WHERE migration.version::text = expected.version) AS applied FROM (VALUES (''20261103120000''), (''20261103130000''), (''20261103140000'')) AS expected(version) ORDER BY expected.version',
                true, false, ''
              )
              COLUMNS version text PATH 'version', applied boolean PATH 'applied'
            ) AS ledger_rows
          ), '[]'::jsonb
        )
      )
    )
  END AS report
)
SELECT pg_catalog.jsonb_pretty(pg_catalog.jsonb_build_object(
  'audit', 'NorthStar live backend catalog audit',
  'read_only', true,
  'routines', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(routine_report) ORDER BY routine_report.label) FROM routine_report),
  'role_existence', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(roles) ORDER BY roles.role_name) FROM roles),
  'tables', (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'schema', security.schema_name,
        'table', security.table_name,
        'exists', security.object_exists,
        'rls_enabled', security.rls_enabled,
        'rls_forced', security.rls_forced,
        'columns', columns_row.columns,
        'constraints', constraints_row.constraints,
        'indexes', indexes_row.indexes,
        'policies', security.policies
      ) ORDER BY security.schema_name, security.table_name
    )
    FROM table_security AS security
    JOIN table_columns AS columns_row USING (schema_name, table_name)
    JOIN table_constraints AS constraints_row USING (schema_name, table_name)
    JOIN table_indexes AS indexes_row USING (schema_name, table_name)
  ),
  'department_head_check', (
    SELECT pg_catalog.jsonb_build_object(
      'setter_exists', setter.object_exists,
      'assignment_rpc_exists', assignment.object_exists,
      'bare_integer_literal_call_present', COALESCE(setter.source_body ~ 'northstar_admin_assign_department_level\s*\(\s*p_user_id\s*,\s*p_department_id\s*,\s*1\s*\)', false),
      'explicit_smallint_cast_call_present', COALESCE(setter.source_body ~ 'northstar_admin_assign_department_level\s*\(\s*p_user_id\s*,\s*p_department_id\s*,\s*1\s*::\s*smallint\s*\)', false)
    )
    FROM routine_report AS setter CROSS JOIN routine_report AS assignment
    WHERE setter.label = 'department_head_set' AND assignment.label = 'department_level_assign'
  ),
  'direct_messaging_check', (
    SELECT pg_catalog.jsonb_build_object(
      'function_exists', messaging.object_exists,
      'actor_department_reference_present', COALESCE(messaging.source_body ILIKE '%actor_department%', false),
      'peer_department_reference_present', COALESCE(messaging.source_body ILIKE '%peer_department%', false),
      'actor_department_assignment_required', COALESCE(messaging.source_body ILIKE '%actor_department_id IS NULL%', false),
      'peer_department_assignment_required', COALESCE(messaging.source_body ILIKE '%peer_department_id IS NULL%', false),
      'same_department_comparison_present', COALESCE(messaging.source_body ILIKE '%IS DISTINCT FROM actor_department%', false),
      'advisory_lock_present', COALESCE(messaging.source_body ILIKE '%pg_advisory_xact_lock%', false),
      'self_conversation_guard_present', COALESCE(messaging.source_body ILIKE '%peer_id = actor_id%', false),
      'exact_two_member_reuse_present', COALESCE(
        messaging.source_body ILIKE '%array_agg%' AND messaging.source_body ILIKE '%count(*) = 2%', false),
      'eligibility_fragments_present', COALESCE(
        messaging.source_body ILIKE '%email_confirmed_at IS NOT NULL%'
        AND messaging.source_body ILIKE '%registration_completed IS TRUE%'
        AND messaging.source_body ILIKE '%approval_status::text = ''approved''%'
        AND messaging.source_body ILIKE '%employment_status::text = ''active''%'
        AND messaging.source_body ILIKE '%role::text IN (''employee'', ''manager'')%', false)
    )
    FROM routine_report AS messaging WHERE messaging.label = 'direct_conversation_create'
  ),
  'incident_visibility_checks', (SELECT report FROM incident_visibility),
  'migration_ledger', (SELECT report FROM migration_ledger),
  'dependency_note', 'Catalog dependency records can omit relations referenced only inside PL/pgSQL source; full routine definitions and object-presence reports are included for manual comparison.'
)) AS northstar_live_backend_audit;
