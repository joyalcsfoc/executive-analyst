# Executive Analyst — authority and scope

Gate 4, items 1 and 2. This page exists so the boundary is a decision someone
signed, not an assumption that happens to be true because nobody has built the
write path yet.

**Status:** DRAFT — unsigned. Phase 1 does not close until the owner line below
is filled in by a person.

## What this agent is

An advisory analytics assistant over five gold metric views. It reads. It
answers questions about production, inventory, supplier quality, revenue and
marketing, and it cites the period and source for every figure.

## What it may not do

No write-back to any system. Specifically, and not as an exhaustive list:

- No work orders, maintenance tickets, or purchase requests
- No schedule changes
- No machine parameter or setpoint changes
- No connection to MES, SCADA, historian, or any control system
- No free-form SQL that changes state — read paths only, against the fixed
  surface of five metric views, five facts and two graph functions

This is enforced at three layers, deliberately: Unity Catalog grants
(`src/security/grant_agent_readonly.sql`, proven by
`src/tests/assert_agent_readonly.sql`), the fixed Genie data surface, and the
input gate in `app/guards.py`. If any one of them were the only control, the
boundary would be an instruction — and an instruction can be argued with.

## What it is not evidence for

Answers from this agent are **not** a system of record and must not be used as
the basis for:

- Warranty claims or recall decisions
- Regulatory findings or submissions
- Supplier penalties, chargebacks, or contract disputes
- Any safety determination

Those come from the originating system. If an answer here disagrees with the
MES, the MES wins and the discrepancy gets raised — see Escalation below.

## Safety

The agent does not answer safety procedure questions, summarise them, or
paraphrase them. It points to the approved procedure and a responsible person
(`SAFETY_CONTACT` in `app/guards.py`). It will still answer analytical
questions about safety-related *events* — how often an interlock tripped, which
shift logs the most stoppages — because those are production data.

## Known limitation: shared identity

Until queries run as the signed-in user, everyone using the agent sees whatever
the shared service principal can see. Unity Catalog row filters and column masks
are the fix. Plan the pilot group accordingly.

## Escalation

| Situation | Goes to |
| --- | --- |
| Answer disagrees with the MES or system of record | _(name)_ |
| Suspected wrong number | _(name)_ |
| Safety question the agent refused | Plant EHS lead |
| Request to widen scope or add a write path | Owner below, in writing |

## Sign-off

| | |
| --- | --- |
| Owner (accountable for this scope) | _(name, role, date)_ |
| Reviewed by | _(name, role, date)_ |
| Next review | _(date — suggest 6 months, or on any scope change)_ |

Any change to "What it may not do" requires re-signing. Widening scope is not a
deployment decision.
