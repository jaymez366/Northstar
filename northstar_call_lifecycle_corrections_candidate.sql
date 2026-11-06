-- NorthStar call lifecycle correction candidate.
-- REVIEW ONLY: this file has not been executed against any database.
-- Run the complete file as one script in an explicitly approved maintenance window.
-- Any error aborts the transaction; issue ROLLBACK if the SQL client leaves it open.
-- The migration changes only the three named function source bodies.

BEGIN;

-- Preflight: require the exact overloads, deployed-source fingerprints, return
-- signatures, security attributes, private search_path, and expected callers.
DO $preflight$
DECLARE
    item record;
    function_oid oid;
    source_md5 text;
    function_owner oid;
    function_acl aclitem[];
    is_security_definer boolean;
    function_config text[];
    language_name name;
    result_signature text;
    public_can_execute boolean;
    current_role_oid oid;
    current_role_superuser boolean;
BEGIN
    SELECT r.oid, r.rolsuper
    INTO current_role_oid, current_role_superuser
    FROM pg_catalog.pg_roles AS r
    WHERE r.rolname = current_user;

    IF current_role_oid IS NULL THEN
        RAISE EXCEPTION 'Preflight failed: current database role could not be resolved.';
    END IF;

    FOR item IN
        SELECT *
        FROM (VALUES
            ('public.northstar_start_call(uuid,text)',
             '36d5a34584fbef853215c930515e011c',
             'TABLE(id uuid, conversation_id uuid, caller_id uuid, callee_id uuid, call_type text, status text, expires_at timestamp with time zone)'),
            ('public.northstar_update_call_status(uuid,text)',
             '05c709a62fd1b21abdac6654a5ddcf0e',
             'TABLE(id uuid, conversation_id uuid, caller_id uuid, callee_id uuid, call_type text, status text, expires_at timestamp with time zone)'),
            ('public.northstar_send_call_signal(uuid,text,jsonb)',
             '242eb74573a8e6df494b9e693937c837',
             'void')
        ) AS expected(signature, fingerprint, result_signature)
    LOOP
        function_oid := pg_catalog.to_regprocedure(item.signature)::oid;
        IF function_oid IS NULL THEN
            RAISE EXCEPTION 'Preflight failed: required function signature is missing: %', item.signature;
        END IF;

        SELECT pg_catalog.md5(p.prosrc), p.proowner, p.proacl,
               p.prosecdef, p.proconfig, l.lanname,
               pg_catalog.pg_get_function_result(p.oid)
        INTO source_md5, function_owner, function_acl,
             is_security_definer, function_config, language_name,
             result_signature
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
        WHERE p.oid = function_oid;

        IF source_md5 IS DISTINCT FROM item.fingerprint THEN
            RAISE EXCEPTION 'Preflight failed: source fingerprint mismatch for % (expected %, found %).',
                item.signature, item.fingerprint, source_md5;
        END IF;

        IF result_signature IS DISTINCT FROM item.result_signature THEN
            RAISE EXCEPTION 'Preflight failed: return signature mismatch for % (expected %, found %).',
                item.signature, item.result_signature, result_signature;
        END IF;

        IF language_name <> 'plpgsql' OR NOT is_security_definer THEN
            RAISE EXCEPTION 'Preflight failed: unexpected language or SECURITY DEFINER setting for %.', item.signature;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_options_to_table(function_config) AS setting
            WHERE setting.option_name = 'search_path'
              AND setting.option_value IN ('', '""')
        ) THEN
            RAISE EXCEPTION 'Preflight failed: empty search_path is not configured for %.', item.signature;
        END IF;

        IF NOT pg_catalog.has_function_privilege('authenticated', function_oid, 'EXECUTE')
           OR NOT pg_catalog.has_function_privilege('service_role', function_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'Preflight failed: authenticated/service_role EXECUTE access is not present for %.', item.signature;
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM pg_catalog.aclexplode(
                COALESCE(function_acl, pg_catalog.acldefault('f', function_owner))
            ) AS acl
            WHERE acl.grantee = 0
              AND acl.privilege_type = 'EXECUTE'
        )
        INTO public_can_execute;

        IF public_can_execute THEN
            RAISE EXCEPTION 'Preflight failed: PUBLIC has EXECUTE on %; refusing to proceed.', item.signature;
        END IF;

        IF NOT current_role_superuser
           AND NOT pg_catalog.pg_has_role(current_role_oid, function_owner, 'MEMBER') THEN
            RAISE EXCEPTION 'Preflight failed: current role must own %, be a member of its owner role, or be a superuser.', item.signature;
        END IF;
    END LOOP;
END;
$preflight$;

-- Apply exact, single-occurrence replacements to pg_proc.prosrc, then pass the
-- resulting source through pg_get_functiondef() so CREATE OR REPLACE retains
-- the live signature and function attributes. All checks are repeated inside
-- the same transaction immediately before each replacement.
DO $apply$
DECLARE
    item record;
    function_oid oid;
    source_text text;
    new_source text;
    function_ddl text;
    old_fragment text;
    new_fragment text;
    fragment_label text;
    occurrence_count integer;
    before_metadata jsonb;
    after_metadata jsonb;
BEGIN
    -- 1. public.northstar_start_call(uuid, text)
    function_oid := pg_catalog.to_regprocedure('public.northstar_start_call(uuid,text)')::oid;
    SELECT p.prosrc INTO source_text FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF pg_catalog.md5(source_text) <> '36d5a34584fbef853215c930515e011c' THEN
        RAISE EXCEPTION 'Apply failed: northstar_start_call fingerprint changed after preflight.';
    END IF;
    new_source := source_text;
    FOR fragment_label, old_fragment, new_fragment IN
        SELECT * FROM (VALUES
            ('refresh time after participant locks',
             $old$END LOOP;

-- Mark expired ringing calls as missed before checking.$old$,
             $new$END LOOP;

v_now := clock_timestamp();

-- Mark expired ringing calls as missed before checking.$new$),
            ('refresh time after cleanup UPDATE',
             $old$OR s.callee_id IN (v_caller, v_callee)
);

IF EXISTS ($old$,
             $new$OR s.callee_id IN (v_caller, v_callee)
);

v_now := clock_timestamp();

IF EXISTS ($new$),
            ('accepted-call active predicate',
             $old$WHERE s.status IN ('ringing', 'accepted')
AND s.expires_at > v_now
AND ($old$,
             $new$WHERE (
s.status = 'accepted'
OR (
s.status = 'ringing'
AND s.expires_at > v_now
)
)
AND ($new$)
        ) AS replacements(label, old_text, new_text)
    LOOP
        occurrence_count := (length(new_source) - length(replace(new_source, old_fragment, ''))) / length(old_fragment);
        IF occurrence_count <> 1 THEN
            RAISE EXCEPTION 'Apply failed: replacement "%" in northstar_start_call matched % occurrences; expected exactly one.',
                fragment_label, occurrence_count;
        END IF;
        new_source := replace(new_source, old_fragment, new_fragment);
    END LOOP;

    SELECT pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO before_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;

    function_ddl := pg_catalog.pg_get_functiondef(function_oid);
    occurrence_count := (length(function_ddl) - length(replace(function_ddl, source_text, ''))) / length(source_text);
    IF occurrence_count <> 1 THEN
        RAISE EXCEPTION 'Apply failed: northstar_start_call source in generated DDL matched % occurrences; expected exactly one.', occurrence_count;
    END IF;
    function_ddl := replace(function_ddl, source_text, new_source);
    EXECUTE function_ddl;

    SELECT p.prosrc, pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO source_text, after_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF source_text IS DISTINCT FROM new_source OR after_metadata IS DISTINCT FROM before_metadata THEN
        RAISE EXCEPTION 'Postflight failed: source or protected attributes changed unexpectedly for northstar_start_call.';
    END IF;

    -- 2. public.northstar_update_call_status(uuid, text)
    function_oid := pg_catalog.to_regprocedure('public.northstar_update_call_status(uuid,text)')::oid;
    SELECT p.prosrc INTO source_text FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF pg_catalog.md5(source_text) <> '05c709a62fd1b21abdac6654a5ddcf0e' THEN
        RAISE EXCEPTION 'Apply failed: northstar_update_call_status fingerprint changed after preflight.';
    END IF;
    new_source := source_text;
    FOR fragment_label, old_fragment, new_fragment IN
        SELECT * FROM (VALUES
            ('expiry-check declaration',
             $old$v_now timestamptz := now();$old$,
             $new$v_now timestamptz := now();
v_expiry_check_now timestamptz;$new$),
            ('expiry timestamp immediately after locked-session check',
             $old$IF NOT FOUND THEN
RAISE EXCEPTION 'Call not found or access denied.'
USING ERRCODE = '42501';
END IF;

-- Expired invitations cannot be accepted or revived.$old$,
             $new$IF NOT FOUND THEN
RAISE EXCEPTION 'Call not found or access denied.'
USING ERRCODE = '42501';
END IF;

v_expiry_check_now := clock_timestamp();

-- Expired invitations cannot be accepted or revived.$new$),
            ('expired-invitation comparison',
             $old$AND v_session.expires_at <= v_now THEN$old$,
             $new$AND v_session.expires_at <= v_expiry_check_now THEN$new$),
            ('missed-action expiry comparison',
             $old$OR v_session.expires_at > v_now THEN$old$,
             $new$OR v_session.expires_at > v_expiry_check_now THEN$new$)
        ) AS replacements(label, old_text, new_text)
    LOOP
        occurrence_count := (length(new_source) - length(replace(new_source, old_fragment, ''))) / length(old_fragment);
        IF occurrence_count <> 1 THEN
            RAISE EXCEPTION 'Apply failed: replacement "%" in northstar_update_call_status matched % occurrences; expected exactly one.',
                fragment_label, occurrence_count;
        END IF;
        new_source := replace(new_source, old_fragment, new_fragment);
    END LOOP;

    SELECT pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO before_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;

    function_ddl := pg_catalog.pg_get_functiondef(function_oid);
    occurrence_count := (length(function_ddl) - length(replace(function_ddl, source_text, ''))) / length(source_text);
    IF occurrence_count <> 1 THEN
        RAISE EXCEPTION 'Apply failed: northstar_update_call_status source in generated DDL matched % occurrences; expected exactly one.', occurrence_count;
    END IF;
    function_ddl := replace(function_ddl, source_text, new_source);
    EXECUTE function_ddl;

    SELECT p.prosrc, pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO source_text, after_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF source_text IS DISTINCT FROM new_source OR after_metadata IS DISTINCT FROM before_metadata THEN
        RAISE EXCEPTION 'Postflight failed: source or protected attributes changed unexpectedly for northstar_update_call_status.';
    END IF;

    -- 3. public.northstar_send_call_signal(uuid, text, jsonb)
    function_oid := pg_catalog.to_regprocedure('public.northstar_send_call_signal(uuid,text,jsonb)')::oid;
    SELECT p.prosrc INTO source_text FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF pg_catalog.md5(source_text) <> '242eb74573a8e6df494b9e693937c837' THEN
        RAISE EXCEPTION 'Apply failed: northstar_send_call_signal fingerprint changed after preflight.';
    END IF;
    new_source := source_text;
    FOR fragment_label, old_fragment, new_fragment IN
        SELECT * FROM (VALUES
            ('expiry-check declaration',
             $old$v_now timestamptz := now();$old$,
             $new$v_now timestamptz := now();
v_expiry_check_now timestamptz;$new$),
            ('expiry timestamp immediately after locked-session check',
             $old$IF NOT FOUND THEN
RAISE EXCEPTION 'Call not found or access denied.'
USING ERRCODE = '42501';
END IF;

IF v_session.status NOT IN ('ringing', 'accepted')$old$,
             $new$IF NOT FOUND THEN
RAISE EXCEPTION 'Call not found or access denied.'
USING ERRCODE = '42501';
END IF;

v_expiry_check_now := clock_timestamp();

IF v_session.status NOT IN ('ringing', 'accepted')$new$),
            ('ringing-signal expiry comparison',
             $old$v_session.expires_at <= v_now$old$,
             $new$v_session.expires_at <= v_expiry_check_now$new$)
        ) AS replacements(label, old_text, new_text)
    LOOP
        occurrence_count := (length(new_source) - length(replace(new_source, old_fragment, ''))) / length(old_fragment);
        IF occurrence_count <> 1 THEN
            RAISE EXCEPTION 'Apply failed: replacement "%" in northstar_send_call_signal matched % occurrences; expected exactly one.',
                fragment_label, occurrence_count;
        END IF;
        new_source := replace(new_source, old_fragment, new_fragment);
    END LOOP;

    SELECT pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO before_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;

    function_ddl := pg_catalog.pg_get_functiondef(function_oid);
    occurrence_count := (length(function_ddl) - length(replace(function_ddl, source_text, ''))) / length(source_text);
    IF occurrence_count <> 1 THEN
        RAISE EXCEPTION 'Apply failed: northstar_send_call_signal source in generated DDL matched % occurrences; expected exactly one.', occurrence_count;
    END IF;
    function_ddl := replace(function_ddl, source_text, new_source);
    EXECUTE function_ddl;

    SELECT p.prosrc, pg_catalog.jsonb_build_object(
        'owner', p.proowner, 'acl', p.proacl, 'security_definer', p.prosecdef,
        'config', p.proconfig, 'language', p.prolang, 'return_type', p.prorettype,
        'return_set', p.proretset, 'argument_types', p.proargtypes::text,
        'all_argument_types', p.proallargtypes, 'argument_modes', p.proargmodes,
        'argument_names', p.proargnames, 'volatility', p.provolatile,
        'strict', p.proisstrict, 'leakproof', p.proleakproof,
        'parallel', p.proparallel,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result', pg_catalog.pg_get_function_result(p.oid)
    ) INTO source_text, after_metadata
    FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;
    IF source_text IS DISTINCT FROM new_source OR after_metadata IS DISTINCT FROM before_metadata THEN
        RAISE EXCEPTION 'Postflight failed: source or protected attributes changed unexpectedly for northstar_send_call_signal.';
    END IF;
END;
$apply$;

-- Final postflight: verify the required edits, function signatures, security
-- attributes, empty search_path, caller access, and absence of PUBLIC EXECUTE.
DO $postflight$
DECLARE
    item record;
    function_oid oid;
    function_source text;
    source_result text;
    function_owner oid;
    function_acl aclitem[];
    function_config text[];
    source_is_security_definer boolean;
    public_can_execute boolean;
BEGIN
    FOR item IN
        SELECT *
        FROM (VALUES
            ('public.northstar_start_call(uuid,text)',
             'TABLE(id uuid, conversation_id uuid, caller_id uuid, callee_id uuid, call_type text, status text, expires_at timestamp with time zone)'),
            ('public.northstar_update_call_status(uuid,text)',
             'TABLE(id uuid, conversation_id uuid, caller_id uuid, callee_id uuid, call_type text, status text, expires_at timestamp with time zone)'),
            ('public.northstar_send_call_signal(uuid,text,jsonb)', 'void')
        ) AS expected(signature, result_signature)
    LOOP
        function_oid := pg_catalog.to_regprocedure(item.signature)::oid;
        IF function_oid IS NULL THEN
            RAISE EXCEPTION 'Postflight failed: function signature disappeared: %.', item.signature;
        END IF;

        SELECT p.prosrc, pg_catalog.pg_get_function_result(p.oid), p.proowner,
               p.proacl, p.proconfig, p.prosecdef
        INTO function_source, source_result, function_owner,
             function_acl, function_config, source_is_security_definer
        FROM pg_catalog.pg_proc AS p WHERE p.oid = function_oid;

        IF source_result IS DISTINCT FROM item.result_signature OR NOT source_is_security_definer THEN
            RAISE EXCEPTION 'Postflight failed: signature or SECURITY DEFINER check failed for %.', item.signature;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_options_to_table(function_config) AS setting
            WHERE setting.option_name = 'search_path' AND setting.option_value IN ('', '""')
        ) THEN
            RAISE EXCEPTION 'Postflight failed: empty search_path check failed for %.', item.signature;
        END IF;
        IF NOT pg_catalog.has_function_privilege('authenticated', function_oid, 'EXECUTE')
           OR NOT pg_catalog.has_function_privilege('service_role', function_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'Postflight failed: expected caller EXECUTE privileges missing for %.', item.signature;
        END IF;
        SELECT EXISTS (
            SELECT 1 FROM pg_catalog.aclexplode(
                COALESCE(function_acl, pg_catalog.acldefault('f', function_owner))
            ) AS acl
            WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
        ) INTO public_can_execute;
        IF public_can_execute THEN
            RAISE EXCEPTION 'Postflight failed: PUBLIC has EXECUTE on %.', item.signature;
        END IF;

        IF item.signature = 'public.northstar_start_call(uuid,text)' THEN
            IF position('v_now := clock_timestamp();' IN function_source) = 0
               OR position('s.status = ''accepted''' IN function_source) = 0
               OR position('s.status = ''ringing''' IN function_source) = 0
               OR position('s.expires_at > v_now' IN function_source) = 0 THEN
                RAISE EXCEPTION 'Postflight failed: start-call lifecycle corrections not found.';
            END IF;
        ELSIF item.signature = 'public.northstar_update_call_status(uuid,text)' THEN
            IF position('v_expiry_check_now timestamptz;' IN function_source) = 0
               OR position('v_expiry_check_now := clock_timestamp();' IN function_source) = 0
               OR position('v_session.expires_at <= v_expiry_check_now' IN function_source) = 0
               OR position('v_session.expires_at > v_expiry_check_now' IN function_source) = 0 THEN
                RAISE EXCEPTION 'Postflight failed: call-status expiry corrections not found.';
            END IF;
        ELSE
            IF position('v_expiry_check_now timestamptz;' IN function_source) = 0
               OR position('v_expiry_check_now := clock_timestamp();' IN function_source) = 0
               OR position('v_session.expires_at <= v_expiry_check_now' IN function_source) = 0 THEN
                RAISE EXCEPTION 'Postflight failed: call-signal expiry correction not found.';
            END IF;
        END IF;
    END LOOP;
END;
$postflight$;

COMMIT;