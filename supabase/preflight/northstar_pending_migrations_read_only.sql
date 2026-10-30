-- NorthStar migration preflight (read-only)
-- Run this single script in the Supabase SQL Editor for the intended project.
-- It reads PostgreSQL/Supabase catalogs and bucket metadata only. It does not
-- return employee-level data, reveal function bodies, or modify database state.
-- The JSON report is returned as numbered, bounded-size rows. Copy all rows in
-- chunk-number order and concatenate report_text to reconstruct the JSON.
-- SQL Editor's
-- privileged role sees metadata; this does not simulate client RLS behavior.

BEGIN TRANSACTION READ ONLY;

DO $northstar_read_only_preflight$
DECLARE
  report jsonb;
  expected_columns jsonb;
  all_columns jsonb;
  bucket_report jsonb := '[]'::jsonb;
  data_preflight_report jsonb := '{}'::jsonb;
  report_text text;
  chunk_size integer := 1200;
  chunk_count integer;
  chunk_number integer;
  report_cursor refcursor := 'northstar_preflight_report';
  section_row record;
  target_tables text[] := ARRAY[
    'profiles', 'departments', 'announcements', 'events', 'event_attendees',
    'resources', 'northstar_incidents', 'northstar_incident_updates',
    'northstar_department_discussion_posts'
  ];
  required_columns jsonb := '[
    {"table":"northstar_incidents","column":"id","stage":"base"},
    {"table":"northstar_incidents","column":"title","stage":"base"},
    {"table":"northstar_incidents","column":"description","stage":"base"},
    {"table":"northstar_incidents","column":"category","stage":"base"},
    {"table":"northstar_incidents","column":"severity","stage":"base"},
    {"table":"northstar_incidents","column":"location","stage":"base"},
    {"table":"northstar_incidents","column":"reported_by","stage":"base"},
    {"table":"northstar_incidents","column":"reported_at","stage":"base"},
    {"table":"northstar_incidents","column":"status","stage":"base"},
    {"table":"northstar_incidents","column":"assigned_responder","stage":"base"},
    {"table":"northstar_incidents","column":"resolution_details","stage":"base"},
    {"table":"northstar_incidents","column":"updated_at","stage":"base"},
    {"table":"northstar_incident_updates","column":"id","stage":"base"},
    {"table":"northstar_incident_updates","column":"incident_id","stage":"base"},
    {"table":"northstar_incident_updates","column":"actor_id","stage":"base"},
    {"table":"northstar_incident_updates","column":"event_type","stage":"base"},
    {"table":"northstar_incident_updates","column":"visibility","stage":"base"},
    {"table":"northstar_incident_updates","column":"old_status","stage":"base"},
    {"table":"northstar_incident_updates","column":"new_status","stage":"base"},
    {"table":"northstar_incident_updates","column":"old_severity","stage":"base"},
    {"table":"northstar_incident_updates","column":"new_severity","stage":"base"},
    {"table":"northstar_incident_updates","column":"details","stage":"base"},
    {"table":"northstar_incident_updates","column":"created_at","stage":"base"},
    {"table":"profiles","column":"id","stage":"department"},
    {"table":"profiles","column":"first_name","stage":"department"},
    {"table":"profiles","column":"last_name","stage":"department"},
    {"table":"profiles","column":"department_id","stage":"department"},
    {"table":"profiles","column":"role","stage":"department"},
    {"table":"profiles","column":"approval_status","stage":"department"},
    {"table":"profiles","column":"employment_status","stage":"department"},
    {"table":"profiles","column":"registration_completed","stage":"department"},
    {"table":"profiles","column":"department_level","stage":"added_or_existing_291200"},
    {"table":"departments","column":"id","stage":"department"},
    {"table":"departments","column":"name","stage":"department"},
    {"table":"announcements","column":"id","stage":"department"},
    {"table":"announcements","column":"title","stage":"department"},
    {"table":"announcements","column":"content","stage":"department"},
    {"table":"announcements","column":"author_id","stage":"department"},
    {"table":"announcements","column":"department_id","stage":"department"},
    {"table":"announcements","column":"created_at","stage":"department"},
    {"table":"announcements","column":"is_pinned","stage":"department"},
    {"table":"events","column":"id","stage":"department"},
    {"table":"events","column":"title","stage":"department"},
    {"table":"events","column":"organizer_id","stage":"department"},
    {"table":"events","column":"department_id","stage":"department"},
    {"table":"events","column":"start_time","stage":"department"},
    {"table":"events","column":"created_at","stage":"department"},
    {"table":"event_attendees","column":"event_id","stage":"department"},
    {"table":"event_attendees","column":"user_id","stage":"department"},
    {"table":"event_attendees","column":"attendance_status","stage":"department"},
    {"table":"resources","column":"id","stage":"department"},
    {"table":"resources","column":"title","stage":"department"},
    {"table":"resources","column":"storage_path","stage":"department"},
    {"table":"resources","column":"uploaded_by","stage":"department"},
    {"table":"resources","column":"department_id","stage":"department"},
    {"table":"resources","column":"created_at","stage":"department"},
    {"table":"northstar_incidents","column":"deleted_at","stage":"from_281300"},
    {"table":"northstar_incidents","column":"department_id","stage":"added_by_291200"},
    {"table":"northstar_incident_updates","column":"old_assigned_responder","stage":"department"},
    {"table":"northstar_incident_updates","column":"new_assigned_responder","stage":"department"},
    {"table":"northstar_incident_updates","column":"old_resolution_details","stage":"department"},
    {"table":"northstar_incident_updates","column":"new_resolution_details","stage":"department"},
    {"table":"northstar_department_discussion_posts","column":"id","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"department_id","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"author_id","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"parent_id","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"content","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"created_at","stage":"created_by_291200"},
    {"table":"northstar_department_discussion_posts","column":"updated_at","stage":"created_by_291200"},
    {"schema":"auth","table":"users","column":"id","stage":"authentication_dependency"},
    {"schema":"auth","table":"users","column":"email_confirmed_at","stage":"authentication_dependency"}
  ]'::jsonb;
  local_migration_versions text[] := ARRAY[
    '20261015120000','20261015130000','20261015140000','20261018120000',
    '20261019000000','20261021120000','20261021130000','20261022140000',
    '20261024170000','20261028120000','20261028130000','20261029120000','20261030120000'
  ];
  applied_versions jsonb := NULL;
  migration_history_status text := 'unknown';
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    EXECUTE $query$
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', bucket.id, 'public', bucket.public,
        'file_size_limit', bucket.file_size_limit,
        'allowed_mime_types', bucket.allowed_mime_types
      ) ORDER BY bucket.id), '[]'::jsonb)
      FROM storage.buckets AS bucket
      WHERE bucket.id IN ('northstar-message-attachments', 'company-resources')
    $query$ INTO bucket_report;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'schema', coalesce(expected->>'schema', 'public'),
    'table', expected->>'table',
    'column', expected->>'column',
    'stage', expected->>'stage',
    'present', actual.column_name IS NOT NULL,
    'data_type', actual.data_type,
    'udt_name', actual.udt_name,
    'nullable', actual.is_nullable,
    'default', actual.column_default,
    'identity', actual.is_identity,
    'generated', actual.is_generated
  ) ORDER BY expected->>'stage', expected->>'table', expected->>'column'), '[]'::jsonb)
  INTO expected_columns
  FROM jsonb_array_elements(required_columns) AS item(expected)
  LEFT JOIN information_schema.columns AS actual
    ON actual.table_schema = coalesce(expected->>'schema', 'public')
   AND actual.table_name = expected->>'table'
   AND actual.column_name = expected->>'column';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'schema', column_row.table_schema,
    'table', column_row.table_name,
    'column', column_row.column_name,
    'data_type', column_row.data_type,
    'udt_name', column_row.udt_name,
    'nullable', column_row.is_nullable,
    'default', column_row.column_default,
    'identity', column_row.is_identity,
    'generated', column_row.is_generated
  ) ORDER BY column_row.table_schema, column_row.table_name, column_row.ordinal_position), '[]'::jsonb)
  INTO all_columns
  FROM information_schema.columns AS column_row
  WHERE (column_row.table_schema = 'public' AND column_row.table_name = ANY(target_tables))
     OR (column_row.table_schema = 'auth' AND column_row.table_name = 'users');

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles'
        AND column_name = ANY(ARRAY['department_id','approval_status','employment_status','registration_completed','role'])) = 5 THEN
    EXECUTE $query$
      SELECT jsonb_build_object(
        'active_approved_registered_profiles_without_department', (
          SELECT count(*) FROM public.profiles
          WHERE department_id IS NULL
            AND coalesce(approval_status::text, '') = 'approved'
            AND coalesce(employment_status::text, '') = 'active'
            AND registration_completed IS TRUE
        )
      )
    $query$ INTO data_preflight_report;
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles'
        AND column_name = ANY(ARRAY['department_id','approval_status','employment_status','registration_completed','role','department_level'])) = 6
     AND (SELECT data_type = 'smallint' FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'department_level') THEN
    EXECUTE $query$
      SELECT $1 || jsonb_build_object(
        'duplicate_eligible_department_head_groups', (
          SELECT count(*) FROM (
            SELECT department_id FROM public.profiles
            WHERE department_id IS NOT NULL AND department_level = 1
              AND role::text IN ('employee','manager')
              AND approval_status::text = 'approved'
              AND employment_status::text = 'active'
              AND registration_completed IS TRUE
            GROUP BY department_id HAVING count(*) > 1
          ) AS duplicate_groups
        ),
        'extra_eligible_department_head_profiles', (
          SELECT coalesce(sum(head_count - 1), 0) FROM (
            SELECT count(*) AS head_count FROM public.profiles
            WHERE department_id IS NOT NULL AND department_level = 1
              AND role::text IN ('employee','manager')
              AND approval_status::text = 'approved'
              AND employment_status::text = 'active'
              AND registration_completed IS TRUE
            GROUP BY department_id HAVING count(*) > 1
          ) AS duplicate_groups
        ),
        'existing_department_level_values_out_of_range',
        (SELECT count(*) FROM public.profiles WHERE department_level IS NOT NULL AND department_level NOT BETWEEN 1 AND 5)
      )
    $query$ INTO data_preflight_report USING data_preflight_report;
  END IF;

  IF to_regclass('supabase_migrations.schema_migrations') IS NOT NULL THEN
    BEGIN
      EXECUTE $query$
        SELECT coalesce(jsonb_agg(version::text ORDER BY version::text), '[]'::jsonb)
        FROM supabase_migrations.schema_migrations
      $query$ INTO applied_versions;
      migration_history_status := 'readable';
    EXCEPTION WHEN OTHERS THEN
      migration_history_status := 'exists_but_unreadable: ' || SQLSTATE;
      applied_versions := NULL;
    END;
  ELSE
    migration_history_status := 'table_not_found';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', statement_timestamp(),
    'read_only', true,
    'connection_role', current_user,
    'migration_order', jsonb_build_array(
      '20261028130000_northstar_incident_reporter_actions_and_shared_history.sql',
      '20261029120000_northstar_department_hierarchy_and_collaboration.sql',
      '20261030120000_northstar_department_head_management.sql'
    ),
    'required_columns', expected_columns,
    'all_actual_columns', all_columns,
    'relations', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname,
        'table', c.relname,
        'exists', c.oid IS NOT NULL,
        'rls_enabled', c.relrowsecurity,
        'force_rls', c.relforcerowsecurity
      ) ORDER BY n.nspname, c.relname), '[]'::jsonb)
      FROM (
        SELECT 'public'::text AS schema_name, unnest(target_tables) AS table_name
        UNION ALL SELECT 'auth', 'users'
        UNION ALL SELECT 'storage', 'buckets'
        UNION ALL SELECT 'storage', 'objects'
      ) AS wanted
      LEFT JOIN pg_namespace AS n ON n.nspname = wanted.schema_name
      LEFT JOIN pg_class AS c ON c.relnamespace = n.oid AND c.relname = wanted.table_name
    ),
    'constraints', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'table', relation.relname,
        'name', con.conname,
        'type', CASE con.contype WHEN 'p' THEN 'primary_key' WHEN 'f' THEN 'foreign_key'
          WHEN 'u' THEN 'unique' WHEN 'c' THEN 'check' ELSE con.contype::text END,
        'definition', pg_get_constraintdef(con.oid, true),
        'validated', con.convalidated,
        'deferrable', con.condeferrable,
        'initially_deferred', con.condeferred
      ) ORDER BY relation.relname, con.conname), '[]'::jsonb)
      FROM pg_constraint AS con
      JOIN pg_class AS relation ON relation.oid = con.conrelid
      JOIN pg_namespace AS n ON n.oid = relation.relnamespace
      WHERE n.nspname = 'public' AND relation.relname = ANY(target_tables)
    ),
    'triggers', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname, 'table', relation.relname,
        'name', trigger_row.tgname,
        'enabled_state', trigger_row.tgenabled,
        'definition', pg_get_triggerdef(trigger_row.oid, true)
      ) ORDER BY n.nspname, relation.relname, trigger_row.tgname), '[]'::jsonb)
      FROM pg_trigger AS trigger_row
      JOIN pg_class AS relation ON relation.oid = trigger_row.tgrelid
      JOIN pg_namespace AS n ON n.oid = relation.relnamespace
      WHERE NOT trigger_row.tgisinternal
        AND ((n.nspname = 'public' AND relation.relname = ANY(target_tables))
          OR (n.nspname = 'storage' AND relation.relname = 'objects'))
    ),
    'indexes', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'table', relation.relname, 'index', index_relation.relname,
        'unique', index_row.indisunique,
        'primary', index_row.indisprimary,
        'valid', index_row.indisvalid,
        'definition', pg_get_indexdef(index_row.indexrelid)
      ) ORDER BY relation.relname, index_relation.relname), '[]'::jsonb)
      FROM pg_index AS index_row
      JOIN pg_class AS relation ON relation.oid = index_row.indrelid
      JOIN pg_class AS index_relation ON index_relation.oid = index_row.indexrelid
      JOIN pg_namespace AS n ON n.oid = relation.relnamespace
      WHERE n.nspname = 'public' AND relation.relname = ANY(target_tables)
    ),
    'policies', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', policy.schemaname, 'table', policy.tablename,
        'name', policy.policyname, 'permissive', policy.permissive,
        'roles', policy.roles, 'command', policy.cmd,
        'using', policy.qual, 'with_check', policy.with_check
      ) ORDER BY policy.schemaname, policy.tablename, policy.policyname), '[]'::jsonb)
      FROM pg_policies AS policy
      WHERE (policy.schemaname = 'public' AND policy.tablename = ANY(target_tables))
         OR (policy.schemaname = 'storage' AND policy.tablename = 'objects')
    ),
    'table_grants', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname, 'table', relation.relname,
        'owner', pg_get_userbyid(relation.relowner),
        'direct_acl', relation.relacl::text,
        'acl_uses_default', relation.relacl IS NULL,
        'effective_anon_select', has_table_privilege('anon', relation.oid, 'SELECT'),
        'effective_authenticated_select', has_table_privilege('authenticated', relation.oid, 'SELECT'),
        'effective_authenticated_insert', has_table_privilege('authenticated', relation.oid, 'INSERT'),
        'effective_authenticated_update', has_table_privilege('authenticated', relation.oid, 'UPDATE'),
        'effective_authenticated_delete', has_table_privilege('authenticated', relation.oid, 'DELETE'),
        'effective_service_role_select', has_table_privilege('service_role', relation.oid, 'SELECT')
      ) ORDER BY n.nspname, relation.relname), '[]'::jsonb)
      FROM pg_class AS relation
      JOIN pg_namespace AS n ON n.oid = relation.relnamespace
      WHERE (n.nspname = 'public' AND relation.relname = ANY(target_tables))
         OR (n.nspname = 'storage' AND relation.relname = 'objects')
    ),
    'column_grants', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname,
        'table', relation.relname,
        'column', attribute.attname,
        'direct_acl', attribute.attacl::text,
        'effective_authenticated_select', has_column_privilege('authenticated', relation.oid, attribute.attnum, 'SELECT'),
        'effective_authenticated_insert', has_column_privilege('authenticated', relation.oid, attribute.attnum, 'INSERT'),
        'effective_authenticated_update', has_column_privilege('authenticated', relation.oid, attribute.attnum, 'UPDATE'),
        'effective_authenticated_references', has_column_privilege('authenticated', relation.oid, attribute.attnum, 'REFERENCES')
      ) ORDER BY n.nspname, relation.relname, attribute.attnum), '[]'::jsonb)
      FROM pg_attribute AS attribute
      JOIN pg_class AS relation ON relation.oid = attribute.attrelid
      JOIN pg_namespace AS n ON n.oid = relation.relnamespace
      WHERE attribute.attnum > 0 AND NOT attribute.attisdropped
        AND n.nspname = 'public' AND relation.relname = ANY(target_tables)
    ),
    'owned_sequence_grants', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'table', table_row.relname,
        'sequence', sequence_row.relname,
        'sequence_owner', pg_get_userbyid(sequence_row.relowner),
        'direct_acl', sequence_row.relacl::text,
        'acl_uses_default', sequence_row.relacl IS NULL,
        'effective_anon_usage', has_sequence_privilege('anon', sequence_row.oid, 'USAGE'),
        'effective_authenticated_usage', has_sequence_privilege('authenticated', sequence_row.oid, 'USAGE'),
        'effective_authenticated_select', has_sequence_privilege('authenticated', sequence_row.oid, 'SELECT'),
        'effective_authenticated_update', has_sequence_privilege('authenticated', sequence_row.oid, 'UPDATE'),
        'effective_service_role_usage', has_sequence_privilege('service_role', sequence_row.oid, 'USAGE')
      ) ORDER BY table_row.relname, sequence_row.relname), '[]'::jsonb)
      FROM pg_depend AS dependency
      JOIN pg_class AS sequence_row ON sequence_row.oid = dependency.objid AND sequence_row.relkind = 'S'
      JOIN pg_class AS table_row ON table_row.oid = dependency.refobjid
      JOIN pg_namespace AS table_namespace ON table_namespace.oid = table_row.relnamespace
      WHERE dependency.classid = 'pg_class'::regclass
        AND dependency.refclassid = 'pg_class'::regclass
        AND dependency.deptype IN ('a', 'i')
        AND table_namespace.nspname = 'public'
        AND table_row.relname = ANY(target_tables)
    ),
    'schema_grants', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', schema_row.nspname,
        'owner', pg_get_userbyid(schema_row.nspowner),
        'direct_acl', schema_row.nspacl::text,
        'acl_uses_default', schema_row.nspacl IS NULL,
        'effective_authenticated_usage', has_schema_privilege('authenticated', schema_row.oid, 'USAGE'),
        'effective_authenticated_create', has_schema_privilege('authenticated', schema_row.oid, 'CREATE')
      ) ORDER BY schema_row.nspname), '[]'::jsonb)
      FROM pg_namespace AS schema_row
      WHERE schema_row.nspname IN ('public', 'northstar_private', 'storage')
    ),
    'functions', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname,
        'identity', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
        'returns', pg_get_function_result(p.oid),
        'language', language_row.lanname,
        'owner', pg_get_userbyid(p.proowner),
        'security_definer', p.prosecdef,
        'settings', p.proconfig,
        'effective_execute_anon', has_function_privilege('anon', p.oid, 'EXECUTE'),
        'effective_execute_authenticated', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
        'effective_execute_service_role', has_function_privilege('service_role', p.oid, 'EXECUTE'),
        'effective_execute_connection_role', has_function_privilege(current_user, p.oid, 'EXECUTE'),
        'direct_acl', p.proacl::text,
        'acl_uses_default', p.proacl IS NULL,
        'definition_md5', md5(p.prosrc),
        'comment', obj_description(p.oid, 'pg_proc')
      ) ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), '[]'::jsonb)
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
      JOIN pg_language AS language_row ON language_row.oid = p.prolang
      WHERE n.nspname IN ('public', 'northstar_private')
        AND p.proname = ANY(ARRAY[
          'northstar_is_designated_admin', 'northstar_list_company_incidents',
          'northstar_report_incident', 'northstar_admin_update_incident',
          'northstar_reporter_update_incident_status', 'northstar_presence_heartbeat',
          'northstar_list_active_company_incidents', 'northstar_list_company_incident_history',
          'northstar_reporter_edit_incident', 'northstar_reporter_soft_delete_incident',
          'northstar_admin_list_department_assignments', 'northstar_admin_assign_department_level',
          'northstar_admin_list_department_management', 'northstar_admin_set_department_head',
          'northstar_admin_approve_employee_with_department_level',
          'northstar_admin_update_employee_registration_status',
          'northstar_department_head_update_incident', 'northstar_department_report_incident',
          'northstar_department_list_incidents', 'northstar_department_list_incident_history',
          'is_eligible_department_member', 'is_eligible_workspace_user', 'is_department_head',
          'is_department_member_or_admin', 'resource_object_allowed', 'protect_department_assignment',
          'guard_department_discussion_post', 'protect_department_content_provenance',
          'set_incident_department'
        ])
    ),
    'required_preexisting_functions', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'signature', required.signature,
        'purpose', required.purpose,
        'present', procedure_row.oid IS NOT NULL,
        'actual_return_type', pg_get_function_result(procedure_row.oid),
        'expected_return_type', required.expected_return,
        'return_type_matches', CASE WHEN procedure_row.oid IS NULL OR required.expected_return IS NULL THEN NULL
          ELSE regexp_replace(lower(pg_get_function_result(procedure_row.oid)), '[[:space:]]', '', 'g')
             = regexp_replace(lower(required.expected_return), '[[:space:]]', '', 'g') END,
        'actual_security_definer', procedure_row.prosecdef,
        'actual_settings', procedure_row.proconfig,
        'execute_as_connection_role', CASE WHEN procedure_row.oid IS NULL THEN NULL
          ELSE has_function_privilege(current_user, procedure_row.oid, 'EXECUTE') END
      ) ORDER BY required.signature), '[]'::jsonb)
      FROM (VALUES
        ('public.northstar_list_company_incidents()', 'Existing incident list called by 20261028130000',
          'TABLE(id uuid, title text, description text, category text, severity text, location text, reporter_name text, reported_at timestamp with time zone, status text, assigned_responder_name text, resolution_details text, is_reporter boolean)'),
        ('public.northstar_is_designated_admin()', 'Authorization helper required by both migrations', 'boolean'),
        ('public.northstar_report_incident(text,text,text,text,text)', 'Existing report RPC wrapped by 20261029120000', 'uuid'),
        ('public.northstar_admin_assign_department_level(uuid,uuid,smallint)', 'Assignment RPC required by 20261030120000', 'void'),
        ('public.northstar_admin_update_employee_registration_status(uuid,text,text,text[])', 'Approval RPC required by 20261030120000', 'void')
      ) AS required(signature, purpose, expected_return)
      LEFT JOIN pg_proc AS procedure_row ON procedure_row.oid = to_regprocedure(required.signature)
    ),
    'storage_buckets', bucket_report,
    'department_head_index_prerequisite', (
      SELECT jsonb_build_object(
        'name', 'northstar_one_active_department_head_uidx',
        'present', index_relation.oid IS NOT NULL,
        'unique', index_row.indisunique,
        'valid', index_row.indisvalid,
        'definition', CASE WHEN index_relation.oid IS NULL THEN NULL ELSE pg_get_indexdef(index_relation.oid) END
      )
      FROM (SELECT to_regclass('public.northstar_one_active_department_head_uidx') AS index_oid) AS found_index
      LEFT JOIN pg_class AS index_relation ON index_relation.oid = found_index.index_oid
      LEFT JOIN pg_index AS index_row ON index_row.indexrelid = index_relation.oid
    ),
    'aggregate_data_checks', data_preflight_report,
    'reporter_update_check_constraint_present', EXISTS (
      SELECT 1 FROM pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = to_regclass('public.northstar_incident_updates')
        AND constraint_row.contype = 'c'
        AND pg_get_constraintdef(constraint_row.oid) ILIKE '%event_type%'
        AND pg_get_constraintdef(constraint_row.oid) ILIKE '%reporter_update%'
    ),
    'preexisting_restrictive_policy_conflicts', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', policy.schemaname, 'table', policy.tablename,
        'name', policy.policyname, 'roles', policy.roles, 'command', policy.cmd,
        'using', policy.qual, 'with_check', policy.with_check
      ) ORDER BY policy.schemaname, policy.tablename, policy.policyname), '[]'::jsonb)
      FROM pg_policies AS policy
      WHERE policy.schemaname = 'public'
        AND policy.tablename = ANY(ARRAY[
          'announcements','events','resources','event_attendees',
          'northstar_incidents','northstar_incident_updates'
        ])
        AND policy.permissive = 'RESTRICTIVE'
        AND (policy.roles @> ARRAY['public']::name[] OR policy.roles @> ARRAY['authenticated']::name[])
    ),
    'policy_name_collisions', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'schema', policy.schemaname, 'table', policy.tablename,
        'name', policy.policyname, 'permissive', policy.permissive,
        'roles', policy.roles, 'command', policy.cmd
      ) ORDER BY policy.schemaname, policy.tablename, policy.policyname), '[]'::jsonb)
      FROM pg_policies AS policy
      WHERE (policy.schemaname = 'public' AND policy.policyname = ANY(ARRAY[
        'northstar_department_announcements_guard', 'northstar_department_announcements_select',
        'northstar_department_announcements_insert_guard', 'northstar_department_announcements_insert_policy',
        'northstar_department_announcements_update_policy', 'northstar_department_announcements_delete_policy',
        'northstar_department_announcements_delete_guard', 'northstar_department_announcements_update_guard',
        'northstar_department_events_guard', 'northstar_department_events_select_policy',
        'northstar_department_events_insert_policy', 'northstar_department_events_update_policy',
        'northstar_department_events_delete_policy', 'northstar_department_events_insert_guard',
        'northstar_department_events_update_guard', 'northstar_department_events_delete_guard',
        'northstar_department_event_attendees_select', 'northstar_department_event_attendees_insert',
        'northstar_department_event_attendees_update', 'northstar_department_event_attendees_delete',
        'northstar_department_event_attendees_guard', 'northstar_department_resources_guard',
        'northstar_department_resources_select_policy', 'northstar_department_resources_insert_policy',
        'northstar_department_resources_update_policy', 'northstar_department_resources_delete_policy',
        'northstar_department_resources_insert_guard', 'northstar_department_resources_update_guard',
        'northstar_department_resources_delete_guard', 'northstar_incidents_department_guard',
        'northstar_incident_updates_department_guard'
      ]))
    ),
    'migration_history', jsonb_build_object(
      'status', migration_history_status,
      'all_applied_versions', applied_versions,
      'checked_in_local_versions_present', CASE WHEN applied_versions IS NULL THEN NULL ELSE (
        SELECT coalesce(jsonb_agg(local_version ORDER BY local_version), '[]'::jsonb)
        FROM unnest(local_migration_versions) AS versions(local_version)
        WHERE applied_versions ? local_version
      ) END,
      'prior_local_versions_not_recorded', CASE WHEN applied_versions IS NULL THEN NULL ELSE (
        SELECT coalesce(jsonb_agg(local_version ORDER BY local_version), '[]'::jsonb)
        FROM unnest(local_migration_versions) AS versions(local_version)
        WHERE local_version < '20261030120000'
          AND NOT (applied_versions ? local_version)
      ) END,
      'targets', CASE WHEN applied_versions IS NULL THEN NULL ELSE jsonb_build_object(
        '20261028130000', CASE WHEN applied_versions ? '20261028130000' THEN 'applied' ELSE 'not_recorded' END,
        '20261029120000', CASE WHEN applied_versions ? '20261029120000' THEN 'applied' ELSE 'not_recorded' END,
        '20261030120000', CASE WHEN applied_versions ? '20261030120000' THEN 'applied' ELSE 'not_recorded' END,
        '20261028120000_prerequisite', CASE WHEN applied_versions ? '20261028120000' THEN 'applied' ELSE 'not_recorded' END
      ) END,
      'note', 'Only local migration versions listed in this preflight are compared; compare the complete ledger with the checked-in supabase/migrations filenames before any production migration run.'
    )
  ) INTO report;

  report_text := report::text;
  chunk_count := greatest(1, ceil(length(report_text)::numeric / chunk_size)::integer);
  OPEN report_cursor FOR
    SELECT series.chunk_number AS chunk_number,
           chunk_count AS total_chunks,
           substr(report_text, ((series.chunk_number - 1) * chunk_size) + 1, chunk_size) AS report_text
    FROM generate_series(1, chunk_count) AS series(chunk_number)
    ORDER BY series.chunk_number;
END;
$northstar_read_only_preflight$;

FETCH ALL FROM northstar_preflight_report;

COMMIT;
