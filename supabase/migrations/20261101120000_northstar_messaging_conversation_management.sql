-- Complete the authenticated direct-conversation creation contract used by the
-- employee messaging client. Existing core message tables and send RPC are
-- deliberately retained; this migration fails closed if their contract differs.
BEGIN;

DO $preflight$
DECLARE
  missing_columns text;
  sender_oid oid;
  legacy_create_oid oid;
BEGIN
  IF to_regclass('public.conversations') IS NULL
     OR to_regclass('public.conversation_members') IS NULL
     OR to_regclass('public.messages') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'NorthStar messaging requires the existing conversations, conversation_members, messages, profiles, and auth.users tables.';
  END IF;
  IF to_regprocedure('public.has_any_role(text[])') IS NULL THEN
    RAISE EXCEPTION 'NorthStar messaging requires public.has_any_role(text[]).';
  END IF;
  IF to_regprocedure('public.create_conversation(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'NorthStar messaging requires the legacy conversation RPC to exist so its client execution can be retired safely.';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
      WHERE namespace_row.nspname = 'public' AND procedure_row.proname = 'create_conversation') <> 1 THEN
    RAISE EXCEPTION 'Unexpected overloaded public.create_conversation functions exist; inspect every signature before retiring the legacy client RPC.';
  END IF;
  legacy_create_oid := to_regprocedure('public.create_conversation(uuid[])');
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = legacy_create_oid
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.prosecdef
      AND EXISTS (
        SELECT 1 FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[])) AS setting(config_value)
        WHERE split_part(setting.config_value, '=', 1) = 'search_path'
          AND regexp_replace(split_part(setting.config_value, '=', 2), '["]', '', 'g') = 'pg_catalog, public'
      )
  ) OR NOT has_function_privilege('authenticated', legacy_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('service_role', legacy_create_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'The legacy conversation RPC no longer matches the inspected postgres-owned SECURITY DEFINER, pg_catalog/public search_path, authenticated/service_role execution contract.';
  END IF;
  SELECT procedure_row.oid INTO sender_oid
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'northstar_send_message'
    AND procedure_row.proargtypes = '2950 25 2950'::oidvector;
  IF sender_oid IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = sender_oid
      AND procedure_row.proretset
      AND procedure_row.prorettype = 'public.messages'::regtype
  ) OR NOT has_function_privilege('authenticated', sender_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'NorthStar messaging requires the authenticated SETOF public.messages sender contract from the applied message-interactions migration.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'northstar_create_direct_conversation'
  ) THEN
    RAISE EXCEPTION 'northstar_create_direct_conversation(uuid[]) already exists; inspect it before applying this migration.';
  END IF;

  SELECT string_agg(required.table_name || '.' || required.column_name, ', ' ORDER BY required.table_name, required.column_name)
  INTO missing_columns
  FROM (VALUES
    ('conversations', 'id', 'uuid'::regtype), ('conversations', 'updated_at', 'timestamptz'::regtype),
    ('conversation_members', 'conversation_id', 'uuid'::regtype),
    ('conversation_members', 'user_id', 'uuid'::regtype),
    ('profiles', 'id', 'uuid'::regtype), ('profiles', 'department_id', 'uuid'::regtype),
    ('profiles', 'role', NULL::regtype), ('profiles', 'approval_status', NULL::regtype),
    ('profiles', 'employment_status', NULL::regtype), ('profiles', 'registration_completed', 'boolean'::regtype),
    ('conversation_members', 'last_read_at', 'timestamptz'::regtype),
    ('messages', 'id', 'uuid'::regtype), ('messages', 'conversation_id', 'uuid'::regtype),
    ('messages', 'sender_id', 'uuid'::regtype), ('messages', 'content', 'text'::regtype),
    ('messages', 'created_at', 'timestamptz'::regtype)
  ) AS required(table_name, column_name, type_oid)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS actual
    WHERE actual.attrelid = to_regclass('public.' || required.table_name)
      AND actual.attname = required.column_name
      AND (required.type_oid IS NULL OR actual.atttypid = required.type_oid)
      AND actual.attnum > 0 AND NOT actual.attisdropped
  );
  IF missing_columns IS NOT NULL THEN
    RAISE EXCEPTION 'NorthStar messaging preflight failed; missing or incompatible columns: %', missing_columns;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'auth.users'::regclass AND attname = 'email_confirmed_at'
      AND atttypid = 'timestamptz'::regtype AND attnum > 0 AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'NorthStar messaging requires auth.users.email_confirmed_at.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.messages'::regclass
      AND conname = 'messages_conversation_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.conversations'::regclass
      AND convalidated
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.conversation_members'::regclass
      AND conname = 'conversation_members_user_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.profiles'::regclass
      AND convalidated
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.conversation_members'::regclass
      AND conname = 'conversation_members_conversation_id_fkey'
      AND contype = 'f'
      AND confrelid = 'public.conversations'::regclass
      AND convalidated
  ) THEN
    RAISE EXCEPTION 'NorthStar messaging requires the validated message/conversation foreign keys used by the frontend relationship queries.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation
    WHERE relation.oid IN (
      'public.conversations'::regclass,
      'public.conversation_members'::regclass,
      'public.messages'::regclass
    ) AND (relation.relrowsecurity IS FALSE OR relation.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'NorthStar messaging requires RLS enabled and not forced on the postgres-owned conversation helpers.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.conversations'::regclass
      AND attribute.attnum > 0 AND NOT attribute.attisdropped
      AND attribute.attnotnull
      AND attribute.attname <> 'id'
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attrdef AS default_value
        WHERE default_value.adrelid = attribute.attrelid AND default_value.adnum = attribute.attnum
      )
      AND attribute.attidentity = '' AND attribute.attgenerated = ''
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.conversation_members'::regclass
      AND attribute.attnum > 0 AND NOT attribute.attisdropped
      AND attribute.attnotnull
      AND attribute.attname NOT IN ('conversation_id', 'user_id')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attrdef AS default_value
        WHERE default_value.adrelid = attribute.attrelid AND default_value.adnum = attribute.attnum
      )
      AND attribute.attidentity = '' AND attribute.attgenerated = ''
  ) THEN
    RAISE EXCEPTION 'NorthStar messaging cannot safely create conversation rows with the current required-column contract.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    JOIN pg_catalog.pg_attrdef AS default_value
      ON default_value.adrelid = attribute.attrelid AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = 'public.conversations'::regclass
      AND attribute.attname = 'id' AND NOT attribute.attisdropped
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.conversations'::regclass
      AND attribute.attname = 'id' AND attribute.attidentity <> '' AND NOT attribute.attisdropped
  ) THEN
    RAISE EXCEPTION 'NorthStar messaging requires conversations.id to have a database-generated default.';
  END IF;

  IF to_regclass('public.northstar_conversation_members_pair_uidx') IS NOT NULL THEN
    RAISE EXCEPTION 'The NorthStar conversation membership index name is already occupied; inspect it before applying.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.conversation_members
    GROUP BY conversation_id, user_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate conversation memberships exist; resolve them before creating the unique membership index.';
  END IF;

END;
$preflight$;

CREATE UNIQUE INDEX northstar_conversation_members_pair_uidx
  ON public.conversation_members (conversation_id, user_id);

CREATE FUNCTION public.northstar_create_direct_conversation(p_member_ids uuid[])
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  peer_id uuid;
  actor_department_id uuid;
  peer_department_id uuid;
  conversation_id uuid;
BEGIN
  IF actor_id IS NULL OR NOT public.has_any_role(ARRAY['employee', 'manager']::text[]) THEN
    RAISE EXCEPTION 'An active employee account is required to start a conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_member_ids IS NULL OR cardinality(p_member_ids) <> 1 OR p_member_ids[1] IS NULL THEN
    RAISE EXCEPTION 'A direct conversation requires exactly one other employee.' USING ERRCODE = '22023';
  END IF;
  peer_id := p_member_ids[1];
  IF peer_id = actor_id THEN
    RAISE EXCEPTION 'A conversation cannot be created with the same employee.' USING ERRCODE = '22023';
  END IF;

  SELECT profile.department_id INTO actor_department_id
  FROM public.profiles AS profile
  JOIN auth.users AS account ON account.id = profile.id
  WHERE profile.id = actor_id
    AND profile.role::text IN ('employee', 'manager')
    AND profile.registration_completed IS TRUE
    AND profile.approval_status::text = 'approved'
    AND profile.employment_status::text = 'active'
    AND account.email_confirmed_at IS NOT NULL;
  IF actor_department_id IS NULL THEN
    RAISE EXCEPTION 'An approved, confirmed employee assigned to a department is required.' USING ERRCODE = '42501';
  END IF;

  SELECT profile.department_id INTO peer_department_id
  FROM public.profiles AS profile
  JOIN auth.users AS account ON account.id = profile.id
  WHERE profile.id = peer_id
    AND profile.role::text IN ('employee', 'manager')
    AND profile.registration_completed IS TRUE
    AND profile.approval_status::text = 'approved'
    AND profile.employment_status::text = 'active'
    AND account.email_confirmed_at IS NOT NULL;
  IF peer_department_id IS NULL OR peer_department_id IS DISTINCT FROM actor_department_id THEN
    RAISE EXCEPTION 'Direct conversations are limited to confirmed, active employees in your department.' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(LEAST(actor_id, peer_id)::text || ':' || GREATEST(actor_id, peer_id)::text, 0)
  );

  SELECT membership.conversation_id INTO conversation_id
  FROM public.conversation_members AS membership
  GROUP BY membership.conversation_id
  HAVING count(*) = 2
    AND pg_catalog.array_agg(membership.user_id ORDER BY membership.user_id)
      = ARRAY[LEAST(actor_id, peer_id), GREATEST(actor_id, peer_id)]::uuid[]
  ORDER BY membership.conversation_id
  LIMIT 1;

  IF conversation_id IS NOT NULL THEN
    RETURN conversation_id;
  END IF;

  INSERT INTO public.conversations DEFAULT VALUES
  RETURNING id INTO conversation_id;

  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES (conversation_id, actor_id), (conversation_id, peer_id);

  UPDATE public.conversations
  SET updated_at = pg_catalog.clock_timestamp()
  WHERE id = conversation_id;

  RETURN conversation_id;
END;
$function$;
ALTER FUNCTION public.northstar_create_direct_conversation(uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_create_direct_conversation(uuid[]) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_create_direct_conversation(uuid[]) TO authenticated;

-- Retire the legacy client entry point after the application has moved to the
-- department-scoped RPC above. Internal calls made by trusted function owners
-- remain possible; clients must use the eligibility-checked route.
REVOKE ALL ON FUNCTION public.create_conversation(uuid[]) FROM PUBLIC, anon, authenticated, service_role;

DO $realtime$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'NorthStar messaging requires the supabase_realtime publication.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END;
$realtime$;

DO $acl_check$
BEGIN
  IF has_function_privilege('anon', 'public.create_conversation(uuid[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.create_conversation(uuid[])', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.create_conversation(uuid[])', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid = 'public.create_conversation(uuid[])'::regprocedure
         AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'The legacy conversation RPC remains executable by a client role or PUBLIC.';
  END IF;
  IF has_function_privilege('anon', 'public.northstar_create_direct_conversation(uuid[])', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.northstar_create_direct_conversation(uuid[])', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid = 'public.northstar_create_direct_conversation(uuid[])'::regprocedure
         AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Direct conversation creation must not be executable by anon or PUBLIC.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_create_direct_conversation(uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated employees must be able to create authorized direct conversations.';
  END IF;
END;
$acl_check$;

NOTIFY pgrst, 'reload schema';
COMMIT;
