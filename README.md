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

**Nothing needed manual UI setup for this phase** — the FSL managed package
already ships 4 default Scheduling Policies (Customer First, High Intensity,
Soft Boundaries, Emergency) which Phase 3 will use for `FSL.ScheduleService`
calls. "Emergency" conveniently lines up with the "Emergency Call-out" work
type for later test scenarios.

## Running the demo

_(To be filled in as later phases land: Apex deploy, auth setup, n8n import,
test scenarios.)_

## Secrets

All credentials (Salesforce connected app client ID/secret, Claude API key,
etc.) live in a gitignored `.env` file — never hardcoded. See
`summit-plumbing-ai-receptionist/.gitignore`.
