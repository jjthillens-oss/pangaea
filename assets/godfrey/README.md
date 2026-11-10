# Godfrey's review assets

Candidate props from Godfrey's asset PRs (#176, #177, #183 to #187), each with its Blender source, GLB and review
sheets. They are not production assets: nothing in the game loads them, and the owner has not judged them against the
art bar yet. `.gdignore` keeps Godot from importing this folder, so the review images and reference photos stay out of
the exported game.

To adopt one, move its `.blend` to `assets/source/blender/`, its GLB to `assets/export/` and write its record in
`assets/records/` (`tests/test_assets.gd` enforces all three).
