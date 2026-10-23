# Legless and stub-leg Gait Lab report

Status: PROPOSED prototype. This is original Godot 4.7.2 work based on the project's
creature descriptions. It is not production locomotion or a dynamics simulation.

## Method

The spine-only `s1_snake` uses a head-to-tail travelling yaw wave at 1.25 Hz, 1.25
waves along the body and 8 degrees per vertebra. Alternating brief belly contacts
approximate ground traction. Its commanded maximum speed uses capped body length
and vertebra count. The two-joint short-legged `s1_tiny` uses alternating paired
leg lifts at 2 Hz and a conservative translational and turning limit. The existing
generated `SpineRig` supplies the mesh and bones; the new adapter applies the poses.

`tests/ground_drive_checks.gd` runs both descriptions for 3,600 steps at 60 Hz
with the existing deterministic `random` drive seed 17. It checks finite positions,
orientation, velocity, phase and contact anchors; nonzero travel; maximum contact
slip; and root pitch/roll. Contact slip is maximum displacement of a nominal
planted belly point or foot from its position at contact onset, divided by body
length or short-leg length. It includes turns. The flat-ground controller holds
the root level by design; the pitch/roll check detects accidental nonfinite or
nonlevel output, not dynamic tipping under gravity.

## Headless measurements

Godot 4.7.2 stable, Windows headless, `tests/run_tests.gd`:

| Check | Result | Gate |
| --- | ---: | ---: |
| Slither maximum at 1 m / 8 vertebrae | 0.093 m/s | Increasing |
| Slither maximum at 2 m / 8 vertebrae | 0.186 m/s | Increasing |
| Slither maximum at 2 m / 20 vertebrae | 0.286 m/s | Increasing |
| Slither cap at extreme size/count | 0.550 m/s | At most 0.550 m/s |
| Snake 60 s absolute travel | 12.874 m | Nonzero |
| Snake maximum nominal belly slip | 8.46% of body length | At most 12% |
| Tiny 60 s absolute travel | 0.175 m | Nonzero |
| Tiny maximum nominal foot slip | 19.27% of short-leg length | At most 25% |
| Both 60 s state/pitch/roll | Finite, 0 degrees | Finite, at most 5 degrees |

These are controller/contact-point measurements, not measurements of rendered
pixels, terrain interaction or physical friction. The tiny body's maximum speed
is intentionally low given its short reach. A later dynamics pass should verify
traction and balance on slopes and uneven ground, and visual review should check
wave and skin appearance in the full renderer.

## Verification

`tests/run_tests.gd`, `run_spine_tests.gd`, `run_stage1_tests.gd` and
`run_editor_tests.gd` all ended with `FAILURES: 0`. Headless scene smoke runs of
`walker_lab.tscn` with `s1_snake` and `s1_tiny` loaded without script errors.
`run_stage1_tests.gd` still reports its existing known `s1_tiny` posed-surface
miss, which is outside this gait change.
