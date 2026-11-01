import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/20261031120000_northstar_companywide_admin_management.sql', import.meta.url), 'utf8')
const departmentCollaboration = readFileSync(new URL('../../pages/departmentCollaboration.vue', import.meta.url), 'utf8')
const disasterManagement = readFileSync(new URL('../../pages/disasterManagement.vue', import.meta.url), 'utf8')
const adminDashboard = readFileSync(new URL('../../pages/adminDashboard.vue', import.meta.url), 'utf8')
const adminDepartments = readFileSync(new URL('../../pages/adminDepartments.vue', import.meta.url), 'utf8')
const router = readFileSync(new URL('../../router/index.ts', import.meta.url), 'utf8')
const app = readFileSync(new URL('../../App.vue', import.meta.url), 'utf8')

test('department content write policies keep administrator writes company-wide and department writes head-scoped', () => {
  assert.match(migration, /northstar_department_announcements_insert_guard[\s\S]*?northstar_is_designated_admin\(\) AND department_id IS NULL/)
  const announcementInsertPolicies = migration.match(/ALTER POLICY northstar_department_announcements_insert_(?:guard|policy) ON public\.announcements[\s\S]*?\n\);/g) ?? []
  assert.equal(announcementInsertPolicies.length, 2)
  for (const policy of announcementInsertPolicies) {
    assert.doesNotMatch(policy, /department_id IS NULL AND northstar_private\.is_eligible_workspace_user/)
    assert.match(policy, /department_id IS NOT NULL[\s\S]*?northstar_private\.is_department_head\(department_id\)/)
  }
  const announcementUpdatePolicies = migration.match(/ALTER POLICY northstar_department_announcements_update_(?:guard|policy) ON public\.announcements[\s\S]*?\n\);/g) ?? []
  assert.equal(announcementUpdatePolicies.length, 2)
  for (const policy of announcementUpdatePolicies) {
    assert.doesNotMatch(policy, /role::text = 'manager'/)
    assert.match(policy, /northstar_is_designated_admin\(\) AND department_id IS NULL/)
    assert.match(policy, /northstar_private\.is_department_head\(department_id\)/)
  }
  assert.match(migration, /REVOKE UPDATE ON public\.announcements FROM authenticated;\s*GRANT UPDATE \(title, content, priority, is_pinned\) ON public\.announcements TO authenticated;/)
  assert.match(migration, /northstar_department_events_insert_guard[\s\S]*?northstar_is_designated_admin\(\) AND department_id IS NULL/)
  assert.match(migration, /northstar_department_resources_insert_guard[\s\S]*?northstar_is_designated_admin\(\) AND department_id IS NULL/)
  assert.match(migration, /northstar_private\.is_department_head\(department_id\)/)
  assert.match(migration, /resource_object_managed_by_department_head\(name\)/)
})

test('administrator incident RPCs are designated-admin guarded and company-wide only', () => {
  assert.match(migration, /FUNCTION public\.northstar_admin_report_company_incident[\s\S]*?northstar_is_designated_admin\(\)[\s\S]*?reported_by, department_id[\s\S]*?admin_id, NULL/)
  assert.match(migration, /FUNCTION public\.northstar_admin_update_incident[\s\S]*?northstar_is_designated_admin\(\)[\s\S]*?target\.id = p_incident_id AND target\.department_id IS NULL/)
})

test('admin department collaboration uses the admin shell and no admin department-write controls', () => {
  assert.match(router, /path: '\/department',[\s\S]*?adminReadable: true/)
  assert.match(app, /<AdminLayout v-if="route\.meta\.requiresAdmin \|\| \(route\.meta\.adminReadable && auth\.isAdmin\)">/)
  assert.match(departmentCollaboration, /const isHead = computed\(\(\) => !auth\.isAdmin/)
  assert.match(departmentCollaboration, /const canManage = computed\(\(\) => isHead\.value\)/)
})

test('administrator incident form uses the company-wide RPC and controls only company-wide incidents', () => {
  assert.match(disasterManagement, /canCreateIncident = computed\(\(\) => isDesignatedAdmin\.value \|\| canReportIncident\.value\)/)
  assert.match(disasterManagement, /northstar_admin_report_company_incident/)
  assert.match(disasterManagement, /if \(isDesignatedAdmin\.value\) return incident\.department_id === null/)
  assert.match(disasterManagement, /canManageIncident\(incident\)/)
})

test('smallint department rank RPC arguments are sent as decimal strings while preserving null assignments', () => {
  assert.match(adminDepartments, /p_department_level: level === null \? null : String\(level\)/)
  assert.match(adminDepartments, /p_outgoing_department_level: outgoingLevel === null \? null : String\(outgoingLevel\)/)
  assert.match(adminDashboard, /p_department_level: String\(level\)/)
  assert.match(adminDashboard, /p_outgoing_department_level: outgoingLevel === null \? null : String\(outgoingLevel\)/)
})
