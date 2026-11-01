import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/20261101120000_northstar_messaging_conversation_management.sql', import.meta.url), 'utf8')
const workspace = readFileSync(new URL('../../stores/workspace.ts', import.meta.url), 'utf8')
const messagesPage = readFileSync(new URL('../../pages/messages.vue', import.meta.url), 'utf8')
const interactions = readFileSync(new URL('../../../supabase/migrations/20261024170000_northstar_message_interactions.sql', import.meta.url), 'utf8')

test('direct conversation creation is an authenticated, idempotent same-department RPC', () => {
  assert.match(migration, /CREATE FUNCTION public\.northstar_create_direct_conversation\(p_member_ids uuid\[\]\)[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path = ''[\s\S]*?SET row_security = off/)
  assert.match(migration, /cardinality\(p_member_ids\) <> 1/)
  assert.match(migration, /profile\.approval_status::text = 'approved'[\s\S]*?profile\.employment_status::text = 'active'[\s\S]*?profile\.registration_completed IS TRUE/)
  assert.match(migration, /peer_department_id IS DISTINCT FROM actor_department_id/)
  assert.match(migration, /pg_advisory_xact_lock/)
  assert.match(migration, /count\(\*\) = 2[\s\S]*?array_agg\(membership\.user_id ORDER BY membership\.user_id\)/)
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.northstar_create_direct_conversation\(uuid\[\]\) TO authenticated/)
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.northstar_create_direct_conversation\(uuid\[\]\) FROM PUBLIC, anon, service_role/)
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.create_conversation\(uuid\[\]\) FROM PUBLIC, anon, authenticated/)
  assert.match(migration, /The legacy conversation RPC remains executable by a client role or PUBLIC/)
})

test('workspace uses the secured conversation RPC and retains empty direct threads', () => {
  assert.match(workspace, /rpc\('northstar_create_direct_conversation', \{ p_member_ids: \[employeeId\] \}\)/)
  const legacyWorkspace = readFileSync(new URL('../../stores/workspace-damilola-pc.ts', import.meta.url), 'utf8')
  assert.match(legacyWorkspace, /rpc\('northstar_create_direct_conversation', \{ p_member_ids: \[employeeId\] \}\)/)
  assert.doesNotMatch(legacyWorkspace, /rpc\('create_conversation'/)
  assert.doesNotMatch(workspace, /\.filter\(item => item\.messages\.length > 0\)/)
  assert.match(workspace, /\.from\('conversation_members'\)[\s\S]*?\.select\('conversation_id,last_read_at'\)[\s\S]*?\.eq\('user_id', auth\.userId\)/)
  assert.match(workspace, /\.from\('conversations'\)[\s\S]*?messages!messages_conversation_id_fkey[\s\S]*?\.in\('id', ids\)/)
  assert.match(workspace, /if \(ids\.length === 0\) \{\s*conversations\.value = \[\]/)
})

test('message sends still use the established idempotent sender and replies keep same-thread checks', () => {
  assert.match(workspace, /rpc\('northstar_send_message', \{[\s\S]*?p_conversation_id: conversationId,[\s\S]*?p_client_request_id: requestId/)
  assert.match(messagesPage, /selectedConversation\.value\s*\?\s*await workspace\.sendMessage\(selectedConversation\.value\.id, draft\.value, replyingTo\.value\?\.id\)[\s\S]*?: await workspace\.sendFirstMessage\(composingEmployee\.value!\.id, draft\.value\)/)
  assert.match(workspace, /const \{ data, error \} = replyToMessageId[\s\S]*?rpc\('northstar_send_message_reply'[\s\S]*?rpc\('northstar_send_message'/)
  assert.match(workspace, /if \(error\) \{\s*backendError\.value = `Could not send message[\s\S]*?\$\{error\.message\}/)
  assert.match(interactions, /target\.id = p_reply_to_message_id[\s\S]*?target\.conversation_id = p_conversation_id/)
  assert.match(interactions, /northstar_private\.is_conversation_member\(p_conversation_id\)/)
})

test('messages are added to supabase_realtime without changing existing attachment guards', () => {
  assert.match(migration, /ALTER PUBLICATION supabase_realtime ADD TABLE public\.messages/)
  assert.match(interactions, /northstar_message_attachments_upload_guard[\s\S]*?AS RESTRICTIVE FOR INSERT TO authenticated/)
  assert.match(interactions, /northstar_message_attachments_read_guard[\s\S]*?AS RESTRICTIVE FOR SELECT TO authenticated/)
})
