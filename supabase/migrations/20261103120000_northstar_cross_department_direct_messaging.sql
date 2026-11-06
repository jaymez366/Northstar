-- Allow eligible employees and managers to start direct conversations across
-- departments, including when either participant has no department assigned.
-- Apply after 20261102130000_northstar_messaging_attachment_upload_eligibility.sql.
BEGIN;

DO $preflight$
DECLARE
  target_function oid := to_regprocedure('public.northstar_create_direct_conversation(uuid[])');
  installed_definition text;
BEGIN
  IF target_function IS NULL
     OR to_regprocedure('public.has_any_role(text[])') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('public.conversations') IS NULL
     OR to_regclass('public.conversation_members') IS NULL THEN
    RAISE EXCEPTION 'Cross-department messaging requires the existing direct-conversation RPC, eligibility helper, and messaging tables.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
      AND column_name IN ('id', 'role', 'registration_completed', 'approval_status', 'employment_status')
    GROUP BY table_schema, table_name
    HAVING count(DISTINCT column_name) = 5
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users'
      AND column_name IN ('id', 'email_confirmed_at')
    GROUP BY table_schema, table_name
    HAVING count(DISTINCT column_name) = 2
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'conversation_members'
      AND column_name IN ('conversation_id', 'user_id')
    GROUP BY table_schema, table_name
    HAVING count(DISTINCT column_name) = 2
  ) THEN
    RAISE EXCEPTION 'Cross-department messaging preflight failed; the profile, Auth, or conversation-member column contract differs.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    JOIN pg_roles AS owner_role ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = target_function
      AND procedure_row.prorettype = 'uuid'::regtype
      AND procedure_row.prosecdef IS TRUE
      AND owner_role.rolname = 'postgres'
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) THEN
    RAISE EXCEPTION 'The installed direct-conversation RPC signature, owner, SECURITY DEFINER, search_path, or row_security configuration differs from the reviewed function.';
  END IF;

  installed_definition := pg_get_functiondef(target_function);
  IF installed_definition NOT ILIKE '%public.has_any_role%'
     OR installed_definition NOT ILIKE '%registration_completed IS TRUE%'
     OR installed_definition NOT ILIKE '%approval_status::text = ''approved''%'
     OR installed_definition NOT ILIKE '%employment_status::text = ''active''%'
     OR installed_definition NOT ILIKE '%email_confirmed_at IS NOT NULL%'
     OR installed_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR installed_definition NOT ILIKE '%array_agg%'
     OR installed_definition NOT ILIKE '%count(*) = 2%' THEN
    RAISE EXCEPTION 'The installed direct-conversation RPC body does not contain the reviewed eligibility, lock, and exact-member-reuse protections.';
  END IF;

  IF to_regclass('public.northstar_conversation_members_pair_uidx') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_index AS index_row
       WHERE index_row.indexrelid = 'public.northstar_conversation_members_pair_uidx'::regclass
         AND index_row.indrelid = 'public.conversation_members'::regclass
         AND index_row.indisunique AND index_row.indisvalid
         AND index_row.indnkeyatts = 2
         AND pg_get_indexdef(index_row.indexrelid) ILIKE '%(conversation_id, user_id)%'
     ) THEN
    RAISE EXCEPTION 'The direct-conversation membership uniqueness index is missing or invalid.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege_row
    WHERE procedure_row.oid = target_function
      AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
  ) OR has_function_privilege('anon', target_function, 'EXECUTE')
    OR has_function_privilege('service_role', target_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'The direct-conversation RPC currently has PUBLIC, anon, or service_role EXECUTE access; inspect the live ACL before continuing.';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.northstar_create_direct_conversation(p_member_ids uuid[])
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  peer_id uuid;
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

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'An approved, confirmed, active employee account with completed registration is required.' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = peer_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Direct conversations require another approved, confirmed, active employee or manager with completed registration.' USING ERRCODE = '42501';
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

DO $postflight$
DECLARE
  target_function regprocedure := 'public.northstar_create_direct_conversation(uuid[])'::regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    WHERE procedure_row.oid = target_function
      AND procedure_row.prorettype = 'uuid'::regtype
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
  ) OR NOT has_function_privilege('authenticated', target_function, 'EXECUTE')
     OR has_function_privilege('anon', target_function, 'EXECUTE')
     OR has_function_privilege('service_role', target_function, 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_proc AS procedure_row
       CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid = target_function
         AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Direct-conversation RPC EXECUTE permissions do not match the authenticated-only contract.';
  END IF;
END;
$postflight$;

COMMIT;

-- Read-only post-migration verification:
-- SELECT p.oid::regprocedure AS signature, pg_get_userbyid(p.proowner) AS owner,
--        p.prosecdef AS security_definer, p.proconfig,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
--        has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute
-- FROM pg_proc AS p
-- WHERE p.oid = to_regprocedure('public.northstar_create_direct_conversation(uuid[])');
