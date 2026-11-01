-- Enforce the full NorthStar account eligibility contract before any existing
-- message sender or reply path runs. The existing implementations are retained
-- as private-in-practice SECURITY DEFINER implementations so their membership,
-- validation, idempotency, and reply metadata behavior remains unchanged.
-- Apply after 20261101120000_northstar_messaging_conversation_management.sql.
BEGIN;

DO $preflight$
DECLARE
  sender_oid oid;
  reply_oid oid;
  unexpected_dependents text;
  unexpected_reply_dependents text;
BEGIN
  IF to_regclass('public.profiles') IS NULL OR to_regclass('auth.users') IS NULL
     OR to_regclass('public.messages') IS NULL
     OR to_regnamespace('northstar_private') IS NULL THEN
    RAISE EXCEPTION 'NorthStar sender eligibility requires profiles, auth.users, messages, and northstar_private.';
  END IF;
  IF to_regprocedure('public.has_any_role(text[])') IS NULL
     OR to_regprocedure('public.northstar_is_designated_admin()') IS NULL THEN
    RAISE EXCEPTION 'NorthStar sender eligibility requires the existing role and designated-administrator authorization helpers.';
  END IF;

  SELECT procedure_row.oid INTO sender_oid
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'northstar_send_message'
    AND procedure_row.proargtypes = '2950 25 2950'::oidvector;
  SELECT procedure_row.oid INTO reply_oid
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'northstar_send_message_reply'
    AND procedure_row.proargtypes = '2950 25 2950 2950'::oidvector;

  IF sender_oid IS NULL OR reply_oid IS NULL THEN
    RAISE EXCEPTION 'NorthStar sender eligibility requires the existing message and reply RPCs.';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
      WHERE namespace_row.nspname = 'public'
        AND procedure_row.proname = 'northstar_send_message') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
         JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
         WHERE namespace_row.nspname = 'public'
           AND procedure_row.proname = 'northstar_send_message_reply') <> 1 THEN
    RAISE EXCEPTION 'Unexpected overloaded NorthStar sender or reply functions exist; inspect every signature before wrapping the RPCs.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = sender_oid AND procedure_row.prosecdef
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.proretset AND procedure_row.prorettype = 'public.messages'::regtype
      AND 'row_security=off' = ANY(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) OR NOT has_function_privilege('authenticated', sender_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'The existing message sender must be postgres-owned, SECURITY DEFINER, use an empty search_path and row_security=off, return SETOF public.messages, and be callable by authenticated users.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = reply_oid AND procedure_row.prosecdef
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prorettype = 'jsonb'::regtype
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = ''
      )
  ) OR NOT has_function_privilege('authenticated', reply_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'The existing reply RPC must be postgres-owned, SECURITY DEFINER, use an empty search_path, return jsonb, and be callable by authenticated users.';
  END IF;
  IF EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
       WHERE namespace_row.nspname = 'public'
         AND procedure_row.proname IN ('northstar_send_message_existing_impl', 'northstar_send_message_reply_existing_impl')
     ) OR to_regprocedure('northstar_private.is_eligible_messaging_actor()') IS NOT NULL THEN
    RAISE EXCEPTION 'A NorthStar messaging eligibility implementation name is already occupied; inspect it before continuing.';
  END IF;

  SELECT string_agg(format('%I.%I', namespace_row.nspname, procedure_row.proname), ', ' ORDER BY namespace_row.nspname, procedure_row.proname)
  INTO unexpected_dependents
  FROM pg_catalog.pg_depend AS dependency
  JOIN pg_catalog.pg_proc AS procedure_row ON dependency.classid = 'pg_proc'::regclass
    AND procedure_row.oid = dependency.objid
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE dependency.refclassid = 'pg_proc'::regclass
    AND dependency.refobjid = sender_oid
    AND procedure_row.oid <> sender_oid;
  IF unexpected_dependents IS NOT NULL THEN
    RAISE EXCEPTION 'Other database functions have tracked dependencies on northstar_send_message and must be reviewed before wrapping it: %', unexpected_dependents;
  END IF;
  SELECT string_agg(format('%I.%I', namespace_row.nspname, procedure_row.proname), ', ' ORDER BY namespace_row.nspname, procedure_row.proname)
  INTO unexpected_reply_dependents
  FROM pg_catalog.pg_depend AS dependency
  JOIN pg_catalog.pg_proc AS procedure_row ON dependency.classid = 'pg_proc'::regclass
    AND procedure_row.oid = dependency.objid
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE dependency.refclassid = 'pg_proc'::regclass
    AND dependency.refobjid = reply_oid
    AND procedure_row.oid <> reply_oid;
  IF unexpected_reply_dependents IS NOT NULL THEN
    RAISE EXCEPTION 'Other database functions have tracked dependencies on northstar_send_message_reply and must be reviewed before wrapping it: %', unexpected_reply_dependents;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
    WHERE procedure_row.oid IN (sender_oid, reply_oid)
      AND privilege_row.privilege_type = 'EXECUTE'
      AND privilege_row.grantee NOT IN (
        0, procedure_row.proowner,
        'anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid
      )
  ) THEN
    RAISE EXCEPTION 'The existing message or reply RPC has custom EXECUTE grants; review those callers before moving the implementations.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND attname = 'id' AND atttypid = 'uuid'::regtype AND attnum > 0 AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND attname = 'role' AND attnum > 0 AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND attname = 'approval_status' AND attnum > 0 AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND attname = 'registration_completed' AND atttypid = 'boolean'::regtype AND attnum > 0 AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND attname = 'employment_status' AND attnum > 0 AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'auth.users'::regclass AND attname = 'email_confirmed_at' AND atttypid = 'timestamptz'::regtype AND attnum > 0 AND NOT attisdropped) THEN
    RAISE EXCEPTION 'NorthStar sender eligibility requires the established profile status and confirmed-email columns.';
  END IF;
END;
$preflight$;

CREATE FUNCTION northstar_private.is_eligible_messaging_actor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = auth.uid()
      AND profile.approval_status::text = 'approved'
      AND profile.registration_completed IS TRUE
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
      AND public.has_any_role(ARRAY['employee', 'manager', 'admin']::text[])
      AND (
        profile.role::text IN ('employee', 'manager')
        OR (profile.role::text = 'admin' AND public.northstar_is_designated_admin())
      )
  );
$function$;
ALTER FUNCTION northstar_private.is_eligible_messaging_actor() OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_eligible_messaging_actor() FROM PUBLIC, anon, authenticated, service_role;

-- Keep the original database implementations and their exact protections.
-- Renaming lets the public RPC names add the stricter eligibility gate without
-- reimplementing the sender's idempotency or the reply's metadata workflow.
ALTER FUNCTION public.northstar_send_message(uuid, text, uuid)
  RENAME TO northstar_send_message_existing_impl;
ALTER FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid)
  RENAME TO northstar_send_message_reply_existing_impl;

REVOKE ALL ON FUNCTION public.northstar_send_message_existing_impl(uuid, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.northstar_send_message_reply_existing_impl(uuid, text, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.northstar_send_message(
  p_conversation_id uuid,
  p_content text,
  p_client_request_id uuid
)
RETURNS SETOF public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
BEGIN
  IF NOT northstar_private.is_eligible_messaging_actor() THEN
    RAISE EXCEPTION 'An approved, registered, active employee or designated administrator with a confirmed email is required to send messages.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT * FROM public.northstar_send_message_existing_impl(
      p_conversation_id, p_content, p_client_request_id
    );
END;
$function$;
ALTER FUNCTION public.northstar_send_message(uuid, text, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_send_message(uuid, text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_send_message(uuid, text, uuid) TO authenticated;

CREATE FUNCTION public.northstar_send_message_reply(
  p_conversation_id uuid,
  p_content text,
  p_client_request_id uuid,
  p_reply_to_message_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
BEGIN
  IF NOT northstar_private.is_eligible_messaging_actor() THEN
    RAISE EXCEPTION 'An approved, registered, active employee or designated administrator with a confirmed email is required to send message replies.' USING ERRCODE = '42501';
  END IF;
  RETURN public.northstar_send_message_reply_existing_impl(
    p_conversation_id, p_content, p_client_request_id, p_reply_to_message_id
  );
END;
$function$;
ALTER FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) TO authenticated;

DO $acl_verify$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_send_message(uuid,text,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_send_message_reply(uuid,text,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_send_message_existing_impl(uuid,text,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_send_message_reply_existing_impl(uuid,text,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_send_message(uuid,text,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_send_message_reply(uuid,text,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_send_message_existing_impl(uuid,text,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_send_message_reply_existing_impl(uuid,text,uuid,uuid)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid IN (
         'public.northstar_send_message(uuid,text,uuid)'::regprocedure,
         'public.northstar_send_message_reply(uuid,text,uuid,uuid)'::regprocedure,
         'public.northstar_send_message_existing_impl(uuid,text,uuid)'::regprocedure,
         'public.northstar_send_message_reply_existing_impl(uuid,text,uuid,uuid)'::regprocedure,
         'northstar_private.is_eligible_messaging_actor()'::regprocedure
       ) AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'NorthStar message sender implementations must not be executable by anon or PUBLIC.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_send_message(uuid,text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.northstar_send_message_reply(uuid,text,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated clients must retain access to the eligibility-guarded message and reply RPCs.';
  END IF;
  IF has_function_privilege('authenticated', 'public.northstar_send_message_existing_impl(uuid,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.northstar_send_message_reply_existing_impl(uuid,text,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'northstar_private.is_eligible_messaging_actor()', 'EXECUTE')
     OR has_function_privilege('service_role', 'northstar_private.is_eligible_messaging_actor()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Internal messaging implementation functions must not be directly executable by authenticated clients.';
  END IF;
END;
$acl_verify$;

NOTIFY pgrst, 'reload schema';
COMMIT;
