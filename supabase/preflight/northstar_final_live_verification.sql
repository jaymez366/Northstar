-- NorthStar consolidated live verification.
-- READ ONLY: every executable statement is a SELECT over PostgreSQL catalogs
-- or Supabase metadata. No application rows or environment/secret tables are
-- queried. Run only after confirming the SQL Editor is connected to NorthStar.
-- Function source is returned for the named application routines so reviewers
-- can inspect authorization checks. Review results in the trusted SQL Editor;
-- do not paste raw results into tickets or logs without checking for literals.

-- 00. Query context. Compare the project identity separately in the dashboard.
SELECT current_database() AS database_name,
       current_user AS current_role,
       session_user AS session_role,
       current_setting('role', true) AS active_role;

-- 01. Migration-history discovery and expected local migration versions.
-- This discovers catalog relations/columns that could be migration ledgers.
-- Static SELECT cannot safely read rows from an unknown relation name. Once
-- the authoritative relation is identified, its version column needs a direct
-- SELECT using that verified identifier. A missing catalog candidate does not
-- prove that repository migrations are pending.
WITH expected(version, migration_file) AS (
  SELECT '20261015120000', '20261015120000_northstar_registration_support.sql'
  UNION ALL SELECT '20261015130000', '20261015130000_northstar_registration_photo_choice.sql'
  UNION ALL SELECT '20261015140000', '20261015140000_northstar_notifications_push.sql'
  UNION ALL SELECT '20261018120000', '20261018120000_northstar_registration_photo_self_read.sql'
  UNION ALL SELECT '20261019000000', '20261019000000_northstar_disaster_management.sql'
  UNION ALL SELECT '20261021120000', '20261021120000_northstar_registration_corrections.sql'
  UNION ALL SELECT '20261021130000', '20261021130000_northstar_admin_rejection_snapshot_read.sql'
  UNION ALL SELECT '20261022140000', '20261022140000_northstar_admin_rejection_history_rpc_name.sql'
  UNION ALL SELECT '20261024170000', '20261024170000_northstar_message_interactions.sql'
  UNION ALL SELECT '20261028120000', '20261028120000_northstar_cross_department_presence.sql'
  UNION ALL SELECT '20261028130000', '20261028130000_northstar_incident_reporter_actions_and_shared_history.sql'
  UNION ALL SELECT '20261029120000', '20261029120000_northstar_department_hierarchy_and_collaboration.sql'
  UNION ALL SELECT '20261030120000', '20261030120000_northstar_department_head_management.sql'
  UNION ALL SELECT '20261031120000', '20261031120000_northstar_companywide_admin_management.sql'
  UNION ALL SELECT '20261101120000', '20261101120000_northstar_messaging_conversation_management.sql'
  UNION ALL SELECT '20261102120000', '20261102120000_northstar_messaging_sender_eligibility.sql'
  UNION ALL SELECT '20261102130000', '20261102130000_northstar_messaging_attachment_upload_eligibility.sql'
  UNION ALL SELECT '20261103120000', '20261103120000_northstar_cross_department_direct_messaging.sql'
  UNION ALL SELECT '20261103130000', '20261103130000_northstar_companywide_incident_visibility.sql'
  UNION ALL SELECT '20261103140000', '20261103140000_northstar_department_head_smallint_call.sql'
), ledger_candidates AS (
  SELECT n.nspname AS schema_name,
         c.relname AS relation_name,
         c.relkind AS relation_kind,
         bool_or(a.attname IN ('version', 'migration_version')) AS has_version_column,
         pg_catalog.has_table_privilege(current_user, c.oid, 'SELECT') AS current_role_can_select,
         c.relrowsecurity AS rls_enabled,
         c.relforcerowsecurity AS force_rls
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  LEFT JOIN pg_catalog.pg_attribute AS a
    ON a.attrelid = c.oid
   AND a.attnum > 0
   AND NOT a.attisdropped
  WHERE c.relkind IN ('r', 'p', 'v', 'm')
    AND (n.nspname ILIKE '%migration%'
         OR c.relname ILIKE '%migration%'
         OR c.relname = 'schema_migrations')
  GROUP BY n.nspname, c.relname, c.relkind, c.oid, c.relrowsecurity, c.relforcerowsecurity
), ledger_summary AS (
  SELECT count(*) AS candidate_count,
         string_agg(format('%I.%I [kind=%s, version_column=%s, select=%s, rls=%s, force_rls=%s]',
                           schema_name, relation_name, relation_kind,
                           has_version_column, current_role_can_select,
                           rls_enabled, force_rls), '; ' ORDER BY schema_name, relation_name) AS candidates
  FROM ledger_candidates
)
SELECT expected.version AS expected_repository_version,
       expected.migration_file,
       ledger_summary.candidate_count AS catalog_candidate_count,
       ledger_summary.candidates AS catalog_candidates,
       'Applied status not proven: inspect version rows from the verified authoritative ledger.' AS live_history_status
FROM expected
CROSS JOIN ledger_summary
ORDER BY expected.version;

-- 02. Realtime publication membership for the named application tables.
-- Membership publishes changes; it does not authorize individual subscribers.
WITH target_tables(schema_name, table_name) AS (
  SELECT 'public', 'notifications'
  UNION ALL SELECT 'public', 'northstar_call_sessions'
  UNION ALL SELECT 'public', 'northstar_call_signals'
), target_publication AS (
  SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
  FROM pg_catalog.pg_publication
  WHERE pubname = 'supabase_realtime'
)
SELECT target_tables.schema_name,
       target_tables.table_name,
       target_publication.pubname AS publication_name,
       target_publication.puballtables AS publishes_all_tables,
       target_publication.pubinsert AS publishes_inserts,
       target_publication.pubupdate AS publishes_updates,
       target_publication.pubdelete AS publishes_deletes,
       target_publication.pubtruncate AS publishes_truncates,
       (publication_table.tablename IS NOT NULL) AS explicit_table_membership
FROM target_tables
LEFT JOIN target_publication ON true
LEFT JOIN pg_catalog.pg_publication_tables AS publication_table
  ON publication_table.pubname = target_publication.pubname
 AND publication_table.schemaname = target_tables.schema_name
 AND publication_table.tablename = target_tables.table_name
ORDER BY target_tables.table_name;

-- 03. Relation existence, ownership, and RLS flags for Realtime, messaging,
-- presence, incident, support, and attachment authorization tables.
WITH target_tables(schema_name, table_name) AS (
  SELECT 'public', 'notifications'
  UNION ALL SELECT 'public', 'northstar_call_sessions'
  UNION ALL SELECT 'public', 'northstar_call_signals'
  UNION ALL SELECT 'public', 'profiles'
  UNION ALL SELECT 'public', 'departments'
  UNION ALL SELECT 'public', 'conversations'
  UNION ALL SELECT 'public', 'conversation_members'
  UNION ALL SELECT 'public', 'messages'
  UNION ALL SELECT 'public', 'northstar_conversation_user_state'
  UNION ALL SELECT 'public', 'northstar_conversation_message_pins'
  UNION ALL SELECT 'public', 'northstar_conversation_typing'
  UNION ALL SELECT 'public', 'message_replies'
  UNION ALL SELECT 'public', 'message_reactions'
  UNION ALL SELECT 'public', 'message_attachments'
  UNION ALL SELECT 'public', 'message_recipient_receipts'
  UNION ALL SELECT 'public', 'northstar_incidents'
  UNION ALL SELECT 'public', 'northstar_incident_updates'
  UNION ALL SELECT 'public', 'support_inquiries'
  UNION ALL SELECT 'public', 'support_inquiry_messages'
  UNION ALL SELECT 'public', 'northstar_push_subscriptions'
  UNION ALL SELECT 'public', 'northstar_push_deliveries'
  UNION ALL SELECT 'public', 'employee_registration_photos'
  UNION ALL SELECT 'public', 'employee_registration_snapshots'
  UNION ALL SELECT 'public', 'employee_registration_rejection_history'
  UNION ALL SELECT 'realtime', 'messages'
  UNION ALL SELECT 'storage', 'objects'
)
SELECT target_tables.schema_name,
       target_tables.table_name,
       (relation.oid IS NOT NULL) AS relation_exists,
       relation.relkind AS relation_kind,
       CASE WHEN relation.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_userbyid(relation.relowner) END AS owner,
       relation.relrowsecurity AS rls_enabled,
       relation.relforcerowsecurity AS force_rls,
       CASE WHEN relation.oid IS NULL THEN NULL
            ELSE pg_catalog.row_security_active(relation.oid::regclass::text)
       END AS row_security_active_for_query_role,
       CASE WHEN owner_role.oid IS NULL THEN NULL ELSE owner_role.rolbypassrls END AS owner_bypasses_rls
FROM target_tables
LEFT JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.nspname = target_tables.schema_name
LEFT JOIN pg_catalog.pg_class AS relation
  ON relation.relnamespace = namespace.oid
 AND relation.relname = target_tables.table_name
LEFT JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = relation.relowner
ORDER BY target_tables.schema_name, target_tables.table_name;

-- 03b. Any table-like objects in northstar_private, with ownership and RLS.
-- Empty results mean no such relations are visible in the catalog to this role.
SELECT namespace.nspname AS schema_name,
       relation.relname AS relation_name,
       relation.relkind AS relation_kind,
       pg_catalog.pg_get_userbyid(relation.relowner) AS owner,
       relation.relrowsecurity AS rls_enabled,
       relation.relforcerowsecurity AS force_rls,
       relation.relacl AS direct_acl
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'northstar_private'
  AND relation.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY relation.relname;

-- 04. Complete policy expressions for Realtime, message, incident, support,
-- and Storage object rows. Review permissive policies together with restrictive
-- policies; counts alone do not establish effective authorization.
SELECT policy.schemaname,
       policy.tablename,
       policy.policyname,
       policy.permissive,
       policy.roles,
       policy.cmd,
       policy.qual AS using_expression,
       policy.with_check AS check_expression
FROM pg_catalog.pg_policies AS policy
WHERE (policy.schemaname = 'realtime' AND policy.tablename = 'messages')
   OR (policy.schemaname = 'storage' AND policy.tablename = 'objects')
   OR policy.schemaname = 'northstar_private'
   OR (policy.schemaname = 'public' AND policy.tablename IN (
        'notifications', 'northstar_call_sessions', 'northstar_call_signals',
        'profiles', 'departments', 'conversations', 'conversation_members',
        'messages', 'northstar_conversation_user_state', 'northstar_conversation_message_pins',
        'northstar_conversation_typing', 'message_replies', 'message_reactions', 'message_attachments',
        'message_recipient_receipts', 'northstar_incidents', 'northstar_incident_updates',
        'support_inquiries', 'support_inquiry_messages', 'northstar_push_subscriptions',
        'northstar_push_deliveries', 'employee_registration_photos',
        'employee_registration_snapshots', 'employee_registration_rejection_history'))
ORDER BY policy.schemaname, policy.tablename, policy.policyname;

-- 05. Effective table privileges for client roles on the relevant relations.
-- These results must be interpreted together with Section 03 RLS flags and
-- Section 04 policy expressions.
WITH target_tables(schema_name, table_name) AS (
  SELECT 'public', 'notifications'
  UNION ALL SELECT 'public', 'northstar_call_sessions'
  UNION ALL SELECT 'public', 'northstar_call_signals'
  UNION ALL SELECT 'public', 'profiles'
  UNION ALL SELECT 'public', 'conversations'
  UNION ALL SELECT 'public', 'conversation_members'
  UNION ALL SELECT 'public', 'messages'
  UNION ALL SELECT 'public', 'northstar_conversation_user_state'
  UNION ALL SELECT 'public', 'northstar_conversation_message_pins'
  UNION ALL SELECT 'public', 'northstar_conversation_typing'
  UNION ALL SELECT 'public', 'message_replies'
  UNION ALL SELECT 'public', 'message_reactions'
  UNION ALL SELECT 'public', 'message_attachments'
  UNION ALL SELECT 'public', 'message_recipient_receipts'
  UNION ALL SELECT 'public', 'northstar_incidents'
  UNION ALL SELECT 'public', 'northstar_incident_updates'
  UNION ALL SELECT 'public', 'support_inquiries'
  UNION ALL SELECT 'public', 'support_inquiry_messages'
  UNION ALL SELECT 'public', 'northstar_push_subscriptions'
  UNION ALL SELECT 'public', 'northstar_push_deliveries'
  UNION ALL SELECT 'public', 'employee_registration_photos'
  UNION ALL SELECT 'public', 'employee_registration_snapshots'
  UNION ALL SELECT 'public', 'employee_registration_rejection_history'
  UNION ALL SELECT 'realtime', 'messages'
  UNION ALL SELECT 'storage', 'objects'
), target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
), target_privileges(privilege_name) AS (
  SELECT 'SELECT' UNION ALL SELECT 'INSERT' UNION ALL SELECT 'UPDATE'
  UNION ALL SELECT 'DELETE' UNION ALL SELECT 'TRUNCATE'
  UNION ALL SELECT 'REFERENCES' UNION ALL SELECT 'TRIGGER'
)
SELECT target_tables.schema_name,
       target_tables.table_name,
       target_roles.role_name,
       (role_row.oid IS NOT NULL) AS role_exists,
       target_privileges.privilege_name,
       CASE WHEN role_row.oid IS NULL OR relation.oid IS NULL THEN NULL
            ELSE pg_catalog.has_table_privilege(role_row.oid, relation.oid, target_privileges.privilege_name)
       END AS effective_privilege,
       relation.relacl AS direct_relation_acl
FROM target_tables
LEFT JOIN pg_catalog.pg_namespace AS namespace ON namespace.nspname = target_tables.schema_name
LEFT JOIN pg_catalog.pg_class AS relation
  ON relation.relnamespace = namespace.oid AND relation.relname = target_tables.table_name
CROSS JOIN target_roles
CROSS JOIN target_privileges
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
ORDER BY target_tables.schema_name, target_tables.table_name, target_roles.role_name, target_privileges.privilege_name;

-- 05c. Effective table privileges on every northstar_private table-like
-- relation. Interpret alongside private relation RLS and policy results.
WITH target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
), private_relations AS (
  SELECT relation.*, namespace.nspname
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'northstar_private'
    AND relation.relkind IN ('r', 'p', 'v', 'm', 'f')
), target_privileges(privilege_name) AS (
  SELECT 'SELECT' UNION ALL SELECT 'INSERT' UNION ALL SELECT 'UPDATE'
  UNION ALL SELECT 'DELETE' UNION ALL SELECT 'TRUNCATE'
  UNION ALL SELECT 'REFERENCES' UNION ALL SELECT 'TRIGGER'
)
SELECT private_relations.relname AS relation_name,
       pg_catalog.pg_get_userbyid(private_relations.relowner) AS owner,
       private_relations.relrowsecurity AS rls_enabled,
       private_relations.relforcerowsecurity AS force_rls,
       private_relations.relacl AS direct_acl,
       target_roles.role_name,
       target_privileges.privilege_name,
       CASE WHEN role_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_table_privilege(role_row.oid, private_relations.oid, target_privileges.privilege_name)
       END AS effective_privilege
FROM private_relations
CROSS JOIN target_roles
CROSS JOIN target_privileges
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
ORDER BY private_relations.relname, target_roles.role_name, target_privileges.privilege_name;

-- 05b. Explicit column ACLs and effective column privileges. Column grants can
-- exist even when the corresponding table-level privilege is absent.
WITH target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
), target_privileges(privilege_name) AS (
  SELECT 'SELECT' UNION ALL SELECT 'INSERT' UNION ALL SELECT 'UPDATE' UNION ALL SELECT 'REFERENCES'
)
SELECT namespace.nspname AS schema_name,
       relation.relname AS table_name,
       attribute.attname AS column_name,
       attribute.attacl AS direct_column_acl,
       target_roles.role_name,
       (role_row.oid IS NOT NULL) AS role_exists,
       target_privileges.privilege_name,
       CASE WHEN role_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_column_privilege(role_row.oid, relation.oid, attribute.attnum, target_privileges.privilege_name)
       END AS effective_column_privilege
FROM pg_catalog.pg_attribute AS attribute
JOIN pg_catalog.pg_class AS relation ON relation.oid = attribute.attrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
CROSS JOIN target_roles
CROSS JOIN target_privileges
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
WHERE namespace.nspname = 'public'
  AND relation.relname IN (
    'profiles', 'conversations', 'conversation_members', 'messages',
    'northstar_incidents', 'northstar_incident_updates',
    'support_inquiries', 'support_inquiry_messages')
  AND attribute.attnum > 0
  AND NOT attribute.attisdropped
  AND attribute.attacl IS NOT NULL
ORDER BY relation.relname, attribute.attnum, target_roles.role_name, target_privileges.privilege_name;

-- 06. Expected RPCs and authorization helpers: source, owner, SECURITY DEFINER,
-- function settings, direct ACL, and effective execution rights. The source is
-- limited to the named application functions and never selects table row data.
WITH expected_functions(signature, schema_name, function_name) AS (
  SELECT 'public.northstar_presence_heartbeat()', 'public', 'northstar_presence_heartbeat'
  UNION ALL SELECT 'public.northstar_list_employee_presence(uuid[])', 'public', 'northstar_list_employee_presence'
  UNION ALL SELECT 'public.northstar_send_message(uuid,text,uuid)', 'public', 'northstar_send_message'
  UNION ALL SELECT 'public.northstar_send_message_existing_impl(uuid,text,uuid)', 'public', 'northstar_send_message_existing_impl'
  UNION ALL SELECT 'public.northstar_send_message_reply(uuid,text,uuid,uuid)', 'public', 'northstar_send_message_reply'
  UNION ALL SELECT 'public.northstar_send_message_reply_existing_impl(uuid,text,uuid,uuid)', 'public', 'northstar_send_message_reply_existing_impl'
  UNION ALL SELECT 'public.northstar_create_direct_conversation(uuid[])', 'public', 'northstar_create_direct_conversation'
  UNION ALL SELECT 'public.northstar_admin_set_department_head(uuid,uuid,smallint)', 'public', 'northstar_admin_set_department_head'
  UNION ALL SELECT 'public.northstar_admin_assign_department_level(uuid,uuid,smallint)', 'public', 'northstar_admin_assign_department_level'
  UNION ALL SELECT 'public.northstar_is_designated_admin()', 'public', 'northstar_is_designated_admin'
  UNION ALL SELECT 'northstar_private.is_eligible_messaging_actor()', 'northstar_private', 'is_eligible_messaging_actor'
  UNION ALL SELECT 'northstar_private.message_attachment_path_allowed(text)', 'northstar_private', 'message_attachment_path_allowed'
  UNION ALL SELECT 'northstar_private.message_attachment_object_readable(text)', 'northstar_private', 'message_attachment_object_readable'
  UNION ALL SELECT 'northstar_private.is_eligible_workspace_user()', 'northstar_private', 'is_eligible_workspace_user'
  UNION ALL SELECT 'northstar_private.is_eligible_department_member(uuid)', 'northstar_private', 'is_eligible_department_member'
  UNION ALL SELECT 'northstar_private.is_department_head(uuid)', 'northstar_private', 'is_department_head'
), target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
)
SELECT expected_functions.signature,
       (function_row.oid IS NOT NULL) AS function_exists,
       CASE WHEN function_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_userbyid(function_row.proowner) END AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       function_row.provolatile AS volatility,
       function_row.proleakproof AS leakproof,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition,
       target_roles.role_name,
       (role_row.oid IS NOT NULL) AS role_exists,
       CASE WHEN role_row.oid IS NULL OR function_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege(role_row.oid, function_row.oid, 'EXECUTE')
       END AS effective_execute,
       CASE WHEN function_row.oid IS NULL THEN NULL ELSE function_row.proacl END AS direct_acl
FROM expected_functions
LEFT JOIN pg_catalog.pg_proc AS function_row
  ON function_row.oid = pg_catalog.to_regprocedure(expected_functions.signature)
CROSS JOIN target_roles
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
ORDER BY expected_functions.signature, target_roles.role_name;

-- 06a. Discover all installed incident-related functions by catalog name,
-- including reporting/listing/history/edit/delete/status/update routines and
-- overloads. No assumed RPC signature or function name is required.
WITH target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
)
SELECT namespace.nspname AS schema_name,
       function_row.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(function_row.oid) AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       function_row.proacl AS direct_acl,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition,
       target_roles.role_name,
       (role_row.oid IS NOT NULL) AS role_exists,
       CASE WHEN role_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege(role_row.oid, function_row.oid, 'EXECUTE')
       END AS effective_execute
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = function_row.pronamespace
CROSS JOIN target_roles
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
WHERE namespace.nspname IN ('public', 'northstar_private')
  AND function_row.prokind = 'f'
  AND function_row.proname ILIKE '%incident%'
ORDER BY namespace.nspname, function_row.proname, identity_arguments, target_roles.role_name;

-- 06b. Discover all installed support/inquiry functions by catalog name,
-- covering employee submission/listing/message retrieval and admin listing/replies.
WITH target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
)
SELECT namespace.nspname AS schema_name,
       function_row.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(function_row.oid) AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       function_row.proacl AS direct_acl,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition,
       target_roles.role_name,
       (role_row.oid IS NOT NULL) AS role_exists,
       CASE WHEN role_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege(role_row.oid, function_row.oid, 'EXECUTE')
       END AS effective_execute
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = function_row.pronamespace
CROSS JOIN target_roles
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
WHERE namespace.nspname IN ('public', 'northstar_private')
  AND function_row.prokind = 'f'
  AND (function_row.proname ILIKE '%support%' OR function_row.proname ILIKE '%inquiry%')
ORDER BY namespace.nspname, function_row.proname, identity_arguments, target_roles.role_name;

-- 06c. Inventory all helper functions in northstar_private, including names
-- that do not match incident or support feature keywords.
WITH target_roles(role_name) AS (
  SELECT 'anon' UNION ALL SELECT 'authenticated' UNION ALL SELECT 'service_role'
)
SELECT function_row.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       function_row.proacl AS direct_acl,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition,
       target_roles.role_name,
       CASE WHEN role_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege(role_row.oid, function_row.oid, 'EXECUTE')
       END AS effective_execute
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = function_row.pronamespace
CROSS JOIN target_roles
LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = target_roles.role_name
WHERE namespace.nspname = 'northstar_private'
  AND function_row.prokind = 'f'
ORDER BY function_row.proname, identity_arguments, target_roles.role_name;

-- 06d. Call-signaling RPCs and any overloads. Their exact signatures and
-- implementations are not present in the checked-in migration history, so
-- report what is installed without assuming a signature.
SELECT namespace.nspname AS schema_name,
       function_row.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       function_row.proacl AS direct_acl,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = function_row.pronamespace
WHERE namespace.nspname = 'public'
  AND function_row.proname IN (
    'northstar_start_call', 'northstar_update_call_status', 'northstar_send_call_signal',
    'northstar_presence_heartbeat')
ORDER BY function_row.proname, identity_arguments;

-- 07. Trigger definitions on message and related authorization/audit tables.
-- This includes enabled user triggers and excludes internal PostgreSQL triggers.
SELECT namespace.nspname AS schema_name,
       relation.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       trigger_row.tgenabled AS trigger_enabled_state,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
       function_namespace.nspname AS trigger_function_schema,
       function_row.proname AS trigger_function_name,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS trigger_function_owner,
       function_row.prosecdef AS trigger_function_security_definer,
       function_row.proconfig AS trigger_function_settings,
       pg_catalog.pg_get_functiondef(function_row.oid) AS trigger_function_definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation ON relation.oid = trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid = function_row.pronamespace
WHERE NOT trigger_row.tgisinternal
  AND namespace.nspname = 'public'
  AND relation.relname IN (
    'messages', 'conversation_members', 'conversations', 'message_replies',
    'message_reactions', 'message_attachments', 'message_recipient_receipts',
    'northstar_call_sessions', 'northstar_call_signals', 'notifications',
    'northstar_incidents', 'northstar_incident_updates',
    'support_inquiries', 'support_inquiry_messages')
ORDER BY relation.relname, trigger_row.tgname;

-- 08. Relevant foreign keys and indexes, including the direct-conversation
-- membership uniqueness prerequisite and conversation PostgREST relations.
SELECT namespace.nspname AS schema_name,
       relation.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS constraint_definition,
       constraint_row.convalidated AS is_validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation ON relation.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'public'
  AND relation.relname IN (
    'profiles', 'departments', 'conversations', 'conversation_members',
    'messages', 'message_replies', 'message_attachments',
    'message_recipient_receipts', 'northstar_incidents', 'northstar_incident_updates',
    'support_inquiries', 'support_inquiry_messages')
ORDER BY relation.relname, constraint_row.conname;

SELECT namespace.nspname AS schema_name,
       relation.relname AS table_name,
       index_relation.relname AS index_name,
       index_row.indisunique AS is_unique,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       index_row.indpred IS NOT NULL AS is_partial,
       pg_catalog.pg_get_indexdef(index_row.indexrelid) AS index_definition
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS relation ON relation.oid = index_row.indrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid = index_row.indexrelid
WHERE namespace.nspname = 'public'
  AND relation.relname IN ('conversation_members', 'messages', 'message_attachments', 'northstar_incidents')
ORDER BY relation.relname, index_relation.relname;

-- 09. Storage bucket privacy/configuration and all policies governing object
-- access. Bucket metadata contains no object rows or signed URLs.
SELECT bucket.id AS bucket_id,
       bucket.name AS bucket_name,
       bucket.public AS is_public,
       bucket.file_size_limit,
       bucket.allowed_mime_types
FROM storage.buckets AS bucket
ORDER BY bucket.id;

SELECT policy.policyname,
       policy.permissive,
       policy.roles,
       policy.cmd,
       policy.qual AS using_expression,
       policy.with_check AS check_expression
FROM pg_catalog.pg_policies AS policy
WHERE policy.schemaname = 'storage'
  AND policy.tablename = 'objects'
ORDER BY policy.policyname;

-- 10. Supabase Realtime publication metadata for client change subscriptions.
-- Policies on realtime.messages are reported in Section 04; publication
-- membership itself is reported in Section 02.
SELECT publication.pubname AS publication_name,
       publication.puballtables AS publishes_all_tables,
       publication.pubinsert AS publishes_inserts,
       publication.pubupdate AS publishes_updates,
       publication.pubdelete AS publishes_deletes,
       publication.pubtruncate AS publishes_truncates,
       member.schemaname AS member_schema,
       member.tablename AS member_table
FROM pg_catalog.pg_publication AS publication
LEFT JOIN pg_catalog.pg_publication_tables AS member ON member.pubname = publication.pubname
WHERE publication.pubname = 'supabase_realtime'
ORDER BY member.schemaname, member.tablename;

-- 11. Candidate latest-migration objects and their current source fingerprints.
-- These are state evidence only; they do not establish ledger application or
-- approve an unapplied migration.
SELECT target.signature,
       (function_row.oid IS NOT NULL) AS function_exists,
       CASE WHEN function_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(function_row.oid) END AS function_definition,
       CASE WHEN function_row.oid IS NULL THEN NULL ELSE pg_catalog.md5(function_row.prosrc) END AS source_md5,
       CASE WHEN function_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_userbyid(function_row.proowner) END AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS function_settings,
       CASE WHEN function_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE')
       END AS authenticated_execute,
       CASE WHEN function_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE')
       END AS anon_execute,
       CASE WHEN function_row.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE')
       END AS service_role_execute
FROM (
  SELECT 'public.northstar_create_direct_conversation(uuid[])' AS signature
  UNION ALL SELECT 'public.northstar_department_list_incidents()'
  UNION ALL SELECT 'public.northstar_department_list_incident_history(uuid[])'
  UNION ALL SELECT 'public.northstar_admin_set_department_head(uuid,uuid,smallint)'
) AS target
LEFT JOIN pg_catalog.pg_proc AS function_row
  ON function_row.oid = pg_catalog.to_regprocedure(target.signature)
ORDER BY target.signature;
