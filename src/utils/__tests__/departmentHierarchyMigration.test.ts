import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const hierarchyMigration = readFileSync(new URL('../../../supabase/migrations/20261029120000_northstar_department_hierarchy_and_collaboration.sql', import.meta.url), 'utf8')
const managementMigration = readFileSync(new URL('../../../supabase/migrations/20261030120000_northstar_department_head_management.sql', import.meta.url), 'utf8')

test('department rank and head mutation RPCs have server-side designated-admin guards', () => {
  assert.match(hierarchyMigration, /FUNCTION public\.northstar_admin_assign_department_level[\s\S]*?IF NOT public\.northstar_is_designated_admin\(\)/)
  assert.match(managementMigration, /FUNCTION public\.northstar_admin_set_department_head[\s\S]*?IF NOT public\.northstar_is_designated_admin\(\)/)
  assert.match(managementMigration, /FUNCTION public\.northstar_admin_approve_employee_with_department_level[\s\S]*?IF NOT public\.northstar_is_designated_admin\(\)/)
  assert.match(managementMigration, /REVOKE ALL ON FUNCTION public\.northstar_admin_approve_employee_with_department_level[\s\S]*?FROM PUBLIC, anon/)
})

test('head selection checks role, approval, employment, registration, and confirmed email in SQL', () => {
  assert.match(managementMigration, /candidate\.role::text IN \('employee', 'manager'\)/)
  assert.match(managementMigration, /candidate\.registration_completed IS TRUE/)
  assert.match(managementMigration, /candidate\.approval_status::text = 'approved'/)
  assert.match(managementMigration, /candidate\.employment_status::text = 'active'/)
  assert.match(managementMigration, /user_row\.email_confirmed_at IS NOT NULL/)
  assert.match(managementMigration, /WHERE p\.department_id IS NULL AND p\.role::text IN \('employee', 'manager'\)/)
})

test('head replacement serializes by department and retains the unique active-head index', () => {
  assert.match(managementMigration, /pg_advisory_xact_lock[\s\S]*?northstar_admin_assign_department_level\(p_user_id, p_department_id, 1\)/)
  assert.match(hierarchyMigration, /CREATE UNIQUE INDEX IF NOT EXISTS northstar_one_active_department_head_uidx[\s\S]*?department_level = 1/)
})
