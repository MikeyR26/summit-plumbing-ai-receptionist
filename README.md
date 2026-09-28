# Summit Plumbing — AI Receptionist for Salesforce Field Service

Portfolio demo: an AI receptionist (Claude + n8n) that books, reschedules, and
cancels jobs for a fictional Vancouver, BC plumbing company directly in
Salesforce Field Service.

## Architecture

```
Caller/Chat ──▶ n8n (AI Agent node, Claude) ──▶ Apex REST API ──▶ Salesforce Field Service
                                                                   (FSL scheduling engine)
```

- **Salesforce Field Service** — system of record. Accounts/Contacts (customers),
  WorkOrders + ServiceAppointments (jobs), ServiceResources (technicians),
  ServiceTerritory (Metro Vancouver), scheduled via the FSL managed package's
  scheduling engine (`FSL.ScheduleService` / `FSL.AppointmentBookingService`) —
  never by writing appointment times directly.
- **Apex REST API** (`/services/apexrest/agent/v1/*`) — the only interface the
  agent talks to. Handles lookup/create customer, get slots, book/reschedule/
  cancel appointments. Returns clean, agent-friendly JSON.
- **n8n Cloud** — orchestration layer. Fetches/caches an OAuth token, exposes
  each Apex endpoint as a tool, and runs the Claude-powered AI Agent node that
  talks to the caller.
- **Supabase / GitHub** — supporting infra for the agency's stack (used for
  auxiliary logging/config as the build progresses).

## Repo layout

- `summit-plumbing-ai-receptionist/` — the SFDX project (Apex classes, tests,
  seed/setup scripts, metadata).
- `n8n/` — importable n8n workflow JSON (added in Phase 5).
- `docs/` — test scenarios and any supplementary notes (added in Phase 6).

## Salesforce org

- Type: Developer Edition (org name shows as "BeeAI" — a default Salesforce
  assigns to new Dev Edition orgs, not related to this project).
- Field Service: enabled, with the FSL managed package installed
  (Summer2026, v262.0.68.1).
- CLI alias: `summit-plumbing` (see `sf org list`).

## Setup so far (Phase 1)

1. Installed Homebrew, Node.js, and the Salesforce CLI (`sf`).
2. Generated the SFDX project: `summit-plumbing-ai-receptionist/`.
3. Authorized the org via `sf org login web` (aliased `summit-plumbing`).
   Note: the browser-callback flow needed a couple of retries on this
   machine before the OAuth redirect connected — if it times out, just
   rerun `sf org login web --alias summit-plumbing --set-default`.
4. Enabled Field Service (Setup → Field Service Settings).
5. Installed the FSL managed package via the direct install link
   (`https://d36000000z1fneac.my.salesforce-sites.com/install` →
   "Install in Production" → "Install for Admins Only"). This package isn't
   distributed through the public AppExchange marketplace search — it's
   only reachable via that direct link.

## Setup so far (Phase 2)

Field Service configuration and seed data are fully scripted and idempotent —
rerun any time with:

```
cd summit-plumbing-ai-receptionist
./scripts/setup-phase2.sh summit-plumbing
```

This creates (or confirms already exists, if rerun):

- **Operating Hours** "Metro Vancouver Business Hours" (`America/Vancouver`
  timezone) with time slots Mon–Fri 8am–5pm, Sat 9am–1pm.
- **Service Territory** "Metro Vancouver" (800 Robson St, Vancouver, BC).
- **4 Service Resources** (technicians): Dave Chen, Maria Santos,
  Kevin O'Brien, Priya Patel — each backed by a dedicated User record
  (Salesforce Platform license, `Standard Platform User` profile) that never
  logs in; it exists only so `ServiceResource.RelatedRecordId` has something
  to point to. All 4 are Primary members of Metro Vancouver.
- **4 Work Types**: Drain Cleaning (1h), Water Heater Install (3h), Leak
  Repair (2h), Emergency Call-out (1.5h) — linked to the territory.
- **30 seed customers** (Account + Contact + address) spread across
  Vancouver, Richmond, Burnaby, Coquitlam, New Westminster, North/West
  Vancouver, Surrey, Delta, and Langley.
- **17 seed appointments** (WorkOrder + ServiceAppointment + AssignedResource)
  spread across the next 7 days and all 4 technicians, so the calendar isn't
  empty for the demo.

Scripts live at `summit-plumbing-ai-receptionist/scripts/apex/setup/01`–`05`
and are individually idempotent (each checks for existing records before
creating). Note: this seed data writes `ServiceAppointment` times directly,
which is fine for pre-existing historical demo data — the Phase 3 Apex REST
API that the AI agent calls must **not** do this; it has to go through
`FSL.ScheduleService` / `FSL.AppointmentBookingService`.

The FSL managed package already ships 4 default Scheduling Policies (Customer
First, High Intensity, Soft Boundaries, Emergency) which Phase 3 uses for
`FSL.ScheduleService` calls. "Emergency" conveniently lines up with the
"Emergency Call-out" work type for later test scenarios.

### Manual setup required before the scheduling engine works

Discovered by live-testing `FSL.AppointmentBookingService`/`FSL.ScheduleService`
before writing Phase 3's Apex — these can't be scripted (they're UI-only or
license-gated actions):

1. **Create the Field Service permission sets.** App Launcher → *Field Service
   Admin* → *Field Service Settings* → *Permission Sets* → click "Create
   Permissions" on each tile. This generates `FSL_Admin_Permissions`,
   `FSL_Resource_Permissions`, `FSL_Dispatcher_Permissions`, etc. — none of
   these exist by default even after installing the package.
2. **Assign yourself `Field Service Admin Permissions` + `...License`** so
   your own user can call FSL Apex while testing/developing:
   ```
   sf org assign permset --name FSL_Admin_Permissions --target-org summit-plumbing
   sf org assign permset --name FSL_Admin_License --target-org summit-plumbing
   ```
3. **Turn OFF "Enhanced Scheduling and Optimization" (ESO).** Field Service
   Settings → Optimization → Activation. It was mysteriously **on by default**
   in this org, but has no authorized optimization user/profile connected —
   every scheduling call fails with a generic `Schedule optimization
   incomplete (System Code)` error until you turn it off. The classic
   (non-ESO) engine computes synchronously in Apex and needs no external
   service. Re-enabling ESO later would need its own OAuth-style setup (an
   "Optimization Profile and User") — out of scope for this demo.

**License cap that limits schedulable technicians to 2 of 4:** the FSL
scheduling engine requires a `ServiceResource.RelatedRecordId` User to hold
the "Field Service Scheduling" permission set license before
`IsOptimizationCapable` can be set to `true` on their resource. This trial
org has only **2** of those license seats. `scripts/apex/setup/02` assigns
them to Dave Chen and Maria Santos; Kevin O'Brien and Priya Patel remain as
real `ServiceResource` records (for a realistic-looking 4-person roster) but
the FSL engine will never assign them work. Buying more licenses would lift
this in a real org.

### Verified FSL Apex behavior (for Phase 3)

- `FSL.AppointmentBookingService.getSlots(saId, policyId, operatingHoursId, tz, exactAppointment)`
  performs a real callout (travel-time lookup) — the ServiceAppointment it's
  called against **must already be committed in a prior transaction** (no DML
  earlier in the same transaction, or you get `System.CalloutException: You
  have uncommitted work pending`). This is why the booking flow needs two
  separate Apex REST endpoints, not one.
- `FSL.ScheduleService.schedule(policyId, saId)` returns `null` on failure —
  no exception, no error message. Call `FSL.ScheduleService.getAppointmentInsights()`
  for a reason, though that method requires ESO and won't work with it off.
- On success, `FSL.ScheduleResult` exposes `.Service` (the updated
  ServiceAppointment) and `.Resource` (the assigned ServiceResource) — **not**
  `.serviceAppointment`/`.serviceResource` as the official docs' property
  table states (confirmed by compile error; likely a docs bug).
- `schedule()` automatically creates the `AssignedResource` junction record —
  no need to insert it manually.
- `WorkType.TimeframeStart`/`TimeframeEnd` must be set (we use 0–14 days) or
  `getSlots` searches a zero-width window and always returns empty.
- `AppointmentBookingSlot.interval.Start`/`.Finish` come back as **wall-clock
  values in the requested timezone, stuffed into the Datetime's UTC fields
  uncorrected** — e.g. an intended Pacific "8:00 AM" slot comes back
  internally labeled as UTC 08:00, not the true UTC instant (15:00 during
  PDT). Left uncorrected, displayed times are off by exactly the UTC offset.
  Fix: `slot.interval.Start.addSeconds(tz.getOffset(slot.interval.Start) / -1000)`.
  Found by comparing displayed slot times against known operating hours.

## Phase 3 — Apex REST API

`force-app/main/default/classes/` implements the agent-facing API at
`/services/apexrest/agent/v1/*`:

| Endpoint | Purpose |
|---|---|
| `lookupCustomer` | Find an existing customer by phone or email |
| `createCustomer` | Create Account + Contact + address (rejects out-of-territory cities) |
| `getSlots` | Get available appointment slots for a job type |
| `bookAppointment` | Book a chosen slot |
| `rescheduleAppointment` | Move an existing appointment to a new slot |
| `cancelAppointment` | Cancel an appointment |

**Architecture**: `IFieldServiceScheduler` is the seam around the FSL managed
package. `FSLFieldServiceScheduler` is the real implementation (calls
`FSL.AppointmentBookingService`/`FSL.ScheduleService`); `MockFieldServiceScheduler`
is what tests inject instead, via `FieldServiceSchedulerFactory`. Each REST
endpoint is a thin `@RestResource` class that parses the JSON body, delegates
to `AgentCustomerService` or `AgentSchedulingService`, and maps exceptions to
HTTP status codes (`AgentApiException` → 400, `AgentOutsideTerritoryException`
→ 422). Responses are `{"ok": true, "data": {...}}` or
`{"ok": false, "error": "...", "code": "..."}`.

**`getSlots` is a two-call flow, not one.** `FSL.AppointmentBookingService.getSlots`
performs a real callout, which can't happen in the same transaction as the
DML that creates the draft WorkOrder/ServiceAppointment (see "Verified FSL
Apex behavior" above). So:
1. Call `getSlots` with `customerId` + `jobType` (no `serviceAppointmentId`) →
   creates the draft appointment, returns `{"status": "pending", "serviceAppointmentId": "..."}`.
2. Call `getSlots` again with that `serviceAppointmentId` → returns
   `{"status": "ready", "slots": [...]}` with real availability.

This will be hidden from the AI agent in Phase 5 — the n8n sub-workflow does
both calls internally and exposes one clean `get_available_slots` tool.
`rescheduleAppointment` doesn't need this two-step dance for its "list new
slots" mode, since the appointment already exists from a prior transaction.

**Tests**: `AgentCustomerServiceTest`, `AgentSchedulingServiceTest`, and
`AgentApiRestTest` (33 tests total, 81% org-wide coverage).

**Important platform finding, discovered in Phase 4 while testing with the
real OAuth integration user (not the admin session used to build everything
else):** this Summer '26 org enforces CRUD/FLS by default for plain Apex
SOQL/DML — `[SELECT ...]`, `insert`, `update` — for a non-admin user, unlike
the classic Apex default of bypassing FLS/CRUD unless you opt in via `WITH
SECURITY_ENFORCED`. This first showed up as `ServiceAppointment.Status`
updates failing with "fields being inaccessible" in **test context only**
(same admin user, but Apex tests apparently enforce this even when live
execution as that user didn't) — the initial, narrower fix was
`Database.update(record, AccessLevel.SYSTEM_MODE)` on that one path. Once we
built the actual low-privilege integration user for Phase 4 and called the
API for real, the same issue appeared everywhere: `AgentConfig` couldn't
even see `WorkType`/`ServiceTerritory` records under `with sharing`. The
real fix was systemic: every service class (`AgentConfig`,
`AgentCustomerService`, `AgentSchedulingService`, `FSLFieldServiceScheduler`)
is now `without sharing`, and every SOQL/DML statement explicitly declares
`WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`. This is the architecturally
correct pattern for a backend integration API regardless of the underlying
platform-default question — the API enforces its own business rules
(territory checks, job type validation), not the calling user's raw object
permissions. **Lesson**: test integration APIs with the actual low-privilege
credential they'll run under, not just the admin session used to build them
— several bugs here were invisible until we did.

Note on `WITH SYSTEM_MODE` placement: it must come before `LIMIT`, not
after, or you get a confusing cascade of "Extra ';'" / "Variable does not
exist: WITH" compile errors.

Deploy + test:
```
cd summit-plumbing-ai-receptionist
sf project deploy start --source-dir force-app/main/default/classes --test-level RunLocalTests --target-org summit-plumbing
```

## Phase 4 — Authentication

**Integration user** (`scripts/apex/setup/06_integration_user.apex`, idempotent):
a dedicated User (`agent.integration@...`) the AI agent authenticates as.
Two profiles failed before landing on one that works — see the script's
comments for why ("Minimum Access - API Only Integrations" hit a default
Visualforce-page validation bug; "Standard Platform User" — the same
profile the technicians use fine — hit an Entitlement Management permission
error that didn't happen earlier in the session, suggesting something about
Field Service enablement changed org-wide default new-user behavior).
Settled on **"Standard User"** (full Salesforce license).

Assigned to this user:
- **`Agent_Integration_User`** (custom permission set, in
  `force-app/main/default/permissionsets/`) — Apex class access to the 6
  REST resource classes, plus API Enabled. Deliberately minimal: since the
  service layer runs in system mode, this user doesn't need object/field
  CRUD grants for the API to function.
- **`FSL_Agent_Permissions`** + **`FSL_Agent_License`** ("Field Service Call
  Center Rep") — required for `FSL.ScheduleService`/`AppointmentBookingService`
  to work at all; these enforce their own permission checks independent of
  Apex system mode (see Phase 1/3 findings).

**External Client App** (manual UI setup — OAuth apps can't be scripted):
1. Setup → App Manager → **New External Client App**.
2. Name: `Summit Plumbing AI Agent`. Enable OAuth.
3. Callback URL: any placeholder (e.g. `https://login.salesforce.com/services/oauth2/success`)
   — required by the form but unused by Client Credentials Flow.
4. OAuth Scope: **`api`** only ("Manage user data via APIs").
5. Flow Enablement: check **Enable Client Credentials Flow** only.
6. Create, then go to the app's **Policies** tab → Edit → under "OAuth Flows
   and External Client App Enhancements", check **Enable Client Credentials
   Flow** again (a separate toggle from the creation form) → set **Run As**
   to the integration user's username. Save.
7. Settings tab → Consumer Key and Secret → copy both into `.env` (see
   `.env.example`; never commit the real `.env`).

## Running the demo

Get a token and call any endpoint:
```bash
# .env holds SF_INSTANCE_URL, SF_CLIENT_ID, SF_CLIENT_SECRET
set -a; source .env; set +a

TOKEN=$(curl -s -X POST "${SF_INSTANCE_URL}/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${SF_CLIENT_ID}" \
  -d "client_secret=${SF_CLIENT_SECRET}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

# Look up a customer
curl -s -X POST "${SF_INSTANCE_URL}/services/apexrest/agent/v1/lookupCustomer" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"phone": "604-555-0101"}'

# Get slots: first call creates a draft appointment (status "pending")
curl -s -X POST "${SF_INSTANCE_URL}/services/apexrest/agent/v1/getSlots" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"customerId": "<contactId from lookupCustomer>", "jobType": "Drain Cleaning"}'

# ...then call again with the returned serviceAppointmentId for real slots (status "ready")
curl -s -X POST "${SF_INSTANCE_URL}/services/apexrest/agent/v1/getSlots" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"serviceAppointmentId": "<id from previous call>"}'

# Book a slot (use startIso/endIso from the slots list above)
curl -s -X POST "${SF_INSTANCE_URL}/services/apexrest/agent/v1/bookAppointment" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"serviceAppointmentId": "<id>", "slotStartIso": "2026-09-28T15:00:00Z", "slotEndIso": "2026-09-29T00:00:00Z"}'

# Cancel (by confirmationNumber, e.g. "SA-0034", returned from bookAppointment)
curl -s -X POST "${SF_INSTANCE_URL}/services/apexrest/agent/v1/cancelAppointment" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"confirmationNumber": "SA-0034"}'
```

Verified working end-to-end against the live org with the real OAuth
integration user: lookup → get slots → book (assigned Dave Chen, confirmation
`SA-0034`) → cancel, plus an outside-territory `createCustomer` call
correctly returning a 422.

## Secrets

All credentials (Salesforce OAuth client ID/secret, Claude API key, etc.)
live in a gitignored `.env` file — never hardcoded. Copy `.env.example` to
`.env` and fill in real values. See `summit-plumbing-ai-receptionist/.gitignore`.
