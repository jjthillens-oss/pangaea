# Godfrey task queue

Godfrey is an external coding agent that Joshua runs on this repository. It works from a queue of GitHub issues, and
the studio's Claude threads review every pull request it opens before anything reaches `main`.

## How the queue works

- Each job is one open issue labelled **`godfrey-task`**. The issue holds the shared rules, the branch name, the base
  branch, the files it may touch and the acceptance criteria.
- Jobs labelled **`godfrey-later`** are waiting on other work (they would collide with a branch in flight). Godfrey
  skips them. The studio relabels them `godfrey-task` when they are clear.
- When Godfrey starts a job it comments `claimed by Godfrey` on the issue. When the PR is up it comments the PR link.
- Godfrey never merges, approves, enables auto-merge or pushes to `main`. The studio reviews, asks for changes on the PR,
  and merges.
- Bugs Godfrey finds while reviewing are filed as separate issues labelled **`godfrey-review`**.

## Standing prompt (sent to Godfrey by Joshua on 2026-10-23)

```text
You are Godfrey, a contributing engineer on Pangaea (github.com/jjthillens-oss/pangaea), an
original Godot 4 evolution game. Work through the task queue on your own until it is empty.

Loop:
1. List the open GitHub issues labelled `godfrey-task`, oldest first, and skip any that already
   have a "claimed" comment.
2. Comment "claimed by Godfrey" on the first one.
3. Create the branch named in the issue (`godfrey/<task>`) off the latest `main`.
4. Do the task exactly as written. Commit and push after every step.
5. Run the repo's tests. Open a PR that says "Closes #<issue>", with what you did, the test
   results and any open questions. Never merge it.
6. Comment the PR link on the issue, then go back to step 1.

Rules:
- Original work only. Never copy, decompile or use any code or assets from Spore or EA, and no
  GPL code (Thrive is off limits).
- Never push to `main`, never merge, and never force-push someone else's branch. Stay inside the
  files the task names.
- If you're blocked, comment the reason on the issue and move to the next one.
- If the queue is empty, do the jobs listed in the latest coordinator post the same way.
```

Notes for the studio:
- Where an issue names a different base branch (the creature-lab jobs), the issue wins over step 3.
- Godfrey's environment has no Godot. It can try `tools/setup_toolchain.sh` (downloads the pinned Godot into
  `.toolchain/`); if that fails its PRs say "tests not run locally". CI runs the full `tools/check.sh` gate on every PR,
  and the reviewing thread runs the tests itself before merging. Claims may be posted through the GitHub CLI or API
  (Joshua approved this on 2026-10-23).
- Joshua approved (2026-10-23 08:58) merging Godfrey PRs that pass our review and CI, without waiting for him.
- Keep at least one `godfrey-task` issue open. When the queue is empty the prompt falls back to the coordinator's
  list, which includes the jobs held as `godfrey-later`.

## Current queue (2026-10-23)

| Order | Issue | Branch | Base | Status |
| --- | --- | --- | --- | --- |
| 1 | #30 Architecture map | `godfrey/docs-onboarding` | `main` | ready |
| 2 | #31 Rival evolution prototype | `godfrey/rival-evolution` | `main` | ready |
| 3 | #32 Legless slither and stub-leg gait | `godfrey/legless-locomotion` | `claude/project-thread-uqwkit` | ready |
| 4 | #33 Skin volume at extreme swings | `godfrey/skinning-fix` | `claude/project-thread-uqwkit` | ready |
| 5 | #34 Test gaps and code review | `godfrey/test-review` | `main` | ready |
| 6 | #35 Aquatic and land era proposals | `godfrey/era-proposals` | `main` | ready |
| 7 | #36 Accessibility audit | `godfrey/accessibility-audit` | `main` | ready |
| 8 | #37 Non-blocking lint job | `godfrey/ci-lint` | `main` | ready |
| - | #38 Save fuzzing | `godfrey/save-fuzz` | `main` | later: after S1 saves land |
| - | #39 Performance pass | `godfrey/perf-pass` | `main` | later: after S1 lands |
| - | #40 Localisation prep | `godfrey/l10n-prep` | `main` | later: after PR #28 and S1 |

The creature-lab jobs (#32, #33) branch off the creature lab branch because the lab is not on `main` yet (PR #12).

## Routing reviews

| Area | Reviewing thread |
| --- | --- |
| Game code, saves, CI, performance, tests | Spore-style evolution game (engineering) |
| Creature lab (`prototypes/creature-lab/`, creature research) | Spore research protocol |
| Menus, UI strings, accessibility | Menus and UI |
| Docs and proposals | Engineering, with the owner for design calls |
