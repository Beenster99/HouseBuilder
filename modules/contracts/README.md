# contracts module

Contract briefs, the requirement validator, budget, deadline, payout, and the architecture
firm's XP, tiers and unlocks (Phase 5). Depends on building (to read the design), structure (stress test results) and
multiplayer (to share the board and the contract).

## Classes (api/)

| Class | What it is |
| --- | --- |
| `ContractBrief` | The brief format (plain data; see the file header for every requirement kind), the hand-written briefs (`authored()`, `authored_brief(id)`: detached house, primary school, police station), `normalize()` and `describe(req)` for the checklist wording. |
| `ContractValidator` | `assess(brief, model, structure_report)` → `{ok, items, passed, total, bonus, cost, budget, summary}`. Each item has `label`, `ok`, `progress` (0..1), `detail` (what is wrong) and `tip` (how to fix it). Drives the live checklist, the handover and the payout. |
| `ContractPayout` | `settle(brief, assessment, {days})` → fee, bonus, cost, late penalty, profit, XP earned, and explanation `lines`. |
| `ContractTiers` | The firm's seven tiers, from small works (garden studios, garages, pavilions) to major projects (hospital wings, airports): `tier_for(xp)`, `info(tier)`, `progress(xp)`, `MAX_XP`, `xp_text`. |
| `ContractGenerator` | Deterministic brief generator across 19 building types (`internal/building_types.gd`, each with its tier): `generate(seed, type, tier)`, `board(seed, tier, n, done)`, `types_open(tier)`, `types_of_tier(tier)`. About 70% of briefs are for the firm's own tier. Each brief carries `tier` and `xp`. |
| `ContractCareer` | Money, XP, tier, history, unlocks (building types, materials, part kinds by tier): `record(settlement)`, `tier()`, `progress()`, `set_xp()`, `is_unlocked`, `is_kind_unlocked(kind, catalog)`, `next_unlock()`, `unlocks_at(tier)`. |
| `ContractsBus` | `Modules.bus("contracts")`: `board`, `accept(id)`, `active`, `assess()`, `set_structure_report(rep)`, `hand_over(days)`, `abandon()`, `career`, `set_xp(xp)` (testing), `make_board()` (the big-screen page), `make_debug_section()`. Host-validated events, join snapshot, save section `"contracts"`. |

## For other modules

- Design room: the hall's wall screens show channel `contracts.board` ("Contracts", flag
  `contracts.board`), which has the tier and XP bar, the board with Accept buttons, the live brief
  and the next tier. Settings > Debug has "Contracts: firm XP" (Max XP, Next tier, +1,000, Reset),
  shown while `ui.debug_tab` is on.
- Design room: show `assess()` items as the requirement checklist, `career.is_kind_unlocked()`
  to grey out locked parts in contract mode, and `board` / `accept()` for the job board.
- Structure: contracts listens to `StructureBus.report_changed` and keeps `brief_result()`.
  A result counts only while the building is unchanged (checked by checksum); after an edit
  the structure requirement asks for a new test.
- Timelapse: the handover takes the schedule's length in days: `hand_over(int(schedule.days))`.

## Tuning

XP: a tier needs about four contracts at the tier below (`ContractTiers.TIERS` award vs the
next threshold). A pass earns the brief's XP, plus 10% per bonus goal met and less 10% per week
late (at least a quarter). A fail earns none. Abandoning costs half the brief's XP, but never
a tier.

Budgets are matched to the building catalog's prices (a plain shell with fit-out comes to
about £900 to £1,200 per m2 of rooms) plus an 8% allowance for routed services, not to
real-world totals, which also include overheads. The hand-written briefs leave room for
services too (the test house is £151k plus about £12k of services against £180k). Deadlines are a first guess (60 days plus half a day per m2); tune both once the
timelapse schedule's lengths are known.

## Tests

`tools/run_tests.sh contracts`: the three briefs against test buildings (tests/building_kit.gd),
each kind of failure and its wording, the generator's range and determinism, payout, career,
and the board and contract shared by two players.
