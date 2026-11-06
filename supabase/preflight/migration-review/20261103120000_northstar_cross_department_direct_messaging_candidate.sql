-- Allow eligible employees and managers assigned to different departments to
-- start direct conversations while retaining department-assignment checks.
-- Apply after 20261102130000_northstar_messaging_attachment_upload_eligibility.sql.
-- Definition fingerprint method: SHA-256 over UTF-8 pg_proc.prosrc after
-- normalizing CRLF/CR to LF, with no UTF-8 BOM. The predecessor fingerprint
-- f977444d788ab38aa3cd5c116957e92d3c6892ab80aed93ae007e9e181f1b728 was
-- calculated from the text between the $function$ delimiters in the exact
-- function body in 20261101120000_northstar_messaging_conversation_management.sql.
-- It is derived from repository SQL, not copied from the unavailable raw audit
-- CSV. Separate catalog assertions bind the source to the expected signature,
-- language, owner, security settings, and ACL. The postflight uses SHA-256
-- 114212fd1159fec1483d13251350f9238441c34be4461cbff76b1aa1ef2f7161 for the
-- exact candidate body after the same normalization.
BEGIN;

DO $preflight$
DECLARE
  target_function oid := to_regprocedure('public.northstar_create_direct_conversation(uuid[])');
  membership_index oid := to_regclass('public.northstar_conversation_members_pair_uidx');
  installed_definition text;
  installed_source text;
  installed_source_sha256 text;
  expected_source_sha256 constant text := 'f977444d788ab38aa3cd5c116957e92d3c6892ab80aed93ae007e9e181f1b728';
BEGIN
  IF target_function IS NULL
     OR to_regprocedure('public.has_any_role(text[])') IS NULL
     OR to_regprocedure('pg_catalog.sha256(bytea)') IS NULL
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
      AND procedure_row.prolang = (SELECT language_row.oid FROM pg_catalog.pg_language AS language_row WHERE language_row.lanname = 'plpgsql')
      AND procedure_row.prosecdef IS TRUE
      AND owner_role.rolname = 'postgres'
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
      AND pg_catalog.cardinality(procedure_row.proconfig) = 2
      AND procedure_row.provolatile = 'v'
      AND procedure_row.proisstrict IS FALSE
      AND procedure_row.proleakproof IS FALSE
      AND procedure_row.proparallel = 'u'
      AND procedure_row.proargnames = ARRAY['p_member_ids']::text[]
      AND procedure_row.proargmodes IS NULL
  ) THEN
    RAISE EXCEPTION 'The installed direct-conversation RPC signature, owner, SECURITY DEFINER, search_path, or row_security configuration differs from the reviewed function.';
  END IF;

  installed_definition := pg_get_functiondef(target_function);
  SELECT procedure_row.prosrc INTO installed_source
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = target_function;
  installed_source_sha256 := pg_catalog.encode(
    pg_catalog.sha256(
      pg_catalog.convert_to(
        pg_catalog.replace(pg_catalog.replace(installed_source, E'\r\n', E'\n'), E'\r', E'\n'),
        'UTF8'
      )
    ),
    'hex'
  );
  IF installed_source_sha256 <> expected_source_sha256 THEN
    RAISE EXCEPTION 'The direct-conversation function source differs from the exact repository predecessor fingerprint. Review the installed definition before applying.';
  END IF;

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

  IF membership_index IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indexrelid = membership_index
      AND index_row.indrelid = 'public.conversation_members'::regclass
      AND index_row.indisunique IS TRUE
      AND index_row.indisvalid IS TRUE
      AND index_row.indpred IS NULL
      AND index_row.indexprs IS NULL
      AND index_row.indnkeyatts = 2
      AND index_row.indnatts = 2
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) = 'conversation_id'
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) = 'user_id'
  ) THEN
    RAISE EXCEPTION 'The direct-conversation membership uniqueness index is missing or invalid.';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', target_function, 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', target_function, 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', target_function, 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
       ) AS privilege_row
       WHERE procedure_row.oid = target_function
         AND privilege_row.grantee = 0
         AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'The direct-conversation RPC must already match the authenticated-only EXECUTE contract; inspect ACLs before continuing.';
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
  IF peer_department_id IS NULL THEN
    RAISE EXCEPTION 'Direct conversations require a confirmed, active employee assigned to a department.' USING ERRCODE = '42501';
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
DO $postflight$
DECLARE
  target_function regprocedure := 'public.northstar_create_direct_conversation(uuid[])'::regprocedure;
  definition text := pg_catalog.pg_get_functiondef('public.northstar_create_direct_conversation(uuid[])'::regprocedure);
  installed_source text;
  installed_source_sha256 text;
  expected_source_sha256 constant text := '114212fd1159fec1483d13251350f9238441c34be4461cbff76b1aa1ef2f7161';
BEGIN
  SELECT procedure_row.prosrc INTO installed_source
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = target_function;
  installed_source_sha256 := pg_catalog.encode(
    pg_catalog.sha256(
      pg_catalog.convert_to(
        pg_catalog.replace(pg_catalog.replace(installed_source, E'\r\n', E'\n'), E'\r', E'\n'),
        'UTF8'
      )
    ),
    'hex'
  );
  IF installed_source_sha256 <> expected_source_sha256 THEN
    RAISE EXCEPTION 'The installed direct-conversation RPC source does not match the reviewed candidate SHA-256.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS procedure_row
    JOIN pg_catalog.pg_language AS language_row ON language_row.oid = procedure_row.prolang
    WHERE procedure_row.oid = target_function
      AND procedure_row.prorettype = 'uuid'::regtype
      AND language_row.lanname = 'plpgsql'
      AND procedure_row.prosecdef IS TRUE
      AND procedure_row.proowner = 'postgres'::regrole
      AND procedure_row.proconfig @> ARRAY['search_path=""', 'row_security=off']
      AND pg_catalog.cardinality(procedure_row.proconfig) = 2
      AND procedure_row.provolatile = 'v'
      AND procedure_row.proisstrict IS FALSE
      AND procedure_row.proleakproof IS FALSE
      AND procedure_row.proparallel = 'u'
      AND procedure_row.proargnames = ARRAY['p_member_ids']::text[]
      AND procedure_row.proargmodes IS NULL
  ) THEN
    RAISE EXCEPTION 'Direct-conversation RPC owner or SECURITY DEFINER configuration changed unexpectedly.';
  END IF;
  IF definition NOT ILIKE '%actor_department_id IS NULL%'
     OR definition NOT ILIKE '%peer_department_id IS NULL%'
     OR definition ILIKE '%peer_department_id IS DISTINCT FROM actor_department_id%'
     OR definition NOT ILIKE '%registration_completed IS TRUE%'
     OR definition NOT ILIKE '%approval_status::text = ''approved''%'
     OR definition NOT ILIKE '%employment_status::text = ''active''%'
     OR definition NOT ILIKE '%email_confirmed_at IS NOT NULL%'
     OR definition NOT ILIKE '%role::text IN (''employee'', ''manager'')%'
     OR definition NOT ILIKE '%peer_id = actor_id%'
     OR definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR definition NOT ILIKE '%array_agg%'
     OR definition NOT ILIKE '%count(*) = 2%' THEN
    RAISE EXCEPTION 'Direct-conversation RPC body does not match the cross-department eligibility and membership contract.';
  END IF;
  IF NOT pg_catalog.has_function_privilege('authenticated', target_function, 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', target_function, 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', target_function, 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
       ) AS privilege_row
       WHERE procedure_row.oid = target_function
         AND privilege_row.grantee = 0
         AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Direct-conversation RPC EXECUTE permissions do not match the authenticated-only contract.';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indexrelid = pg_catalog.to_regclass('public.northstar_conversation_members_pair_uidx')
      AND index_row.indrelid = 'public.conversation_members'::regclass
      AND index_row.indisunique IS TRUE
      AND index_row.indisvalid IS TRUE
      AND index_row.indpred IS NULL
      AND index_row.indexprs IS NULL
      AND index_row.indnkeyatts = 2
      AND index_row.indnatts = 2
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) = 'conversation_id'
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) = 'user_id'
  ) THEN
    RAISE EXCEPTION 'The direct-conversation membership uniqueness index changed unexpectedly.';
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
