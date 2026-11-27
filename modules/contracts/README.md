# contracts module

Contract briefs, the requirement validator, budget, deadline, payout, reputation and
unlocks (Phase 5). Depends on building (to read the design), structure (stress test results) and
multiplayer (to share the board and the contract).

## Classes (api/)

| Class | What it is |
| --- | --- |
| `ContractBrief` | The brief format (plain data; see the file header for every requirement kind), the hand-written briefs (`authored()`, `authored_brief(id)`: detached house, primary school, police station), `normalize()` and `describe(req)` for the checklist wording. |
| `ContractValidator` | `assess(brief, model, structure_report)` → `{ok, items, passed, total, bonus, cost, budget, summary}`. Each item has `label`, `ok`, `progress` (0..1), `detail` (what is wrong) and `tip` (how to fix it). Drives the live checklist, the handover and the payout. |
| `ContractPayout` | `settle(brief, assessment, {days})` → fee, bonus, cost, late penalty, profit, reputation change, and explanation `lines`. |
| `ContractGenerator` | Deterministic brief generator across 16 building types, from bungalows to airport terminals (`internal/building_types.gd`): `generate(seed, type, reputation)`, `board(seed, reputation, n, done)`, `types_open(reputation)`. |
| `ContractCareer` | Money, reputation, history, unlocks (building types, materials, part kinds by reputation): `record(settlement)`, `is_unlocked`, `is_kind_unlocked(kind, catalog)`, `next_unlock()`. |
| `ContractsBus` | `Modules.bus("contracts")`: `board`, `accept(id)`, `active`, `assess()`, `set_structure_report(rep)`, `hand_over(days)`, `abandon()`, `career`. Host-validated events, join snapshot, save section `"contracts"`. |

## For other modules

- Design room: show `assess()` items as the requirement checklist, `career.is_kind_unlocked()`
  to grey out locked parts in contract mode, and `board` / `accept()` for the job board.
- Structure: contracts listens to `StructureBus.report_changed` and keeps `brief_result()`.
  A result counts only while the building is unchanged (checked by checksum); after an edit
  the structure requirement asks for a new test.
- Timelapse: the handover takes the schedule's length in days: `hand_over(int(schedule.days))`.

## Tuning

Budgets are matched to the building catalog's prices (a plain shell with fit-out comes to
about £900 to £1,200 per m2 of rooms) plus an 8% allowance for routed services, not to
real-world totals, which also include overheads. The hand-written briefs leave room for
services too (the test house is £151k plus about £12k of services against £180k). Deadlines are a first guess (60 days plus half a day per m2); tune both once the
timelapse schedule's lengths are known.

## Tests

`tools/run_tests.sh contracts`: the three briefs against test buildings (tests/building_kit.gd),
each kind of failure and its wording, the generator's range and determinism, payout, career,
and the board and contract shared by two players.
