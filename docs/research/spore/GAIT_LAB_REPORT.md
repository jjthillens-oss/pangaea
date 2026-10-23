# Gait Lab report (prototype 0a)

Status: PROTOTYPE results, 2026-10-23. The owner approved this build ("Build Gait Lab"). The code is in
`prototypes/creature-lab/` (see its README). Nothing in `game/` changed. The numbers were measured on the cloud test
machine (4 vCPU, no GPU, Godot 4.7.2 headless). They are not from the baseline PC, and the prototype is not
Windows-verified.

Inputs: only the GENESIS specs (`workstreams/locomotion.md` §2–§5 and §9, `PROCEDURAL_ANIMATION_SPEC.md`) and public
biomechanics. No Spore material and no community-tool material went into the build (the handoff rule in
`CHECKPOINT_1.md` §8).

## 1. Result

Every pass criterion in `workstreams/locomotion.md` §9 is met. The main finding is about cost. Godot's built-in
`TwoBoneIK3D` is accurate and cheap enough for legs, so for two-bone limbs we do not need our own solver (option A
holds). The expensive part is our planner, which is written in GDScript.

| # | Criterion | Result | Verdict |
| --- | --- | --- | --- |
| 1 | Foot slip < 2% of leg length per stance, walk and trot, all bodies | Max 0.0007% of leg length (rig, all drives including 60 s random) | Pass |
| 2 | Speed ratio long/short = √2 ± 5%; cadence ratio = 1/√2 ± 5% | 1.4142 and 0.7071, measured at walk, trot and run | Pass (by construction, see §3) |
| 3 | 180° reversal and 720° turn in place, no foot past reach; turn time within 10% of prediction | Stance feet stay within 0.97 of leg length; 720° in 2.07 s (short), 1.60 s (long), 2.40 s (hexapod), each matching its prediction | Pass |
| 4 | Byte-identical foot logs across two runs | Identical SHA-256 over 20 s random drive, all bodies | Pass |
| 5 | 60 s run, no NaN, no knee flips | Finite throughout; 0 knee flips on every drive | Pass |
| 6 | Cost for 50 quadrupeds (informational) | 2.93 ms per frame: planner 1.38, rig sync 0.41, IK solve plus measurement callback 1.14 | Over the provisional 1.5 ms budget, see §2 |

Sources: `prototypes/creature-lab/results/measurements.json` (from `tools/measure.gd`) and the domain tests
(`tests/run_tests.gd`, 34 checks, all passing).

## 2. Cost

| Creatures | Planner (GDScript) | Rig sync | IK solve + callback | Total ms/frame |
| --- | --- | --- | --- | --- |
| 1 | 0.09 | 0.02 | 0.08 | 0.20 |
| 10 | 0.38 | 0.10 | 0.28 | 0.76 |
| 50 | 1.38 | 0.41 | 1.14 | 2.93 |

- The IK work for each quadruped (4 legs, 13 bones) is about 0.02 ms, and that includes our GDScript measurement
  callback. That is well below the 0.2–0.3 ms per creature estimated for our own GDScript solver, so option A, the
  built-in IK, holds for legs.
- The planner costs about 0.027 ms per creature, which makes it the biggest cost. Two ways to bring it down:
  move it to native code with the skin work (0b needs native code anyway), or update mid-distance creatures every
  second frame (tiering is already in the spec).
- 50 creatures together cost 2.9 ms on this machine, against a 1.5 ms budget that the spec marked provisional. Per
  `PROCEDURAL_ANIMATION_SPEC.md` §8, the budget gets re-set now. Proposal: keep 1.5 ms for the near tier (about
  20 full-rate creatures by these numbers) and update the rest at reduced rates. The baseline PC is likely faster than
  this cloud machine, but nobody has measured it.

## 3. What the numbers do and do not show

- **Speed and cadence ratios pass by construction.** The gait table works in leg-relative (Froude) units, so √2 follows
  from the design. The test confirms the code implements that design. It does not show that the motion feels right.
- **Slip is near zero because every planned foot target is within reach** (0.97 of leg length) and the IK reaches it
  exactly. Slopes, uneven ground and bodies that cannot reach will be the real slip test.
- **Early lifts.** A foot lifts early if its hip would otherwise carry it out of reach. In steady walk, trot and run
  this happens 0 times. It happens during speed changes and sharp turns: about 25–35% of steps in the 60 s random drive
  (where the input jumps every 0.5 s), and 3–19 times per short scripted run, mostly at start-up and band changes. This
  is the fallback working as intended. Fewer early lifts on transitions is a tuning task.
- **Not covered:** body bob, pitch and roll, a spine, hip sway, knee direction per leg (every knee bends forward), slopes,
  odd bodies (3 legs, mixed lengths), skin. The motion looks stiff above the legs. Gait Lab only tests the legs.

## 4. Engine facts learned (OBSERVED, Godot 4.7.2)

- `TwoBoneIK3D` works on a skeleton generated in code, with a straight rest pose and a pole node. One modifier holds
  every leg as a separate setting.
- With `modifier_callback_mode_process = MANUAL`, `Skeleton3D.advance(dt)` queues the solve. The solve runs later in
  the same frame, not inside the call.
- The solved pose can be read only inside the `skeleton_updated` signal. After it, `get_bone_global_pose` returns the
  unmodified pose again. Anything that reads solved bones (measurements, attachments, our own visuals) must do it in
  that signal.
- Headless runs are frame-capped at about 7 ms, so wall-clock frame time cannot measure cost there. `tools/measure.gd`
  times each stage instead.
- Movie Maker mode (`--write-movie`, `--fixed-fps 60`) under Xvfb renders deterministic clips at about 13% of real time.

## 5. Media

Rendered with `tools/render_clips.sh`, using the Compatibility renderer under Xvfb: a 10 s demo drive per body (walk,
trot, run, a trotting left turn, stop), plus a run with all three bodies side by side. The contact sheets show one frame
per second. Delivered to the owner with this report. The video files are not committed.

## 6. Recommended next steps (each needs the owner's approval)

1. **0b spine skin + codec** as planned. It needs a native path, which could also host the planner.
2. Gait Lab follow-ups, small:
   - knee direction per leg;
   - body bob and pitch from the stance feet;
   - smoother band transitions to cut early lifts;
   - an odd-body test (3 legs, mixed lengths).
3. Re-set the animation budget as tiers (§2). Measure on the baseline PC when the owner can run the prototype.
4. Record **R307** in Spore (leg length versus speed), so this prototype's anatomy-driven speed can be compared with
   Spore's behaviour.
