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

## Running the demo

_(To be filled in as later phases land: Apex deploy, auth setup, n8n import,
test scenarios.)_

## Secrets

All credentials (Salesforce connected app client ID/secret, Claude API key,
etc.) live in a gitignored `.env` file — never hardcoded. See
`summit-plumbing-ai-receptionist/.gitignore`.
