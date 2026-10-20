---
name: tflab-aws
description: Stand up, break, test and tear down the tflab-aws two-region EKS lab (Sydney primary, Melbourne standby, Cilium, RDS PostgreSQL replica, Route 53 failover) with Terraform, failure drills, CloudWatch alarms and a Playwright regression suite. Use for any request to run, demo, drill, test, cost-check, tear down or extend this lab.
---

# tflab-aws lab operator

You operate a cost-capped AWS lab from the repo root. Read `docs/PLAYBOOK.md` once per session
for architecture, alarms and recovery; the files in this skill folder are the step-by-step runbooks.

## Ground rules (never skip)

1. **Cost first.** The lab costs ~USD 0.50-0.70/hr while up. Before standing it up, say so. After
   every session, end with teardown (`teardown.md`) unless the user explicitly keeps it running.
2. **Identity, not keys.** Use the signed-in admin profile locally or GitHub Actions OIDC.
   Never create access keys, never print or commit secrets, never put credentials in files.
3. **Destructive drills need explicit confirmation**: `failover`, `region-blackout`,
   `promote-replica`, and anything that deletes data. Ask, then pass `--yes`.
4. **No placeholders.** If a value is missing (domain, email, region), ask for it - don't invent it.
5. **Prefer the workflows** (`gh workflow run up.yml|down.yml|drill.yml|regression.yml`) when the
   user is away from a terminal; prefer `make` targets when working locally.

## Pick the runbook

| User wants to...                                   | Read            |
|----------------------------------------------------|-----------------|
| set up a new AWS account / GitHub repo for the lab | `setup.md`      |
| start the lab                                      | `standup.md`    |
| break something / demo alarms / measure RTO, RPO   | `drills.md`     |
| check front end + API still work                   | `regression.md` |
| stop paying / end the session                      | `teardown.md`   |
| look inside: nodes, Cilium, Hubble flows, encryption | `observe.md`  |
| something failed                                   | `troubleshooting.md` |
| improve this skill or the lab                      | `improve.md`    |

## Session shape (memory hook: UP-BREAK-PROVE-DOWN)

1. **UP** - `standup.md`; confirm `https://app.mimidog.click` serves Sydney.
2. **BREAK** - one drill at a time from `drills.md`; note the time it started.
3. **PROVE** - alarm email arrived, CloudWatch alarm state, RTO/RPO output, `regression.md` passes.
4. **DOWN** - `teardown.md`; confirm the leftovers sweep is clean.

Report results to the user as: drill -> expected signal -> observed signal -> time to detect ->
time to recover. Flag any drill whose observed signal differs from the playbook - that's a
candidate improvement for `improve.md`.
