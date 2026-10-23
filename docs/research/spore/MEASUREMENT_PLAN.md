# Measurement plan (recordings by the owner)

Status: PROPOSED, 2026-10-23. Labels as in `LEGAL_RESEARCH_BOUNDARIES.md`. Rows to fill are in
`GAMEPLAY_MEASUREMENTS.csv` (status `planned`).

## 1. Rules

- Play your own installed copy normally. Nothing attaches to the game: no trainers, memory readers, mods,
  injected overlays or frame-time hooks (EA User Agreement §7.C). Plain screen recording only.
- Clips contain EA's art. Keep them on your PC or in the project's private files. They never go into the GitHub
  repository, a public post or a GENESIS build. The repo refers to clips by file name and timestamp only.
- If you use Spore's built-in cheat console to skip ahead (for example to get DNA points), say so in the clip name
  and in the row's notes. Never use it inside a clip that measures progression.
- One question per clip. Short clips (under 2 minutes) are easier to analyse than long sessions.

## 2. Setup

- Recorder: Xbox Game Bar (Win+Alt+R) or OBS, **60 fps**, 1920×1080, the game in the same window mode each time.
- Game settings: note graphics quality and resolution once in a text file next to the clips; keep them fixed.
- Name clips `R<session>-<row id>-<take>.mp4`, for example `R3-R301-take2.mp4`.
- Before each measured action, park the creature still for one second, so the start frame is clear.
- Use the keyboard for movement in measured clips (a key press gives a crisp start frame; mouse clicks to move are
  harder to time).

## 3. Sessions

| Session | What to play | Rows | Time |
| --- | --- | --- | --- |
| R1 Cell | Start a new game in the Cell stage. Play it through once normally (one long clip is fine for R101–R104). Then short clips: swim straight across open water at full speed, from a full stop, five times (R105, R106). Note each zoom-out as the cell grows (R107). | R101–R107 | ~45 min |
| R2 Creature editor | In the Creature editor (or the Creature Creator), build a plain body. Add vertebrae until refused (R201). Shrink and grow the body to its limits (R202). Attach one leg pair and keep recording until it walks (R203, five times). Try symmetric and off-centre placement (R204). Add parts one at a time and watch the complexity meter (R205). Build four test bodies: no legs, three legs, two long plus four short legs, eight legs, and use the test drive to walk each one (R206). | R201–R206 | ~45 min |
| R3 Creature movement | In the Creature stage, on flat open ground: walk and sprint straight, five times each (R301, R302); start and stop with the keyboard (R303); circle a tree or rock at full speed (R304); stop suddenly and keep the camera still (R305); zoom fully in and out (R306). Repeat R301 after swapping only the leg parts. | R301–R306 | ~40 min |
| R4 Combat and social | Use each combat ability on the same NPC species five times (R401, R402); try to befriend the same species (R403); note DNA points for each result (R504). | R401–R403, R504 | ~40 min |
| R5 NPC behaviour | Approach an aggressive species slowly until it chases, five times (R501); run until it gives up (R502); count your pack at each brain level (R503). | R501–R503 | ~30 min |

Order (updated 2026-10-23 to the owner's priority): **R2 and R3 first** (creature editor, skin, rigging, animation
and locomotion), then R1, R4 and R5. R2 also covers rows R207–R211 and R308, R310, R311 (test drive); R3 also covers
R307 and R309.

The single most useful experiment is **R307**: give one creature the same feet on short legs and then on long legs
and compare top speed. A Spore designer wrote that shape did not change stats (S14). If that holds, it is the clearest
place for GENESIS to be better.

## 4. How values are extracted

The research thread does the analysis if you upload clips to the project files, or you can do it yourself.

- **Frames to time.** Step frame by frame (mpv: `.` and `,`; most editors work too). Time = frames ÷ 60. Error is
  ±1 frame at each end, so ±0.033 s per timing.
- **Body lengths as the ruler.** Spore's internal units are unknown and we will not look them up in game files. We
  measure on screen against the creature's own length at the same zoom: speed in body lengths per second, distances
  in body lengths. This is enough to compare feel with GENESIS (which measures the same way).
- **Repeats.** Five takes for timings and speeds; report the median as `value` and half the range as
  `uncertainty`.
- **Result type** (column `result_type`): `observed` (read or counted directly from footage), `estimated`
  (measured with a ruler or derived, with error), `independently verified` (two methods or two sources agree).
- **Confidence** (column `confidence`): high (repeatable, small spread), medium (some spread or one source),
  low (one take or a judgement call).
- **Label**: every recorded value is OBSERVED (the `result_type` column says whether it was estimated). Nothing
  from recordings becomes CONFIRMED as a statement about Spore's code.

## 5. What happens to the numbers

They are comparison targets for feel, never constants copied into GENESIS tuning data
(`LEGAL_RESEARCH_BOUNDARIES.md` §6). When a GENESIS prototype exists, the same rows are measured on it with
`subject=genesis` and compared side by side.
