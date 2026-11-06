# NorthStar live migration reconciliation

## Evidence and scope

**Status: supplied live findings reconciled; raw catalog detail remains unavailable.** The audit summary pasted in the conversation confirms the findings and permission contracts listed below. The full file `Supabase Snippet List Specific Function Details.csv` is not present in the accessible workspace, and no connected document session was available, so its routine definitions, direct ACL rows, policy expressions, columns, constraints, indexes, and migration ledger output could not be independently read. No Supabase connection was made and no SQL was executed.

The live facts below are **confirmed by the supplied live audit summary**, not independently verified by inspecting the CSV. Repository statements are labeled **independently verified from repository files**. Any live detail not stated in the supplied summary is marked **UNVERIFIED**. The complete three migration files and relevant predecessor migrations were reviewed locally.

The local Supabase config contains no project ID, and no Supabase CLI is available. The configured `.env` project URL could not be associated with a trusted NorthStar project reference, so it was not used as a database target.

## 1. Department-head `smallint` correction

Migration: [`20261103140000_northstar_department_head_smallint_call.sql`](../migrations/20261103140000_northstar_department_head_smallint_call.sql)

### Live facts provided in the request

- Both department-head RPCs grant `EXECUTE` to `authenticated` and `service_role`. The supplied summary does not state the complete live owner/configuration or direct ACL rows; those details remain **UNVERIFIED**.
- The setter calls `northstar_admin_assign_department_level` with bare integer literal `1`; an explicit `smallint` cast is absent.
- **UNVERIFIED:** Full live definitions, owner and security configuration, anon/PUBLIC status for each function, and any additional grants.

### Exact migration effect

The migration resolves `public.northstar_admin_set_department_head(uuid,uuid,smallint)`, reads its current definition with `pg_get_functiondef`, and changes only the exact call text:

```sql
northstar_admin_assign_department_level(p_user_id, p_department_id, 1)
```

to:

```sql
northstar_admin_assign_department_level(p_user_id, p_department_id, 1::smallint)
```

It executes the resulting `CREATE OR REPLACE FUNCTION` definition and validates the cast, owner, security-definer status, configuration, authenticated access, and absence of anonymous access. It does not name or modify any table, policy, row, or grant statement.

Compared with the repository predecessor in `20261030120000_northstar_department_head_management.sql`, this is the intended one-expression change. The predecessor contains the designated-administrator guard, department advisory lock and row lock, candidate eligibility checks, current-head handling, and assignment calls. The dynamic rewrite preserves the rest of the installed function source rather than copying the repository version over it.

`CREATE OR REPLACE FUNCTION` preserves the existing function owner and privileges. Accordingly, this migration should retain the live `service_role` permission described in the supplied audit. Its postflight originally checked authenticated and anon only; the review candidate adds service_role and direct-PUBLIC assertions without changing grants.

### Dependencies, risks, and correction

- Requires the setter and `public.northstar_admin_assign_department_level(uuid,uuid,smallint)` from the department hierarchy/management migrations.
- No record changes or RLS changes occur.
- It aborts if the function is missing or its definition does not contain the expected uncast call. It is safe to rerun if already corrected; the postflight still runs.
- The intended source change is only the cast. The candidate preserves the installed function definition dynamically. **UNVERIFIED:** Whether the complete live body contains other drift, because the CSV was unavailable.

**Candidate:** [`20261103140000_northstar_department_head_smallint_call_candidate.sql`](migration-review/20261103140000_northstar_department_head_smallint_call_candidate.sql) adds postflight assertions for authenticated/service_role execute, anon denial, no direct PUBLIC execute, and the existing security configuration. It adds no GRANT/REVOKE.

**Recommendation: BLOCKED** pending the raw audit output. Based on the supplied summary, the targeted cast appears to preserve the live function and its ACL. The report cannot independently verify the complete live body or permissions without the CSV.

## 2. Cross-department direct messaging

Migration: [`20261103120000_northstar_cross_department_direct_messaging.sql`](../migrations/20261103120000_northstar_cross_department_direct_messaging.sql)

### Live facts provided in the request

- The live function requires both participants to have department assignments and compares their departments.
- It already checks confirmed email, completed registration, approved status, active employment, employee/manager roles, self-conversation prevention, advisory locking, and reuse of exact two-member conversations.
- It is `SECURITY DEFINER`, owned by `postgres`, with the expected secure configuration.
- The supplied audit confirms `authenticated` can execute it, while `anon`, `PUBLIC`, and `service_role` cannot.
- **UNVERIFIED:** Full live function text, direct ACL rows, membership constraints and index definitions; the requested CSV was not available for inspection.

### Exact migration effect and comparison

The migration replaces `public.northstar_create_direct_conversation(uuid[])`, sets owner to `postgres`, revokes all execution from `PUBLIC`, `anon`, and `service_role`, and grants execution to `authenticated`.

Its replacement removes the sender and peer department-ID lookups, the null-department rejection, and the same-department comparison. It retains both participants' role, confirmed-email, completed-registration, approved-account, and active-employment checks; rejects self-conversations; uses the same sorted-pair advisory lock; reuses a conversation whose membership set is exactly the two participant IDs; and otherwise inserts a conversation and its two memberships.

The repository predecessor in `20261101120000_northstar_messaging_conversation_management.sql` contains those same restrictions and the matching locking/reuse flow. The proposed body appears to make the requested department-only behavior change. The RPC uses `SECURITY DEFINER`, empty `search_path`, and `row_security=off`; those settings are backed by explicit participant checks and authenticated-only access. The migration does not alter RLS policies.

### Dependencies, overwrite risk, and correction

- Requires `public.has_any_role(text[])`, `public.profiles`, `auth.users`, `public.conversations`, and `public.conversation_members` with the checked columns.
- Requires a valid unique index named `northstar_conversation_members_pair_uidx` on `(conversation_id, user_id)`. The migration fails before replacement if it is absent or invalid.
- It creates no records during migration application. The replacement RPC creates a conversation and memberships only when later invoked and no exact two-member conversation exists.
- Its preflight verifies selected fragments of the installed body, owner/security settings, and the index. Those fragment checks do not prove the entire live function equals the expected predecessor. A newer function with additional authorization or behavior could pass and then have that logic overwritten by the full replacement.
- It is rerunnable against the definition it installs: the preflight fragments continue to match, then the function/ACL statements are repeated. **UNVERIFIED:** Live grants and membership integrity beyond the facts quoted above.

**Candidate:** [`20261103120000_northstar_cross_department_direct_messaging_candidate.sql`](migration-review/20261103120000_northstar_cross_department_direct_messaging_candidate.sql) includes an exact definition MD5 guard with an intentionally unset sentinel. Before it can run, obtain the full function definition from the verified NorthStar project, review it against the intended predecessor, compute `md5(pg_get_functiondef(...))`, and replace the sentinel. It aborts while the sentinel is unset or mismatched. The candidate retains authenticated-only execution and postflight checks.

**Recommendation: NEEDS CORRECTION** because the current preflight does not reliably prevent replacing an unexpected newer function.

## 3. Company-wide incident visibility

Migration: [`20261103130000_northstar_companywide_incident_visibility.sql`](../migrations/20261103130000_northstar_companywide_incident_visibility.sql)

### Live facts provided in the request

- Both incident tables exist and RLS is enabled.
- Company-wide incident and update visibility are absent.
- Admin-update exclusion and response-team restrictions exist.
- The supplied audit confirms the incident RPCs grant `EXECUTE` to `authenticated` and `service_role`; company-wide incident visibility is absent; admin-update exclusion and responder restrictions exist.
- **UNVERIFIED:** Complete policies, RLS forced status, complete list/history function bodies, direct ACL rows, helper definitions, table constraints, and index definitions.

### Exact migration effects and protections

The migration first requires both incident tables, the eligibility/admin helpers, the department incident list/history RPCs, enabled RLS, and two specifically named restrictive authenticated SELECT policies. It checks policy command/permissiveness/role and selected required fragments of each policy. It also checks selected security settings and source fragments of the list/history RPCs.

It then:

1. Alters `northstar_incidents_department_guard` by preserving its existing predicate and OR-ing an additional branch for eligible users viewing non-deleted incidents whose `department_id IS NULL`.
2. Alters `northstar_incident_updates_department_guard` by preserving its existing predicate and OR-ing a company-wide branch that excludes `visibility='admin'` and `event_type='admin_update'`, requires an eligible user and a non-deleted company-wide parent incident, and restricts `response_team` rows to the assigned responder.
3. Replaces `northstar_department_list_incidents()` to include eligible company-wide incidents while retaining department/reporter filtering. Reporter ID/name are returned only to the administrator or reporter; responder assignment is returned only to the administrator, reporter, assigned responder, or department head.
4. Replaces `northstar_department_list_incident_history(uuid[])` to include eligible company-wide history while retaining department/reporter filtering, admin-update exclusion, response-team assignment checks, and detail redaction for ordinary viewers.
5. Sets both RPC owners to `postgres`, retains `SECURITY DEFINER`, empty `search_path`, and `row_security=off`, revokes from `PUBLIC`/`anon`, and grants to `authenticated`. The existing explicit `service_role` grant should survive `CREATE OR REPLACE`; the original postflight fails to verify that it does.

No incident or update records are changed. RLS remains enabled; the restrictive policy predicates are broadened only by the intended eligible-company-wide branches. This makes incident fields selected by the list RPC (including title, description, location, category, severity, status, and resolution details) visible for company-wide incidents to eligible employees. Reporter identity and responder assignment remain conditionally redacted by the RPC; admin-only update rows/details remain excluded for ordinary employees; response-team updates remain assigned-responder-only.

**Repository-verified content privacy risk:** the schema has no incident-level field classification or explicit company-wide-safe flag. The migration's list RPC returns title, description, location, category, severity, status, responder assignment, and resolution details. Its current redactions condition reporter identity and responder assignment, but do not redact description/location/resolution details for company-wide incidents. The history RPC returns event types and status/severity transitions, and conditionally redacts update `details`; admin-only events remain excluded and response-team events remain restricted. This is not enough to establish that ordinary incident fields are safe for broad visibility. The supplied live summary does not settle content classification.

| Field | Effect of proposed company-wide path | Privacy assessment |
|---|---|---|
| Title | Returned unchanged | Could contain identifying or sensitive content; no classification. |
| Description | Returned unchanged | Potentially sensitive narrative; no redaction. |
| Location | Returned unchanged | Can reveal sensitive facility/person location; no redaction. |
| Category | Returned unchanged | Likely lower sensitivity, but classification is not encoded. |
| Severity | Returned unchanged | Operationally sensitive in some cases; no classification. |
| Status | Returned unchanged | Operational progress is exposed. |
| Resolution details | Returned unchanged | May include sensitive remediation details; no redaction. |
| Reporter identity | UUID/name conditionally returned for admin or reporter | Other eligible viewers receive NULL. |
| Responder assignment | Conditionally returned for admin, reporter, assigned responder, or department head | Other eligible viewers receive NULL. |
| Update details | Admin events excluded; response-team visibility remains assigned-responder restricted; details are otherwise conditionally redacted | Existing protections remain, but event metadata and status/severity transitions may still be visible. |

The company-wide eligibility helper’s exact definition and role coverage are **UNVERIFIED** from the missing CSV. The replacement list RPC separately requires an approved, active employee/manager profile with completed registration and confirmed email, but helper internals still need review.

### Dependencies, overwrite/rerun risk, and corrections

- Depends on the incident schema and policies from `20261019000000_northstar_disaster_management.sql`, the reporter/history work in `20261028130000_northstar_incident_reporter_actions_and_shared_history.sql`, and the department helpers/list-history functions from `20261029120000_northstar_department_hierarchy_and_collaboration.sql`.
- Policy changes preserve the complete currently installed policy predicate text by retrieving `pg_get_expr` and adding the scoped branch. This retains other live predicate clauses if the expected named policy passes the preflight.
- Both incident RPCs are fully replaced. The preflight checks selected source fragments, not exact full definitions, so an unexpected newer function can pass and lose additional behavior in the replacement.
- The preflight deliberately rejects a policy that already contains the new company-wide branch. A second run therefore fails before changing anything, rather than acting as a no-op. This is fail-closed but not idempotent; a retry must first establish whether the migration already ran.
- The migration re-grants `authenticated` and revokes `PUBLIC`/`anon`, but does not validate `service_role`. The supplied audit confirms both incident RPCs grant `service_role`; `CREATE OR REPLACE FUNCTION` preserves that explicit grant. Add postflight checks without changing it.

**Candidate:** [`20261103130000_northstar_companywide_incident_visibility_candidate.sql`](migration-review/20261103130000_northstar_companywide_incident_visibility_candidate.sql) is intentionally fail-closed and makes no database changes. It documents the privacy block and a proposed design for review. An executable candidate requires an approved field-level disclosure design, exact live definition guards, first-run/already-applied detection, and authenticated/service_role/anon/PUBLIC ACL assertions. No fingerprint or permission has been invented.

**Recommendation: NEEDS CORRECTION** because the function-source guards are incomplete and rerun behavior requires explicit handling before final review.

## 4. Migration ledger investigation

The supplied audit summary says the expected migration ledger location was not found. The local audit SQL checks `supabase_migrations.schema_migrations` and its `version` column only. It does not search other schemas for another migration ledger, test read permission on a differently named ledger, or inspect external history tooling.

Therefore:

- A different database ledger location: **UNVERIFIED**.
- A ledger hidden/inaccessible to the SQL Editor role: **UNVERIFIED**.
- History managed outside the database: **UNVERIFIED**.
- Whether the NorthStar project has recorded any of the three versions: **UNVERIFIED**.
- Whether these migrations are pending: **UNVERIFIED**. A missing ledger result is not evidence that they are pending.

No ledger should be created or modified. To resolve this, the complete CSV (including ledger/catalog output) or an authorized read-only inspection must identify the actual migration-history mechanism and query its version records.

## 5. Ordering, object interactions, and shared risks

The three files target separate object groups and do not directly conflict with one another. Their filename order is direct messaging (`20261103120000`), incident visibility (`20261103130000`), then department-head cast (`20261103140000`). The messaging migration names `20261102130000` as its immediate prerequisite; the incident migration relies on the prior disaster, reporter-history, and department-hierarchy objects; the cast migration depends on department-head management and the assignment RPC. Verify all prerequisite versions before any application.

The cross-department migration does not alter membership RLS or table constraints; it depends on their existing integrity. The incident migration changes the two named restrictive SELECT policies and replaces the two department RPCs. The department correction replaces one function definition but does not issue permission changes. None of these files changes data during migration application.

Full live definitions, direct ACL rows, constraints, indexes, policy expressions, and version rows remain **UNVERIFIED** until the CSV is available. The supplied summary confirms high-level ACL contracts and findings only. Original migration files and database objects were not changed; three review candidates were prepared separately.

## 6. Final recommendations

| Migration | Recommendation | Blocking evidence/correction |
|---|---|---|
| `20261103140000_northstar_department_head_smallint_call.sql` | **BLOCKED** | Candidate adds requested postflight checks. Raw full live function is not available for comparison; supplied facts support the narrow cast correction. |
| `20261103120000_northstar_cross_department_direct_messaging.sql` | **BLOCKED** | Candidate contains a required but unset exact live-definition fingerprint. Populate only after full live predecessor review. |
| `20261103130000_northstar_companywide_incident_visibility.sql` | **BLOCKED** | No safe executable candidate until field-level disclosure is approved. Current candidate deliberately raises an exception without changing state. |

## 7. Review-candidate summary and production preconditions

The three candidate files are under `supabase/preflight/migration-review/`; they do not overwrite the original migrations. The department-head candidate changes only the cast operation and strengthens postflight checks. The messaging candidate adds an unset exact-definition fingerprint gate. The incident candidate is an intentional stop gate, not an executable migration, because the current schema has no reliable field-level sensitivity mechanism.

**Recommended order after all gates are cleared:** direct messaging (`20261103120000`), incident visibility (`20261103130000`), then department-head cast (`20261103140000`), matching timestamp order. Confirm their named prerequisite migration versions first. Do not treat this order as proof that any version is pending.

**Before any production execution:** obtain the complete live CSV from the verified NorthStar project; resolve the actual migration-history mechanism; verify all prerequisite versions; obtain and review exact current definitions and policy predicates; fill and independently verify the messaging and incident fingerprints; approve how company-wide incident fields are classified and redacted, including write authorization; validate the incident RPC first-run/already-applied path; confirm RLS remains enabled and old department/reporter/admin/responder protections remain intact; confirm authenticated and service_role execute plus anon denied and no direct PUBLIC grant for the incident RPCs; and obtain separate production approval. No connection, SQL execution, migration application, or deployment was performed for this review.

The raw CSV is still needed for the full live reconciliation. The supplied summary corrected the earlier permission findings but does not contain the full catalog evidence or ledger version rows.
