# NorthStar FastAPI backend

This API runs alongside the Vue application and Supabase. Supabase remains the
identity provider, database API, file storage, and realtime service. The API
currently provides health/readiness checks and verified identity introspection;
it does not implement NorthStar business workflows.

## Local setup

Use Python 3.11 or newer from this directory:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
```

Set the required local values in `backend/.env`: `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `JWT_ISSUER`, `JWT_JWKS_URL`, and explicit `CORS_ORIGINS`.
Use the public anon/publishable key only. Keep service-role keys and all other
server secrets out of Vue/Vite variables. The example file contains placeholders.
For Twilio calling, configure `TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY`, and
`TWILIO_API_SECRET` in this backend-only file or a server-side secret store. The
API key and secret must be provisioned in Twilio; never paste them into source or
chat. `TWILIO_TURN_TTL_SECONDS` defaults to 3600 (one hour).

Production must also set `RATE_LIMIT_REDIS_URL` to the private Render Key Value
connection URL (or a compatible Redis URL). Keep this value only in the backend
environment. `ICE_SERVERS_USER_LIMIT`, `ICE_SERVERS_GLOBAL_LIMIT`, and
`ICE_SERVERS_RATE_WINDOW_SECONDS` default to 10, 120, and 60. The ICE endpoint
uses one atomic Redis Lua operation for both rolling-window limits, keyed by
verified JWT subject and endpoint-wide scope. Rate-limit state is shared across workers;
there is no in-memory fallback. Missing production configuration prevents
application configuration from loading. If Redis is unavailable at request
time, the endpoint fails closed with a generic 503; over-limit requests receive
429 and `Retry-After`.

Run the server and tests:

```powershell
uvicorn app.main:app --reload
python -m pytest -v
```

The API docs are at `/docs`; health and readiness are `/api/v1/health` and
`/api/v1/ready`. Both are local process checks and make no Supabase network
request. Readiness means the API process is serving requests; it does not assert
that Supabase is reachable. JWT verification fetches/refreshes JWKS only when an
authenticated request requires it.

`GET /api/v1/calls/ice-servers` requires a verified Supabase bearer token and
requests a fresh Twilio NTS token over HTTPS using HTTP Basic Auth with the
configured API key and secret. It sends the configured TTL and returns only
`ice_servers` plus server-calculated `expires_at`. Provider failures fail closed
with a generic 503 response. Temporary credentials are not cached or logged.

## Configuration and protections

`ENVIRONMENT` accepts `development`, `test`, or `production`. Production requires
HTTPS Supabase and HTTPS browser origins and rejects loopback origins. CORS never
accepts wildcard origins. Request bodies are capped by `MAX_REQUEST_BODY_BYTES`
(default 1 MiB; allowed range 1 KiB–20 MiB). Authentication failures use a safe
401 response and structured event logging without token contents. Unhandled errors
return a generic 500 body; application logs record only event, HTTP method and
route template. Automated tests inject a fake atomic store and do not require a
Redis service. This does not verify connectivity or Lua behavior against a live
Render Key Value instance.

Optional Lua integration tests live in `tests/test_rate_limit_redis_integration.py`.
They run only when `TEST_RATE_LIMIT_REDIS_URL` is explicitly set to a disposable,
isolated test Redis instance; they never fall back to `RATE_LIMIT_REDIS_URL`.
Without that variable they are reported as skipped. The tests delete only their
unique test keys and do not flush the selected Redis database.

The dependency manifest specifies compatible version ranges, not a complete
transitive lockfile. Use a reviewed lock/constraints workflow in CI before
deploying if byte-for-byte repeatable installs are required; do not auto-upgrade
these packages as part of deployment.

## Current and future API boundaries

| Area | Existing Supabase/Vue path | FastAPI today | Recommended boundary |
| --- | --- | --- | --- |
| Sign-in, sign-up, email confirmation, password reset/session | Supabase Auth from `stores/auth.ts`; `resend-confirmation` Edge Function | JWT verification and `/auth/me` | Keep credentials/session lifecycle in Supabase Auth. Use FastAPI only for authenticated server workflows that need a server-held secret. |
| Employee profiles, registration, approvals, directory | RLS-governed PostgREST and named registration/admin RPCs | None | Keep current RPCs/queries while their RLS and function authorization remain verified. Add FastAPI orchestration only for multi-step workflows or external systems. |
| Direct/group messaging and attachments | PostgREST/RPC, Realtime channels, private Storage uploads and signed URLs | None | Keep realtime transport and binary uploads in Supabase. Add an API only for server-side scanning, compliance orchestration, or another secret-backed integration. |
| Notifications and push | Postgres rows/Realtime plus `send-push-notification` Edge Function | None | Keep delivery in the existing Edge Function unless there is a specific operational reason to consolidate; never duplicate push credentials in the browser. |
| Presence | Existing heartbeat/listing RPCs and client state | None | Keep low-latency heartbeat/query operations in Supabase unless centralized presence semantics become necessary. |
| Audio/video call signalling | Supabase Realtime/RPC; browser WebRTC | Verified-user Twilio ICE credential endpoint | Keep signalling in Supabase. FastAPI requests short-lived Twilio TURN credentials; configure backend secrets and verify real network connectivity before production. |
| Disaster/incident management | Supabase RPCs, RLS, PostgREST and Realtime | None | Keep database authorization and state transitions in reviewed RPCs. FastAPI can later orchestrate external incident integrations. |
| Support inquiries | Supabase support RPCs and Realtime/PostgREST | None | Keep the existing scoped RPC flow unless support needs external ticketing or privileged server orchestration. |
| Announcements, events, company resources | RLS-governed PostgREST and Storage | None | Keep direct access under RLS; use the API only for integrations or server-side processing. |

Recommended order: (1) provision and configure a shared Redis-compatible store
for production (the application does not create one), (2) configure Twilio backend secrets and run
two-user TURN connectivity checks, (3) select one owner for push delivery before any
consolidation, and (4) add business API routes only where a concrete server-side
responsibility exists. Frontend integration should then be limited to those
selected routes and must forward the current Supabase access token. The backend
must continue using the public key plus that verified user token so RLS applies.

This map reflects source references in the current Vue repository; it does not
prove the live deployment state or the current effective RLS/function privileges.

## NorthStar feature completion checklist

This is a source and test inventory, not a claim that the production Supabase
project is in sync with this checkout. `COMPLETE` is reserved for behavior with
appropriate integration evidence; a migration file, Vue page, or mocked test by
itself is not enough. Existing Supabase workflows remain in Supabase unless a
specific server-side responsibility calls for FastAPI.

| Feature area / scope | Status | Current evidence and remaining verification |
| --- | --- | --- |
| A. Authentication: Supabase sign-in/session restore, confirmation, password reset | PARTIALLY COMPLETE | Vue auth store/pages use Supabase Auth; `resend-confirmation` Edge Function is present. Verify deployed function configuration, mail delivery, confirmation and recovery flows with test accounts. |
| A. Registration, correction, admin approval/rejection, profile/employment status, employee access | PARTIALLY COMPLETE | Vue forms and local migrations/RPC references exist; FastAPI verifies Supabase JWTs and provides `/auth/me`. Confirm deployed migration history, effective RLS/RPC authorization, and employee/admin workflows with separate accounts. |
| B. Departments, membership, heads, level assignments 1–5, ranking and assignment conflict checks | PARTIALLY COMPLETE | Vue department/directory flows, hierarchy utilities and department/head RPC migrations exist, including `northstar_admin_set_department_head` and `northstar_admin_assign_department_level`. Live function bodies, constraints, role authorization, level semantics, and cross-department visibility still require the supplied audit evidence or live verification. |
| B. Department-specific/cross-department permissions, directory filtering | PARTIALLY COMPLETE | Vue filtering and local policies/RPCs are present. Verify combined table grants, permissive/restrictive policies, and two-user cross-department behavior before treating permissions as complete. |
| C. Direct/group messaging, delivery/history/pagination, receipts, typing, edits/deletes, reactions, pins/hide state, attachments and notifications | PARTIALLY COMPLETE | Vue workspace and messaging RPC/Realtime/Storage migration sources implement these paths. Reported conversation relationship embedding and “thread not found” errors remain unresolved; verify deployed RPC signatures/FKs/policies and exercise two users, including attachment access and mutation boundaries. |
| D. Audio/video call lifecycle, WebRTC media, STUN/TURN, ICE exchange, signalling, synchronization, reconnection, timeouts and concurrent calls | PARTIALLY COMPLETE | Vue call store and local `northstar_start_call`, `northstar_send_call_signal`, and `northstar_update_call_status` references exist. FastAPI Twilio NTS endpoint and Vue integration are covered by mocked/provider-contract tests. `CHANNEL_ERROR` remains unresolved; provider secrets, deployed RPC/Realtime authorization, and real two-user audio/video connectivity are not verified. |
| E. Online/offline/away, heartbeat, expiry, reconnect, tabs, cleanup and presence visibility | PARTIALLY COMPLETE | Vue sends `northstar_presence_heartbeat` and reads `northstar_list_employee_presence`; a presence utility test exists. “Status unavailable” remains unresolved. Confirm the deployed function contract/expiry behavior and test tab churn, logout and two-user visibility. |
| F. In-app message/call/incident/support notifications, preferences, read state, Realtime and push | PARTIALLY COMPLETE | Vue notification store and `send-push-notification` Edge Function are present; migration sources cover push setup. Reported `TIMED_OUT` remains unresolved. Verify deployed JWT/webhook/secret configuration, publication/RLS, delivery providers, preferences and read state. |
| G. Incident creation/reporting, department/company visibility, updates, assignment, severity/status/resolution and notifications | PARTIALLY COMPLETE | Vue incident page and local incident RPC/policy migrations exist. Company-wide visibility migration remains blocked pending field-level privacy approval and live definition comparison; verify reporter/admin/department-head/responder access and sensitive-field redaction with test users. |
| H. Support employee inquiries/history, admin inbox/replies, search/filter, notifications and attachments | PARTIALLY COMPLETE | Vue support page and local submission/list/message/reply RPCs exist. Verify deployed function authorization, realtime delivery, attachment scope (if used), and employee/admin interaction with two accounts. |
| I. Announcements, events, RSVP, company/department resources and file access | PARTIALLY COMPLETE | Vue pages, PostgREST queries and Storage signed-download paths exist. Verify deployed table policies, bucket settings/object policies, department scope, and upload/download behavior with distinct roles. |
| J. Designated admin authorization, employee/approval/department management and audit logs | PARTIALLY COMPLETE | Vue admin pages and local admin/RPC/policy migrations exist. Verify designated-admin identity source, function ACLs and RLS together, audit-log completeness/tamper resistance, and approval history against live state. |
| FastAPI business API beyond auth, health/readiness, and Twilio TURN | NOT IMPLEMENTED | Intentionally no duplicate CRUD/messaging/incident routes. Add a route only when a concrete server-side integration or orchestration requirement is identified; pass the verified bearer identity and retain user-scoped Supabase access. |

### Outstanding defects and verification gates

These reported application errors remain open and must not be counted as
resolved merely because the client displays a fallback or retries:

- Call signalling `CHANNEL_ERROR`.
- Notification Realtime `TIMED_OUT`.
- Employee presence “Status unavailable”.
- Conversation relationship embedding error.
- “Thread not found” when submitting messages.

The repository contains migration source and a consolidated read-only audit
script, but the prior reconciliation says raw catalog output was unavailable
and the live migration ledger, full definitions/ACLs and effective policies
remain unverified. The three candidate migration decisions remain blocked as
described in `supabase/preflight/northstar_live_migration_reconciliation.md`.
No live database query or SQL execution is part of this checklist. Any required
database change needs a separately reviewed proposal and approval.

Verification evidence must be reported in distinct categories:

| Evidence type | Current result | Limit |
| --- | --- | --- |
| FastAPI automated tests | Run the complete suite for the current checkout before reporting a final result. | Unit and mocked HTTP tests do not prove Supabase or Twilio deployment behavior. |
| Frontend build | Run when frontend files are changed. | A successful build proves compilation/type checking, not successful API/Realtime/database behavior. |
| Live integration | Not performed in this audit pass. | Requires the approved NorthStar project/environment and test accounts; no production secrets should be copied into the browser. |
| Two-user functional checks | Outstanding for messaging, calls, presence, notifications, incidents and support. | Use separate approved employee/admin test accounts and verify both allowed and denied access paths. |

Validation snapshot for 2026-11-04:

- FastAPI: `114 passed, 0 failed, 1 warning` (`python -m pytest -v` from
  `backend/`). The warning is Starlette's deprecation notice for using `httpx`
  with `starlette.testclient`; it recommends `httpx2`.
- Frontend production build and Vue type check: passed. Vite reported the
  existing Vue Router `rootDir` advisory and a minified bundle larger than
  500 kB; plugin timing output was informational.
- Frontend presence unit tests: `4 passed, 0 failed` (`npm run test:presence`).
- `git diff --check`: passed. Git printed line-ending conversion advisories
  (LF to CRLF), not whitespace errors.
- No live Supabase/Twilio integration or actual two-user call test was run.

### Remaining setup and decisions

- Configure the Twilio account SID, API key and API secret only in the FastAPI
  server environment, then verify real token retrieval and two-user media
  connectivity. The endpoint fails closed while any required value is missing.
- Set explicit production `CORS_ORIGINS`, secure Supabase/JWT settings, and a
  shared rate limiter at a trusted gateway before exposing FastAPI publicly.
- Decide the single owner for push delivery before changing or duplicating the
  Edge Function path.
- Reconcile deployed migration history and actual function/policy/storage/
  Realtime state using the prepared read-only audit; do not infer deployment
  from repository files.
- Resolve each reported runtime error with its exact safe diagnostic, then
  verify the correction against the deployed project and two test users.
- Review and approve incident company-wide field disclosure before any change
  that broadens incident visibility.
