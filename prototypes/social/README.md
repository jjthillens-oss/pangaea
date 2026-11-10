# Social stage prototype — PROPOSED

This standalone Godot 4 sketch explores the Social era described in the [stage plan](../../docs/stages/social-plan.md). It is separate from the creature-stage befriending interaction and from production saves. All people, colors, responses, numbers, and controls here are PROPOSED. It uses original code and engine drawing only.

## Play

Launch this folder as a Godot project. The screen shows three named individuals (ara, bren, cyra), each one's disposition, food and danger needs, and current trust. The highlight marks the selected person.

- **1, 2, 3:** select an individual.
- **G:** greet and read a cautious or welcoming response.
- **S:** share one food when someone needs it.
- **W:** warn a person who still faces danger.
- **C:** challenge, spending two stamina and risking trust.
- **P, X:** promise help, or break that promise.
- **F:** carry one route food past danger together, if trust is at least four.
- **A:** spend insight from a successful shared route on a clearer signal.

The experiment follows **meet → signal → read response → cooperate or contest → remember → adapt**. A successful shared route moves one item from the route to the player's food, costs one stamina, and grants one insight. Refused actions do not spend resources. The adaptation adds one trust point to future conversations, with a single purchase cap.

## Rules and evidence

The seed deterministically sets dispositions and needs. Every person has a stable ID. When two candidates have the same trust, the lower ID sorts first. State snapshots use ID order, so equal seeds and action sequences produce byte-identical results.

Each encounter ages that individual's memory. Help has a three-encounter lifetime and adds two trust while remembered. A broken promise has a six-encounter lifetime and subtracts three trust. A contest leaves a shorter negative memory. Thus two recent acts of help can turn a cautious greeting into a welcome, whereas a broken commitment outlasts kindness. These values are prototype tuning, not adopted game rules.

The headless tests exercise seeded replay, tie order, individual memory, later responses after two helps, the longer broken-promise memory, trust-gated cooperation and food conservation, adaptation, contest cost, and failures that spend nothing:

`Godot_v4.7.2-stable_win64_console.exe --headless --path prototypes/social --script res://tests/run_tests.gd`

## What remains open

This scene has no embodied travel, group-order acknowledgement, recruitment/dismissal, cross-generation learning, leader-loss recovery, streaming, save migration, controller support, captions, sound, or rendered visual acceptance. It does not implement a rhythm minigame or replace the creature-stage friend path.

Owner decisions: how long significant memories last, which promises should require confirmation, when cooperation offers a companion role, how anatomy changes signaling without blocking accessible controls, and which individual memories enter a future save. The Bible's continuity requirement would need a separately approved production slice and persistence contract.
