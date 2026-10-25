# Isolated Godot review recipe

Make a temporary directory outside the game project. Copy `project.godot`, `review.gd`, and the parent folder's `bush-1.glb` into it. With Godot 4.7.2, run editor import first:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path <temporary-review-directory> --editor --import --quit
```

Then capture pixels with an actual OpenGL Compatibility renderer:

```text
Godot_v4.7.2-stable_win64_console.exe --path <temporary-review-directory> --rendering-method gl_compatibility --resolution 800x800 --script res://review.gd
```

The second command saves `godot-review.png` inside the temporary project. `--headless` cannot substitute for this visual capture because its dummy renderer returns no texture. Keep Godot's generated import files out of the source asset folder.
