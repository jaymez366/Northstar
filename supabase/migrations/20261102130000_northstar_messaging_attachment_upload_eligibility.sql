-- Apply after 20261102120000_northstar_messaging_sender_eligibility.sql.
-- Enforce the same eligible-account gate before a message attachment reaches
-- Storage, while retaining the existing caller-owned path and membership rules.
BEGIN;

DO $preflight$
DECLARE
  attachment_oid oid;
BEGIN
  IF to_regprocedure('northstar_private.is_eligible_messaging_actor()') IS NULL
     OR to_regprocedure('northstar_private.is_conversation_member(uuid)') IS NULL
     OR to_regprocedure('northstar_private.message_attachment_path_allowed(text)') IS NULL THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the applied messaging eligibility and conversation membership helpers.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = 'northstar_private.is_conversation_member(uuid)'::regprocedure
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prosecdef
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) OR NOT has_function_privilege('authenticated', 'northstar_private.is_conversation_member(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'NorthStar attachment authorization requires the postgres-owned, hardened conversation-membership helper.';
  END IF;

  SELECT procedure_row.oid INTO attachment_oid
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'northstar_send_message_attachment'
    AND procedure_row.proargtypes = '2950 25 25 25 20 25 2950 23'::oidvector;
  IF attachment_oid IS NULL
     OR (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
         JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
         WHERE namespace_row.nspname = 'public'
           AND procedure_row.proname = 'northstar_send_message_attachment') <> 1 THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the single inspected northstar_send_message_attachment(uuid,text,text,text,bigint,text,uuid,integer) function.';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = attachment_oid
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prosecdef
      AND procedure_row.prorettype = 'jsonb'::regtype
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) OR NOT has_function_privilege('authenticated', attachment_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'The existing attachment RPC must be postgres-owned, SECURITY DEFINER, use an empty search_path, return jsonb, and be callable by authenticated users.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'northstar_send_message_attachment_existing_impl'
  ) THEN
    RAISE EXCEPTION 'The internal attachment implementation name is already occupied; inspect it before wrapping the RPC.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_depend AS dependency
    JOIN pg_catalog.pg_proc AS dependent_function ON dependency.classid = 'pg_proc'::regclass
      AND dependent_function.oid = dependency.objid
    WHERE dependency.refclassid = 'pg_proc'::regclass
      AND dependency.refobjid = attachment_oid
      AND dependent_function.oid <> attachment_oid
  ) THEN
    RAISE EXCEPTION 'Other database functions have tracked dependencies on northstar_send_message_attachment; review them before wrapping the RPC.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
    WHERE procedure_row.oid = attachment_oid
      AND privilege_row.privilege_type = 'EXECUTE'
      AND privilege_row.grantee NOT IN (
        0, procedure_row.proowner,
        'anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid
      )
  ) THEN
    RAISE EXCEPTION 'The attachment RPC has custom EXECUTE grants; review those callers before moving the implementation.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = 'northstar_private.is_eligible_messaging_actor()'::regprocedure
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prosecdef
      AND 'row_security=off' = ANY(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the postgres-owned, hardened messaging eligibility helper.';
  END IF;

  IF to_regclass('storage.objects') IS NULL OR to_regclass('storage.buckets') IS NULL THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires Supabase Storage tables.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation
    WHERE relation.oid = 'storage.objects'::regclass
      AND relation.relrowsecurity AND NOT relation.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires enabled, non-forced Storage object RLS.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets AS bucket
    WHERE bucket.id = 'northstar-message-attachments'
      AND bucket.public IS FALSE
      AND bucket.file_size_limit = 26214400
      AND bucket.allowed_mime_types = ARRAY[
        'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm',
        'application/pdf', 'text/plain', 'text/csv', 'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the existing private message bucket and its reviewed size and MIME allowlist.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'storage.objects'::regclass
      AND policy.polname = 'northstar_message_attachments_upload_guard'
      AND policy.polcmd = 'a'
      AND policy.polpermissive IS FALSE
      AND policy.polroles = ARRAY['authenticated'::regrole::oid]
      AND coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ILIKE '%northstar_private.message_attachment_path_allowed%'
      AND coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ILIKE '%northstar-message-attachments%'
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the existing restrictive authenticated Storage upload guard for the private message-attachments bucket.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'storage.objects'::regclass
      AND policy.polname = 'northstar_message_attachments_anon_upload_guard'
      AND policy.polcmd = 'a'
      AND policy.polpermissive IS FALSE
      AND policy.polroles = ARRAY['anon'::regrole::oid]
      AND coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ILIKE '%northstar-message-attachments%'
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the existing restrictive anonymous upload guard for the private message bucket.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = 'northstar_private.message_attachment_path_allowed(text)'::regprocedure
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prosecdef
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires the existing hardened Storage path helper.';
  END IF;

  IF to_regprocedure('northstar_private.is_eligible_messaging_actor()') IS NULL
     OR NOT has_function_privilege('authenticated', 'northstar_private.message_attachment_path_allowed(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'NorthStar attachment eligibility requires authenticated access to the Storage path guard and its protected eligibility helper.';
  END IF;
END;
$preflight$;

ALTER FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer)
  RENAME TO northstar_send_message_attachment_existing_impl;
REVOKE ALL ON FUNCTION public.northstar_send_message_attachment_existing_impl(uuid, text, text, text, bigint, text, uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.northstar_send_message_attachment(
  p_conversation_id uuid,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint,
  p_caption text,
  p_client_request_id uuid,
  p_duration_seconds integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
BEGIN
  IF NOT northstar_private.is_eligible_messaging_actor() THEN
    RAISE EXCEPTION 'An approved, registered, active employee or designated administrator with a confirmed email is required to send message attachments.' USING ERRCODE = '42501';
  END IF;
  RETURN public.northstar_send_message_attachment_existing_impl(
    p_conversation_id, p_storage_path, p_file_name, p_mime_type,
    p_size_bytes, p_caption, p_client_request_id, p_duration_seconds
  );
END;
$function$;
ALTER FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.message_attachment_path_allowed(p_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  path_conversation uuid;
  path_user uuid;
BEGIN
  IF auth.uid() IS NULL
     OR pg_catalog.array_length(pg_catalog.string_to_array(p_path, '/'), 1) <> 3 THEN
    RETURN false;
  END IF;
  IF NOT northstar_private.is_eligible_messaging_actor() THEN
    RETURN false;
  END IF;
  IF pg_catalog.split_part(p_path, '/', 1) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
     OR pg_catalog.split_part(p_path, '/', 2) <> auth.uid()::text
     OR pg_catalog.split_part(p_path, '/', 3) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\.(jpg|png|gif|webp|mp4|webm|pdf|txt|csv|doc|docx|xls|xlsx|ppt|pptx|ogg|m4a|mp3|wav)$' THEN
    RETURN false;
  END IF;

  path_conversation := pg_catalog.split_part(p_path, '/', 1)::uuid;
  path_user := pg_catalog.split_part(p_path, '/', 2)::uuid;
  RETURN path_user = auth.uid()
    AND northstar_private.is_conversation_member(path_conversation);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN false;
END;
$function$;

ALTER FUNCTION northstar_private.message_attachment_path_allowed(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.message_attachment_path_allowed(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.message_attachment_path_allowed(text) TO authenticated;

DO $acl_verify$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_send_message_attachment(uuid,text,text,text,bigint,text,uuid,integer)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid = 'public.northstar_send_message_attachment(uuid,text,text,text,bigint,text,uuid,integer)'::regprocedure
         AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'The attachment RPC must not be executable by anon.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_send_message_attachment(uuid,text,text,text,bigint,text,uuid,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated clients must be able to invoke the eligibility-guarded attachment RPC.';
  END IF;
END;
$acl_verify$;

DO $acl_verify_internal$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_send_message_attachment_existing_impl(uuid,text,text,text,bigint,text,uuid,integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.northstar_send_message_attachment_existing_impl(uuid,text,text,text,bigint,text,uuid,integer)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_send_message_attachment_existing_impl(uuid,text,text,text,bigint,text,uuid,integer)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid = 'public.northstar_send_message_attachment_existing_impl(uuid,text,text,text,bigint,text,uuid,integer)'::regprocedure
         AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'The internal attachment implementation must not be executable by client or service roles.';
  END IF;
  IF has_function_privilege('anon', 'northstar_private.message_attachment_path_allowed(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'northstar_private.message_attachment_path_allowed(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'NorthStar attachment path authorization must remain callable only by authenticated users and trusted owners.';
  END IF;
END;
$acl_verify_internal$;

COMMIT;
