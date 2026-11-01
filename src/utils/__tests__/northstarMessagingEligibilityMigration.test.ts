import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/20261102120000_northstar_messaging_sender_eligibility.sql', import.meta.url), 'utf8')
const replyMigration = readFileSync(new URL('../../../supabase/migrations/20261024170000_northstar_message_interactions.sql', import.meta.url), 'utf8')
const designatedAdminMigration = readFileSync(new URL('../../../supabase/migrations/20261015120000_northstar_registration_support.sql', import.meta.url), 'utf8')

test('message eligibility requires approved, complete, active, confirmed employee or designated admin identity', () => {
  assert.match(migration, /profile\.approval_status::text = 'approved'/)
  assert.match(migration, /profile\.registration_completed IS TRUE/)
  assert.match(migration, /profile\.employment_status::text = 'active'/)
  assert.match(migration, /account\.email_confirmed_at IS NOT NULL/)
  assert.match(migration, /public\.has_any_role\(ARRAY\['employee', 'manager', 'admin'\]::text\[\]\)/)
  assert.match(migration, /profile\.role::text = 'admin' AND public\.northstar_is_designated_admin\(\)/)
  assert.match(designatedAdminMigration, /lower\(u\.email\) = 'northstaradmin34@gmail\.com'[\s\S]*?u\.email_confirmed_at IS NOT NULL/)
})

test('public sender and reply wrappers gate calls to retained implementations', () => {
  assert.match(migration, /procedure_row\.proowner = 'postgres'::regrole/)
  assert.match(migration, /row_security=off/)
  assert.match(migration, /split_part\(setting\.config_value, '=', 1\) = 'search_path'[\s\S]*?regexp_replace\(split_part\(setting\.config_value, '=', 2\), '\["\]', '', 'g'\) = ''/)
  assert.match(migration, /ALTER FUNCTION public\.northstar_send_message\(uuid, text, uuid\)[\s\S]*?RENAME TO northstar_send_message_existing_impl/)
  assert.match(migration, /ALTER FUNCTION public\.northstar_send_message_reply\(uuid, text, uuid, uuid\)[\s\S]*?RENAME TO northstar_send_message_reply_existing_impl/)
  assert.match(migration, /CREATE FUNCTION public\.northstar_send_message\([\s\S]*?IF NOT northstar_private\.is_eligible_messaging_actor\(\)[\s\S]*?northstar_send_message_existing_impl\(/)
  assert.match(migration, /CREATE FUNCTION public\.northstar_send_message_reply\([\s\S]*?IF NOT northstar_private\.is_eligible_messaging_actor\(\)[\s\S]*?northstar_send_message_reply_existing_impl\(/)
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.northstar_send_message_existing_impl\(uuid, text, uuid\)[\s\S]*?FROM PUBLIC, anon, authenticated, service_role/)
  assert.match(migration, /has_function_privilege\('anon', 'public\.northstar_send_message_existing_impl/)
  assert.match(migration, /has_function_privilege\('authenticated', 'public\.northstar_send_message_reply_existing_impl/)
})

test('retained reply implementation still checks membership, target conversation and request idempotency', () => {
  assert.match(replyMigration, /northstar_send_message_reply\([\s\S]*?northstar_private\.is_conversation_member\(p_conversation_id\)/)
  assert.match(replyMigration, /target\.id = p_reply_to_message_id[\s\S]*?target\.conversation_id = p_conversation_id/)
  assert.match(replyMigration, /pg_advisory_xact_lock[\s\S]*?get_my_reply_request\(p_client_request_id\)/)
  assert.match(replyMigration, /public\.northstar_send_message\(\$1, \$2, \$3\)/)
})
