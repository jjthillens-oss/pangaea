# Tideleaf marine-flora prop

An original stylized red algal tuft for Pangaea's proposed aquatic environment. It is an art-only deliverable and has no scene or gameplay integration. The reference organism is a red alga associated with seagrass, not a botanical seagrass.

`build_plant.py` is the editable geometry and material recipe. It creates `tideleaf.blend`, `tideleaf.glb`, and three gray plus three beauty studio views. `make_sheets.ps1` combines those views with the CC0 reference photo for paired review. The Blender source is the master; no Hunyuan/provider asset was used.

Build with the locally installed Blender 5.2 binary:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python assets\godfrey\plant\build_plant.py
& assets\godfrey\plant\make_sheets.ps1
```

The final shape, material, import, visual and scale results are recorded in `GATES.md`. `gray-comparison.png` and `beauty-comparison.png` pair the reference with three views each; `godot-review.png` is an actual screenshot from an isolated Godot 4.7.2 OpenGL Compatibility run. This directory intentionally contains only the asset and its evidence, not a production integration.
