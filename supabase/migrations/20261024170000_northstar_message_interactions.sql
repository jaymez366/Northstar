-- NorthStar message interactions and private attachment metadata.
-- This migration deliberately fails before changing anything when the core
-- message-send contract or base-table assumptions do not match the frontend.

BEGIN;

DO $preflight$
DECLARE
  missing text[] := ARRAY[]::text[];
  send_oid oid;
  send_result text;
  send_return_type oid;
  send_returns_set boolean;
  required_column record;
  message_request_key_exists boolean;
BEGIN
  IF to_regclass('public.messages') IS NULL THEN
    missing := array_append(missing, 'public.messages');
  END IF;
  IF to_regclass('public.conversations') IS NULL THEN
    missing := array_append(missing, 'public.conversations');
  END IF;
  IF to_regclass('public.conversation_members') IS NULL THEN
    missing := array_append(missing, 'public.conversation_members');
  END IF;

  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; missing: %', array_to_string(missing, ', ');
  END IF;

  SELECT p.oid, pg_catalog.pg_get_function_result(p.oid), p.prorettype, p.proretset
  INTO send_oid, send_result, send_return_type, send_returns_set
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'northstar_send_message'
    AND p.proargtypes = '2950 25 2950'::oidvector;

  IF send_oid IS NULL THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; expected public.northstar_send_message(uuid,text,uuid)';
  END IF;
  IF NOT send_returns_set OR send_return_type <> 'public.messages'::regtype THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; expected northstar_send_message to return SETOF public.messages (actual: %)', send_result;
  END IF;
  IF NOT pg_catalog.has_function_privilege('authenticated', send_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; authenticated must already be allowed to execute public.northstar_send_message(uuid,text,uuid)';
  END IF;
  IF pg_catalog.to_regprocedure('public.has_any_role(text[])') IS NULL THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; required active-role helper public.has_any_role(text[]) is missing';
  END IF;

  FOR required_column IN
    SELECT * FROM (VALUES
      ('id', 'uuid'::regtype),
      ('content', 'text'::regtype),
      ('created_at', 'timestamptz'::regtype),
      ('edited_at', 'timestamptz'::regtype),
      ('deleted_at', 'timestamptz'::regtype),
      ('content_version', 'integer'::regtype),
      ('client_request_id', 'uuid'::regtype)
    ) AS expected(name, type_oid)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = 'public.messages'::regclass
        AND attname = required_column.name
        AND atttypid = required_column.type_oid
        AND NOT attisdropped
    ) THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; northstar_send_message result is missing or has the wrong type for % (actual: %)', required_column.name, send_result;
    END IF;
  END LOOP;

  FOR required_column IN
    SELECT * FROM (VALUES
      ('id', 'uuid'::regtype), ('conversation_id', 'uuid'::regtype),
      ('sender_id', 'uuid'::regtype), ('content', 'text'::regtype),
      ('created_at', 'timestamptz'::regtype), ('edited_at', 'timestamptz'::regtype),
      ('deleted_at', 'timestamptz'::regtype), ('content_version', 'integer'::regtype),
      ('client_request_id', 'uuid'::regtype)
    ) AS expected(name, type_oid)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = 'public.messages'::regclass AND attname = required_column.name
        AND atttypid = required_column.type_oid AND NOT attisdropped
    ) THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; public.messages is missing or has an incompatible column %', required_column.name;
    END IF;
  END LOOP;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = 'public.messages'::regclass
      AND index_row.indisunique
      AND index_row.indisvalid
      AND index_row.indisready
      AND index_row.indislive
      AND index_row.indimmediate
      AND NOT index_row.indisexclusion
      AND index_row.indnkeyatts = 2
      AND pg_catalog.regexp_replace(
        pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)),
        '[[:space:]()"]', '', 'g'
      ) = 'client_request_idisnotnull'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS index_class
        JOIN pg_catalog.pg_am AS access_method ON access_method.oid = index_class.relam
        WHERE index_class.oid = index_row.indexrelid
          AND access_method.amname = 'btree'
      )
      AND (
        SELECT pg_catalog.array_agg(attribute.attname::text ORDER BY key_column.ordinality)
        FROM pg_catalog.unnest(index_row.indkey) WITH ORDINALITY AS key_column(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = index_row.indrelid
         AND attribute.attnum = key_column.attnum
        WHERE key_column.ordinality <= index_row.indnkeyatts
      ) IN (
        ARRAY['sender_id', 'client_request_id']::text[],
        ARRAY['client_request_id', 'sender_id']::text[]
      )
  ) INTO message_request_key_exists;

  -- PostgreSQL conflict-target inference is order-independent, so either key
  -- order is valid. Require precisely these two key columns; INCLUDE columns
  -- are harmless and are not part of indnkeyatts.
  IF NOT message_request_key_exists THEN
    SELECT EXISTS (
      SELECT 1 FROM public.messages
      WHERE client_request_id IS NOT NULL
      GROUP BY sender_id, client_request_id
      HAVING pg_catalog.count(*) > 1
    ) INTO message_request_key_exists;
    IF message_request_key_exists THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; duplicate non-null (sender_id, client_request_id) values prevent creating the sender idempotency index';
    END IF;
    IF pg_catalog.to_regclass('public.messages_sender_client_request_id_interaction_uidx') IS NOT NULL THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; the required idempotency index name is already occupied by an incompatible object';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class
    WHERE oid IN ('public.conversation_members'::regclass, 'public.messages'::regclass)
      AND relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; postgres-owned membership helpers require the core tables not to FORCE ROW LEVEL SECURITY';
  END IF;

  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; Supabase Storage catalog is unavailable';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; required publication supabase_realtime does not exist';
  END IF;

  IF to_regclass('public.message_replies') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = 'public.message_replies'::regclass
        AND attname = 'request_content'
        AND atttypid = 'text'::regtype
        AND attnotnull
        AND NOT attisdropped
    ) THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; existing public.message_replies lacks the required NOT NULL request_content column';
    END IF;
  END IF;

  IF to_regclass('public.message_attachments') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = 'public.message_attachments'::regclass
        AND attname = 'request_content'
        AND atttypid = 'text'::regtype
        AND attnotnull
        AND NOT attisdropped
    ) THEN
      RAISE EXCEPTION 'Northstar message-interactions preflight failed; existing public.message_attachments lacks the required NOT NULL request_content column';
    END IF;
  END IF;

  IF pg_catalog.to_regprocedure('northstar_private.capture_interaction_message_insert()') IS NOT NULL
     OR pg_catalog.to_regclass('northstar_private.interaction_message_insert_markers') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger
       WHERE tgrelid = 'public.messages'::regclass
         AND tgname = 'northstar_capture_interaction_message_insert'
         AND NOT tgisinternal
     ) THEN
    RAISE EXCEPTION 'Northstar message-interactions preflight failed; interaction-insert marker function or trigger name already exists';
  END IF;

  IF NOT message_request_key_exists THEN
    EXECUTE 'CREATE UNIQUE INDEX public.messages_sender_client_request_id_interaction_uidx '
      || 'ON public.messages USING btree (sender_id, client_request_id) '
      || 'WHERE client_request_id IS NOT NULL';
  END IF;
END;
$preflight$;

CREATE SCHEMA IF NOT EXISTS northstar_private;
GRANT USAGE ON SCHEMA northstar_private TO authenticated;

CREATE TABLE northstar_private.interaction_message_insert_markers (
  request_token uuid PRIMARY KEY,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE
);
ALTER TABLE northstar_private.interaction_message_insert_markers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON northstar_private.interaction_message_insert_markers FROM PUBLIC, anon, authenticated;

-- The existing sender returns the same row on an idempotent retry. This
-- transaction-local marker lets the wrappers distinguish a message inserted
-- by this invocation from a pre-existing message returned by the sender,
-- without relying on xmin or transaction IDs.
CREATE FUNCTION northstar_private.capture_interaction_message_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  request_token text;
BEGIN
  request_token := pg_catalog.current_setting('northstar.interaction_request_token', true);
  IF request_token ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
    INSERT INTO northstar_private.interaction_message_insert_markers(request_token, message_id)
    VALUES (request_token::uuid, NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION northstar_private.capture_interaction_message_insert() OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.capture_interaction_message_insert() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER northstar_capture_interaction_message_insert
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION northstar_private.capture_interaction_message_insert();

CREATE OR REPLACE FUNCTION northstar_private.is_conversation_member(p_conversation_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.conversation_members AS member
    WHERE member.conversation_id = p_conversation_id
      AND member.user_id = auth.uid()
  );
$function$;
ALTER FUNCTION northstar_private.is_conversation_member(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_conversation_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_conversation_member(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.is_message_member(p_message_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.messages AS message
    JOIN public.conversation_members AS member
      ON member.conversation_id = message.conversation_id
     AND member.user_id = auth.uid()
    WHERE message.id = p_message_id
  );
$function$;
ALTER FUNCTION northstar_private.is_message_member(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.is_message_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.is_message_member(uuid) TO authenticated;

CREATE TABLE IF NOT EXISTS public.message_replies (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  reply_to_message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_request_id uuid NOT NULL,
  request_content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT message_replies_not_self CHECK (message_id <> reply_to_message_id),
  CONSTRAINT message_replies_sender_request_key UNIQUE (sender_id, client_request_id)
);
CREATE INDEX IF NOT EXISTS message_replies_target_idx ON public.message_replies(reply_to_message_id);
ALTER TABLE public.message_replies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_replies FROM PUBLIC, anon, authenticated;
GRANT SELECT (message_id, reply_to_message_id, created_at)
ON public.message_replies TO authenticated;
DROP POLICY IF EXISTS northstar_message_replies_member_read ON public.message_replies;
CREATE POLICY northstar_message_replies_member_read
ON public.message_replies FOR SELECT TO authenticated
USING (northstar_private.is_message_member(message_id));
CREATE OR REPLACE FUNCTION northstar_private.get_my_reply_request(p_client_request_id uuid)
RETURNS TABLE(message_id uuid, reply_to_message_id uuid, request_content text, conversation_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT reply.message_id, reply.reply_to_message_id, reply.request_content, message.conversation_id
  FROM public.message_replies AS reply
  JOIN public.messages AS message ON message.id = reply.message_id
  WHERE reply.sender_id = auth.uid()
    AND reply.client_request_id = p_client_request_id
    AND auth.uid() IS NOT NULL;
$function$;
ALTER FUNCTION northstar_private.get_my_reply_request(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.get_my_reply_request(uuid) FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS northstar_message_replies_sender_insert ON public.message_replies;

CREATE OR REPLACE FUNCTION public.northstar_send_message_reply(
  p_conversation_id uuid,
  p_content text,
  p_client_request_id uuid,
  p_reply_to_message_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  sent jsonb;
  sent_id uuid;
  sent_created_at timestamptz;
  request_token_value uuid;
  inserted_message_id uuid;
  previous_request_token text;
  normalized_content text;
  existing_reply uuid;
  existing_content text;
  existing_message uuid;
  existing_conversation uuid;
  prior_message public.messages%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.has_any_role(ARRAY['employee', 'manager', 'admin']::text[])
     OR NOT northstar_private.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'You are not a member of this conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_client_request_id IS NULL OR p_reply_to_message_id IS NULL THEN
    RAISE EXCEPTION 'A request ID and reply target are required.' USING ERRCODE = '22023';
  END IF;
  normalized_content := pg_catalog.btrim(COALESCE(p_content, ''));
  IF pg_catalog.char_length(normalized_content) NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'Message content must contain 1 to 10000 characters.' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(auth.uid()::text || ':' || p_client_request_id::text, 0)
  );
  SELECT request.message_id, request.reply_to_message_id, request.request_content, request.conversation_id
  INTO existing_message, existing_reply, existing_content, existing_conversation
  FROM northstar_private.get_my_reply_request(p_client_request_id) AS request;
  IF FOUND THEN
    IF existing_reply IS DISTINCT FROM p_reply_to_message_id OR existing_content IS DISTINCT FROM normalized_content
       OR existing_conversation IS DISTINCT FROM p_conversation_id THEN
      RAISE EXCEPTION 'This send request ID was already used with different message or reply content.' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.messages AS target
      WHERE target.id = existing_reply AND target.conversation_id = p_conversation_id
    ) THEN
      RAISE EXCEPTION 'The original reply target is no longer available in this conversation.' USING ERRCODE = '22023';
    END IF;
    SELECT message.* INTO prior_message
    FROM public.messages AS message
    WHERE message.id = existing_message
      AND message.conversation_id = p_conversation_id
      AND message.sender_id = auth.uid()
      AND message.client_request_id = p_client_request_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'The previously sent reply is unavailable.' USING ERRCODE = '22023';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'id', prior_message.id, 'content', prior_message.content,
      'created_at', prior_message.created_at, 'edited_at', prior_message.edited_at,
      'deleted_at', prior_message.deleted_at, 'content_version', prior_message.content_version
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.messages AS prior
    WHERE prior.sender_id = auth.uid() AND prior.client_request_id = p_client_request_id
  ) THEN
    RAISE EXCEPTION 'This request ID already belongs to a message without matching reply metadata.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.messages AS target
    WHERE target.id = p_reply_to_message_id
      AND target.conversation_id = p_conversation_id
      AND target.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'The reply target is unavailable in this conversation.' USING ERRCODE = '22023';
  END IF;

  request_token_value := pg_catalog.gen_random_uuid();
  previous_request_token := pg_catalog.current_setting('northstar.interaction_request_token', true);
  PERFORM pg_catalog.set_config('northstar.interaction_request_token', request_token_value::text, true);

  EXECUTE 'SELECT pg_catalog.to_jsonb(sent) FROM public.northstar_send_message($1, $2, $3) AS sent'
    INTO sent USING p_conversation_id, normalized_content, p_client_request_id;
  sent_id := NULLIF(sent ->> 'id', '')::uuid;
  sent_created_at := NULLIF(sent ->> 'created_at', '')::timestamptz;
  SELECT marker.message_id INTO inserted_message_id
  FROM northstar_private.interaction_message_insert_markers AS marker
  WHERE marker.request_token = request_token_value;
  DELETE FROM northstar_private.interaction_message_insert_markers AS marker
  WHERE marker.request_token = request_token_value;
  PERFORM pg_catalog.set_config('northstar.interaction_request_token', COALESCE(previous_request_token, ''), true);
  IF sent_id IS NULL OR sent_created_at IS NULL OR NULLIF(sent ->> 'content', '') IS NULL
     OR inserted_message_id IS DISTINCT FROM sent_id THEN
    RAISE EXCEPTION 'The sender returned a pre-existing or invalid message; reply metadata was not created.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.messages AS sent_row
    WHERE sent_row.id = sent_id
      AND sent_row.conversation_id = p_conversation_id
      AND sent_row.sender_id = auth.uid()
      AND sent_row.client_request_id = p_client_request_id
      AND sent_row.content = normalized_content
  ) THEN
    RAISE EXCEPTION 'The sender returned a message that does not match this reply request.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.message_replies(message_id, reply_to_message_id, sender_id, client_request_id, request_content)
  VALUES (sent_id, p_reply_to_message_id, auth.uid(), p_client_request_id, normalized_content)
  ON CONFLICT (message_id) DO NOTHING;

  SELECT request.message_id, request.reply_to_message_id, request.request_content, request.conversation_id
  INTO existing_message, existing_reply, existing_content, existing_conversation
  FROM northstar_private.get_my_reply_request(p_client_request_id) AS request;
  IF existing_message IS DISTINCT FROM sent_id OR existing_reply IS DISTINCT FROM p_reply_to_message_id
     OR existing_content IS DISTINCT FROM normalized_content OR existing_conversation IS DISTINCT FROM p_conversation_id THEN
    RAISE EXCEPTION 'This send request was already used with a different reply target.' USING ERRCODE = '22023';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'id', sent_id, 'content', sent ->> 'content',
    'created_at', (sent ->> 'created_at')::timestamptz,
    'edited_at', NULLIF(sent ->> 'edited_at', '')::timestamptz,
    'deleted_at', NULLIF(sent ->> 'deleted_at', '')::timestamptz,
    'content_version', (sent ->> 'content_version')::integer
  );
END;
$function$;
ALTER FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_send_message_reply(uuid, text, uuid, uuid) TO authenticated;

CREATE TABLE IF NOT EXISTS public.message_reactions (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT message_reactions_message_user_emoji_key UNIQUE (message_id, user_id, emoji)
);
ALTER TABLE public.message_reactions DROP CONSTRAINT IF EXISTS message_reactions_emoji_check;
ALTER TABLE public.message_reactions ADD CONSTRAINT message_reactions_emoji_check
  CHECK (emoji IN ('👍', '❤️', '😂', '😮', '😢', '🙏'));
CREATE INDEX IF NOT EXISTS message_reactions_user_message_idx ON public.message_reactions(user_id, message_id);
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_reactions FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.message_reactions TO authenticated;
DROP POLICY IF EXISTS northstar_message_reactions_member_read ON public.message_reactions;
CREATE POLICY northstar_message_reactions_member_read
ON public.message_reactions FOR SELECT TO authenticated
USING (northstar_private.is_message_member(message_id));
DROP POLICY IF EXISTS northstar_message_reactions_self_insert ON public.message_reactions;
CREATE POLICY northstar_message_reactions_self_insert
ON public.message_reactions FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()) AND northstar_private.is_message_member(message_id));
DROP POLICY IF EXISTS northstar_message_reactions_self_delete ON public.message_reactions;
CREATE POLICY northstar_message_reactions_self_delete
ON public.message_reactions FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()) AND northstar_private.is_message_member(message_id));

CREATE TABLE IF NOT EXISTS public.northstar_conversation_user_state (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  archived_at timestamptz,
  unread_override boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (conversation_id, user_id)
);
ALTER TABLE public.northstar_conversation_user_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_conversation_user_state FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.northstar_conversation_user_state TO authenticated;
DROP POLICY IF EXISTS northstar_conversation_user_state_self_read ON public.northstar_conversation_user_state;
CREATE POLICY northstar_conversation_user_state_self_read
ON public.northstar_conversation_user_state FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()) AND northstar_private.is_conversation_member(conversation_id));

CREATE OR REPLACE FUNCTION public.northstar_update_conversation_user_state(
  p_conversation_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT northstar_private.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'You are not a member of this conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('archive', 'restore', 'mark_unread', 'mark_read') THEN
    RAISE EXCEPTION 'Unsupported conversation state action.' USING ERRCODE = '22023';
  END IF;

  IF p_action = 'mark_read' THEN
    UPDATE public.conversation_members
    SET last_read_at = pg_catalog.now()
    WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
    INSERT INTO public.northstar_conversation_user_state(conversation_id, user_id, unread_override, updated_at)
    VALUES (p_conversation_id, auth.uid(), false, pg_catalog.now())
    ON CONFLICT (conversation_id, user_id) DO UPDATE
      SET unread_override = false, updated_at = EXCLUDED.updated_at;
  ELSIF p_action = 'archive' THEN
    INSERT INTO public.northstar_conversation_user_state(conversation_id, user_id, archived_at, updated_at)
    VALUES (p_conversation_id, auth.uid(), pg_catalog.now(), pg_catalog.now())
    ON CONFLICT (conversation_id, user_id) DO UPDATE
      SET archived_at = EXCLUDED.archived_at, updated_at = EXCLUDED.updated_at;
  ELSIF p_action = 'restore' THEN
    INSERT INTO public.northstar_conversation_user_state(conversation_id, user_id, archived_at, updated_at)
    VALUES (p_conversation_id, auth.uid(), NULL, pg_catalog.now())
    ON CONFLICT (conversation_id, user_id) DO UPDATE
      SET archived_at = NULL, updated_at = EXCLUDED.updated_at;
  ELSE
    INSERT INTO public.northstar_conversation_user_state(conversation_id, user_id, unread_override, updated_at)
    VALUES (p_conversation_id, auth.uid(), true, pg_catalog.now())
    ON CONFLICT (conversation_id, user_id) DO UPDATE
      SET unread_override = true, updated_at = EXCLUDED.updated_at;
  END IF;
END;
$function$;
ALTER FUNCTION public.northstar_update_conversation_user_state(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_update_conversation_user_state(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_update_conversation_user_state(uuid, text) TO authenticated;

CREATE TABLE IF NOT EXISTS public.northstar_conversation_message_pins (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (conversation_id, message_id, user_id)
);
CREATE INDEX IF NOT EXISTS northstar_conversation_message_pins_user_idx ON public.northstar_conversation_message_pins(user_id, conversation_id);
ALTER TABLE public.northstar_conversation_message_pins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_conversation_message_pins FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.northstar_conversation_message_pins TO authenticated;
DROP POLICY IF EXISTS northstar_conversation_message_pins_self_read ON public.northstar_conversation_message_pins;
CREATE POLICY northstar_conversation_message_pins_self_read
ON public.northstar_conversation_message_pins FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()) AND northstar_private.is_conversation_member(conversation_id));

CREATE OR REPLACE FUNCTION public.northstar_set_conversation_message_pin(
  p_conversation_id uuid,
  p_message_id uuid,
  p_is_pinned boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT northstar_private.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'You are not a member of this conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_is_pinned IS NULL THEN
    RAISE EXCEPTION 'Pin state is required.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.messages AS message
    WHERE message.id = p_message_id AND message.conversation_id = p_conversation_id
  ) THEN
    RAISE EXCEPTION 'The message is not in this conversation.' USING ERRCODE = '22023';
  END IF;
  IF p_is_pinned THEN
    INSERT INTO public.northstar_conversation_message_pins(conversation_id, message_id, user_id)
    VALUES (p_conversation_id, p_message_id, auth.uid()) ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.northstar_conversation_message_pins
    WHERE conversation_id = p_conversation_id AND message_id = p_message_id AND user_id = auth.uid();
  END IF;
END;
$function$;
ALTER FUNCTION public.northstar_set_conversation_message_pin(uuid, uuid, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_set_conversation_message_pin(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_set_conversation_message_pin(uuid, uuid, boolean) TO authenticated;

CREATE TABLE IF NOT EXISTS public.northstar_conversation_typing (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS northstar_conversation_typing_expiry_idx ON public.northstar_conversation_typing(expires_at);
ALTER TABLE public.northstar_conversation_typing ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_conversation_typing FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.northstar_conversation_typing TO authenticated;
DROP POLICY IF EXISTS northstar_conversation_typing_member_read ON public.northstar_conversation_typing;
CREATE POLICY northstar_conversation_typing_member_read
ON public.northstar_conversation_typing FOR SELECT TO authenticated
USING (northstar_private.is_conversation_member(conversation_id) AND expires_at > pg_catalog.now());

CREATE OR REPLACE FUNCTION public.northstar_set_conversation_typing(
  p_conversation_id uuid,
  p_is_typing boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT northstar_private.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'You are not a member of this conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_is_typing IS NULL THEN
    RAISE EXCEPTION 'Typing state is required.' USING ERRCODE = '22023';
  END IF;
  DELETE FROM public.northstar_conversation_typing WHERE expires_at <= pg_catalog.now();
  IF p_is_typing THEN
    INSERT INTO public.northstar_conversation_typing(conversation_id, user_id, expires_at, updated_at)
    VALUES (p_conversation_id, auth.uid(), pg_catalog.now() + interval '8 seconds', pg_catalog.now())
    ON CONFLICT (conversation_id, user_id) DO UPDATE
      SET expires_at = EXCLUDED.expires_at, updated_at = EXCLUDED.updated_at
      WHERE northstar_conversation_typing.expires_at <= pg_catalog.now() - interval '2 seconds';
  ELSE
    DELETE FROM public.northstar_conversation_typing
    WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
  END IF;
END;
$function$;
ALTER FUNCTION public.northstar_set_conversation_typing(uuid, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_set_conversation_typing(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_set_conversation_typing(uuid, boolean) TO authenticated;

CREATE TABLE IF NOT EXISTS public.message_attachments (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  uploaded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_request_id uuid NOT NULL,
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 26214400),
  duration_seconds integer,
  request_content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT message_attachments_request_key UNIQUE (uploaded_by, client_request_id),
  CONSTRAINT message_attachments_duration_check CHECK (duration_seconds IS NULL OR duration_seconds BETWEEN 1 AND 300),
  CONSTRAINT message_attachments_mime_check CHECK (mime_type IN (
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm',
    'application/pdf', 'text/plain', 'text/csv', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav'
  ))
);
CREATE INDEX IF NOT EXISTS message_attachments_message_idx ON public.message_attachments(message_id);
ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_attachments FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, message_id, storage_path, file_name, mime_type, size_bytes, duration_seconds, created_at)
ON public.message_attachments TO authenticated;
DROP POLICY IF EXISTS northstar_message_attachments_member_read ON public.message_attachments;
CREATE POLICY northstar_message_attachments_member_read
ON public.message_attachments FOR SELECT TO authenticated
USING (northstar_private.is_conversation_member(conversation_id));
DROP POLICY IF EXISTS northstar_message_attachments_sender_insert ON public.message_attachments;

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
  IF auth.uid() IS NULL OR pg_catalog.array_length(pg_catalog.string_to_array(p_path, '/'), 1) <> 3 THEN RETURN false; END IF;
  IF pg_catalog.split_part(p_path, '/', 1) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
     OR pg_catalog.split_part(p_path, '/', 2) <> auth.uid()::text
     OR pg_catalog.split_part(p_path, '/', 3) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\.(jpg|png|gif|webp|mp4|webm|pdf|txt|csv|doc|docx|xls|xlsx|ppt|pptx|ogg|m4a|mp3|wav)$' THEN
    RETURN false;
  END IF;
  path_conversation := pg_catalog.split_part(p_path, '/', 1)::uuid;
  path_user := pg_catalog.split_part(p_path, '/', 2)::uuid;
  RETURN path_user = auth.uid() AND northstar_private.is_conversation_member(path_conversation);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN false;
END;
$function$;
ALTER FUNCTION northstar_private.message_attachment_path_allowed(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.message_attachment_path_allowed(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.message_attachment_path_allowed(text) TO authenticated;

CREATE OR REPLACE FUNCTION northstar_private.message_attachment_object_readable(p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.message_attachments AS attachment
    JOIN public.conversation_members AS member
      ON member.conversation_id = attachment.conversation_id
     AND member.user_id = auth.uid()
    WHERE attachment.storage_path = p_path
  );
$function$;
ALTER FUNCTION northstar_private.message_attachment_object_readable(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.message_attachment_object_readable(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.message_attachment_object_readable(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.northstar_send_message_attachment(
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
AS $function$
DECLARE
  sent jsonb;
  sent_id uuid;
  sent_created_at timestamptz;
  request_token_value uuid;
  inserted_message_id uuid;
  previous_request_token text;
  expected_extension text;
  actual_attachment public.message_attachments%ROWTYPE;
  prior_message public.messages%ROWTYPE;
  message_content text;
BEGIN
  -- This validates the declared MIME type and Storage's configured allowlist;
  -- it does not inspect file signatures. Production deployments needing content
  -- authenticity must scan file bytes in a trusted server-side service.
  IF auth.uid() IS NULL
     OR NOT public.has_any_role(ARRAY['employee', 'manager', 'admin']::text[])
     OR NOT northstar_private.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'You are not a member of this conversation.' USING ERRCODE = '42501';
  END IF;
  IF p_client_request_id IS NULL
     OR p_file_name IS NULL OR pg_catalog.length(p_file_name) NOT BETWEEN 1 AND 180
     OR p_caption IS NULL OR pg_catalog.length(p_caption) > 4000
     OR p_size_bytes IS NULL OR p_size_bytes NOT BETWEEN 1 AND 26214400 THEN
    RAISE EXCEPTION 'Invalid attachment metadata.' USING ERRCODE = '22023';
  END IF;
  expected_extension := CASE p_mime_type
    WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/gif' THEN 'gif' WHEN 'image/webp' THEN 'webp'
    WHEN 'video/mp4' THEN 'mp4' WHEN 'video/webm' THEN 'webm'
    WHEN 'application/pdf' THEN 'pdf' WHEN 'text/plain' THEN 'txt' WHEN 'text/csv' THEN 'csv'
    WHEN 'application/msword' THEN 'doc'
    WHEN 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' THEN 'docx'
    WHEN 'application/vnd.ms-excel' THEN 'xls'
    WHEN 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' THEN 'xlsx'
    WHEN 'application/vnd.ms-powerpoint' THEN 'ppt'
    WHEN 'application/vnd.openxmlformats-officedocument.presentationml.presentation' THEN 'pptx'
    WHEN 'audio/webm' THEN 'webm' WHEN 'audio/ogg' THEN 'ogg' WHEN 'audio/mp4' THEN 'm4a'
    WHEN 'audio/mpeg' THEN 'mp3' WHEN 'audio/wav' THEN 'wav'
    ELSE NULL END;
  IF expected_extension IS NULL
     OR p_storage_path IS DISTINCT FROM p_conversation_id::text || '/' || auth.uid()::text || '/' || p_client_request_id::text || '.' || expected_extension
     OR (p_mime_type IN ('audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav')
         AND (p_size_bytes > 10485760 OR p_duration_seconds IS NULL OR p_duration_seconds NOT BETWEEN 1 AND 300))
     OR (p_mime_type NOT IN ('audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav') AND p_duration_seconds IS NOT NULL) THEN
    RAISE EXCEPTION 'Attachment type, path, size, or duration is invalid.' USING ERRCODE = '22023';
  END IF;
  message_content := COALESCE(NULLIF(pg_catalog.btrim(p_caption), ''), '[Attachment]');

  -- Serialize retries of one authenticated request. A successful retry returns
  -- the original message and never calls the base sender a second time.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(auth.uid()::text || ':' || p_client_request_id::text, 0)
  );
  SELECT * INTO actual_attachment FROM public.message_attachments
  WHERE uploaded_by = auth.uid() AND client_request_id = p_client_request_id;
  IF FOUND THEN
    IF actual_attachment.conversation_id IS DISTINCT FROM p_conversation_id
       OR actual_attachment.storage_path IS DISTINCT FROM p_storage_path
       OR actual_attachment.file_name IS DISTINCT FROM p_file_name
       OR actual_attachment.mime_type IS DISTINCT FROM p_mime_type
       OR actual_attachment.size_bytes IS DISTINCT FROM p_size_bytes
       OR actual_attachment.duration_seconds IS DISTINCT FROM p_duration_seconds
       OR actual_attachment.request_content IS DISTINCT FROM message_content THEN
      RAISE EXCEPTION 'This attachment request ID was already used with different attachment data.' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO prior_message FROM public.messages WHERE id = actual_attachment.message_id;
    IF NOT FOUND OR prior_message.sender_id <> auth.uid()
       OR prior_message.conversation_id IS DISTINCT FROM p_conversation_id
       OR prior_message.client_request_id IS DISTINCT FROM p_client_request_id THEN
      RAISE EXCEPTION 'The previously sent attachment message is unavailable.' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM storage.objects AS object
      WHERE object.bucket_id = 'northstar-message-attachments'
        AND object.name = actual_attachment.storage_path
    ) THEN
      RAISE EXCEPTION 'The previously sent attachment object is unavailable.' USING ERRCODE = '22023';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'id', prior_message.id, 'content', prior_message.content,
      'created_at', prior_message.created_at, 'edited_at', prior_message.edited_at,
      'deleted_at', prior_message.deleted_at, 'content_version', prior_message.content_version
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.messages AS prior
    WHERE prior.sender_id = auth.uid() AND prior.client_request_id = p_client_request_id
  ) THEN
    RAISE EXCEPTION 'This request ID already belongs to a message without matching attachment metadata.' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM storage.objects AS object
    WHERE object.bucket_id = 'northstar-message-attachments'
      AND object.name = p_storage_path
  ) THEN
    RAISE EXCEPTION 'The uploaded attachment object was not found in the private message bucket.' USING ERRCODE = '22023';
  END IF;

  request_token_value := pg_catalog.gen_random_uuid();
  previous_request_token := pg_catalog.current_setting('northstar.interaction_request_token', true);
  PERFORM pg_catalog.set_config('northstar.interaction_request_token', request_token_value::text, true);
  EXECUTE 'SELECT pg_catalog.to_jsonb(sent) FROM public.northstar_send_message($1, $2, $3) AS sent'
    INTO sent USING p_conversation_id, message_content, p_client_request_id;
  sent_id := NULLIF(sent ->> 'id', '')::uuid;
  sent_created_at := NULLIF(sent ->> 'created_at', '')::timestamptz;
  SELECT marker.message_id INTO inserted_message_id
  FROM northstar_private.interaction_message_insert_markers AS marker
  WHERE marker.request_token = request_token_value;
  DELETE FROM northstar_private.interaction_message_insert_markers AS marker
  WHERE marker.request_token = request_token_value;
  PERFORM pg_catalog.set_config('northstar.interaction_request_token', COALESCE(previous_request_token, ''), true);
  IF sent_id IS NULL OR sent_created_at IS NULL OR inserted_message_id IS DISTINCT FROM sent_id THEN
    RAISE EXCEPTION 'The sender returned a pre-existing or invalid message; attachment metadata was not created.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.messages AS sent_row
    WHERE sent_row.id = sent_id
      AND sent_row.conversation_id = p_conversation_id
      AND sent_row.sender_id = auth.uid()
      AND sent_row.client_request_id = p_client_request_id
      AND sent_row.content = message_content
  ) THEN
    RAISE EXCEPTION 'The sender returned a message that does not match this attachment request.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.message_attachments(
    message_id, conversation_id, uploaded_by, client_request_id, storage_path,
    file_name, mime_type, size_bytes, duration_seconds, request_content
  ) VALUES (
    sent_id, p_conversation_id, auth.uid(), p_client_request_id, p_storage_path,
    p_file_name, p_mime_type, p_size_bytes, p_duration_seconds, message_content
  ) ON CONFLICT (uploaded_by, client_request_id) DO NOTHING;

  SELECT * INTO actual_attachment FROM public.message_attachments
  WHERE uploaded_by = auth.uid() AND client_request_id = p_client_request_id;
  IF actual_attachment.message_id IS DISTINCT FROM sent_id
     OR actual_attachment.conversation_id IS DISTINCT FROM p_conversation_id
     OR actual_attachment.storage_path IS DISTINCT FROM p_storage_path
     OR actual_attachment.file_name IS DISTINCT FROM p_file_name
     OR actual_attachment.mime_type IS DISTINCT FROM p_mime_type
     OR actual_attachment.size_bytes IS DISTINCT FROM p_size_bytes
     OR actual_attachment.duration_seconds IS DISTINCT FROM p_duration_seconds
     OR actual_attachment.request_content IS DISTINCT FROM message_content THEN
    RAISE EXCEPTION 'This attachment request ID was already used with different attachment data.' USING ERRCODE = '22023';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'id', sent_id, 'content', sent ->> 'content',
    'created_at', (sent ->> 'created_at')::timestamptz,
    'edited_at', NULLIF(sent ->> 'edited_at', '')::timestamptz,
    'deleted_at', NULLIF(sent ->> 'deleted_at', '')::timestamptz,
    'content_version', (sent ->> 'content_version')::integer
  );
END;
$function$;
ALTER FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_send_message_attachment(uuid, text, text, text, bigint, text, uuid, integer) TO authenticated;

DO $bucket$
BEGIN
  INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'northstar-message-attachments', 'northstar-message-attachments', false, 26214400,
    ARRAY[
      'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm',
      'application/pdf', 'text/plain', 'text/csv', 'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav'
    ]::text[]
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;
END;
$bucket$;

DROP POLICY IF EXISTS northstar_message_attachments_upload_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_upload_guard
ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (bucket_id <> 'northstar-message-attachments' OR northstar_private.message_attachment_path_allowed(name));
DROP POLICY IF EXISTS northstar_message_attachments_upload ON storage.objects;
CREATE POLICY northstar_message_attachments_upload
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'northstar-message-attachments' AND northstar_private.message_attachment_path_allowed(name));
DROP POLICY IF EXISTS northstar_message_attachments_read_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_read_guard
ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
USING (bucket_id <> 'northstar-message-attachments' OR northstar_private.message_attachment_object_readable(name));
DROP POLICY IF EXISTS northstar_message_attachments_read ON storage.objects;
CREATE POLICY northstar_message_attachments_read
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'northstar-message-attachments' AND northstar_private.message_attachment_object_readable(name));
DROP POLICY IF EXISTS northstar_message_attachments_anon_read_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_anon_read_guard
ON storage.objects AS RESTRICTIVE FOR SELECT TO anon
USING (bucket_id <> 'northstar-message-attachments');
DROP POLICY IF EXISTS northstar_message_attachments_anon_upload_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_anon_upload_guard
ON storage.objects AS RESTRICTIVE FOR INSERT TO anon
WITH CHECK (bucket_id <> 'northstar-message-attachments');
DROP POLICY IF EXISTS northstar_message_attachments_no_update_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_no_update_guard
ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
USING (bucket_id <> 'northstar-message-attachments')
WITH CHECK (bucket_id <> 'northstar-message-attachments');
DROP POLICY IF EXISTS northstar_message_attachments_no_delete_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_no_delete_guard
ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
USING (bucket_id <> 'northstar-message-attachments');
DROP POLICY IF EXISTS northstar_message_attachments_anon_no_update_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_anon_no_update_guard
ON storage.objects AS RESTRICTIVE FOR UPDATE TO anon
USING (bucket_id <> 'northstar-message-attachments')
WITH CHECK (bucket_id <> 'northstar-message-attachments');
DROP POLICY IF EXISTS northstar_message_attachments_anon_no_delete_guard ON storage.objects;
CREATE POLICY northstar_message_attachments_anon_no_delete_guard
ON storage.objects AS RESTRICTIVE FOR DELETE TO anon
USING (bucket_id <> 'northstar-message-attachments');

DO $realtime$
DECLARE
  target_table text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH target_table IN ARRAY ARRAY[
      'message_replies', 'message_reactions', 'message_attachments',
      'northstar_conversation_user_state', 'northstar_conversation_message_pins', 'northstar_conversation_typing'
    ] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = target_table
      ) THEN
        EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', target_table);
      END IF;
    END LOOP;
  END IF;
END;
$realtime$;

NOTIFY pgrst, 'reload schema';
COMMIT;
