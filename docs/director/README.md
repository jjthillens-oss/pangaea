# The director's office

Status: CONFIRMED operating model (owner approval 2026-10-25 05:09 UTC, "I approve"). Numbers in the rubrics and
the backlog order are PROPOSED tuning that the director may adjust; the tiers, the budget and the routines below
need the owner to change them.

Pangaea runs as an AI studio. Claude is creative and game director; Joshua is owner and executive producer and
approves milestones. This folder holds what agents check their work against, so fewer calls need him.

| File | What it is |
| --- | --- |
| `docs/director/HANDBOOK.md` | The vision as rules: non-negotiables, the Spore pillars per stage, and case law (the owner's past calls) |
| `docs/director/rubrics/visual.md`, `docs/director/rubrics/design.md`, `docs/director/rubrics/feel.md` | Scored review rubrics with reference frames |
| `docs/director/backlog.json` | The Bible's M2 to M5 exit evidence as end-to-end features |
| `docs/director/progress.md` | The running log every scheduled run reads first and appends to |
| `docs/director/templates/task_brief.md`, `docs/director/templates/handoff.md` | Bible section 21 templates |

## Approval tiers

When unsure which tier applies, take the higher one. A reviewer that finds a change filed under the wrong tier fails it.

**Tier 1, agents decide.** Code, refactors, tests, tools, performance work, tuning numbers inside the Bible's
ranges, drop-in asset swaps that keep ids, names, sockets and scale, Godfrey PR merges after review and CI, bug
fixes, CC0 resources. Merge when CI is green and the reviewer passes it. Log as PROPOSED in `docs/DECISIONS.md`.

**Tier 2, weekly batch.** New looks and palettes, new parts and creatures, feel changes, a stage's pacing, HUD and
menu layouts, a choice between two designs that both fit the Bible, perf limit changes. Build the director's
recommendation and merge it; list it in the Sunday report for the owner to keep, change or revert.

**Tier 3, always the owner.** Scope or milestone changes; era count, names or boundaries; save schema versions; the
art pipeline; any money (contractors, music licences, paid tools); new dependencies or network use; dropping a
Spore pillar; departing from the Bible; the M2 benchmark sign-off; anything public (Steam, store page); any
ultracode outside the weekly ultracode day. Use a decision card with a recommendation and keep doing independent work.

## Budget (CONFIRMED 2026-10-25)

The weekly plan resets Wednesday 06:00 UTC.

- **Wednesday to Monday: 10% of weekly usage a day**, solo work only (one agent per thread, Opus medium, no
  Workflow fan-outs, no subagents). If usage is ahead of pace at the 06:00 plan, that day is reviews only.
- **The owner keeps 5 to 10%** for his own tasks.
- **Tuesday is ultracode day**: whatever is left (about 30% plus anything unspent). Monday's plan names the jobs,
  usually the week's hardest multi-track build or a milestone review sweep. It runs from a fixed list, merges what
  is green and stops before the Wednesday reset.
- Routine runs: the daily plan, the playtest capture and the research digest each day, plus the Sunday report. At most 3 task briefs a day and 2 active builder threads. Nothing re-schedules itself or
  loops overnight. The owner keeps extra usage off, so the cap stops work instead of billing.
- The $250 cloud credit is nearly spent ($55 left on 25 Oct 05:47). When the credit session stops, its eight
  `claude/credit-*` branches are taken over by their owners (backlog items T-01 to T-08), ahead of new features and
  within the 2-builder cap.
- Agents cannot read the usage meter reliably. Each run logs what it ran in `docs/director/progress.md`; the owner's usage
  screenshots, when he sends them, correct the estimate.

## Routines

| Routine | When (UTC) | Job |
| --- | --- | --- |
| Daily plan | 06:10 daily | Read `docs/director/progress.md`, `docs/director/backlog.json`, the git log, last night's build and the playtest scores. Write up to 3 task briefs, send them to the owning threads or as `godfrey-task` issues (keep 3 open), post a 5-line plan in project chat. Check the budget pace. |
| Nightly build | 09:17 daily | `.github/workflows/nightly.yml` (GitHub Actions, no Claude usage) |
| Research digest | 13:47 daily | Community signals and permissive tools; opens a PR for the owner |
| Nightly copy and playtest capture | 11:10 daily | Run the scripted smokes under xvfb, copy the nightly zip to the project builds folder, capture frames at gameplay camera, score them against the rubrics as a separate reviewer, file failures as issues, log scores. |
| Weekly report | Sunday 18:10 | One Artifact page: build link, merges, rubric trends, the Tier 2 batch, Tier 3 cards, next week's plan, usage against budget. |

## Every session

Follow Bible section 21, plus the long-running-agent practice this office is built on:

1. Read `docs/director/progress.md`, `git log --oneline -20`, the backlog entries you own, and the handbook sections you touch.
2. Work one backlog feature at a time. Agree its sprint contract (the evidence that proves it) before building.
3. Change only `passes` and `evidence` in `docs/director/backlog.json`; only the director adds, removes or reorders features.
4. Builders never grade their own work. A feature passes only after a separate review against the rubrics.
5. End with committed, pushed, mergeable work and a `docs/director/progress.md` line.
