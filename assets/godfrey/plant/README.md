# Tideleaf marine-flora prop

An original stylized red algal tuft for Pangaea's proposed aquatic environment. It is an art-only deliverable and has no scene or gameplay integration. The reference organism is a red alga associated with seagrass, not a botanical seagrass.

`build_plant.py` is the editable geometry and material recipe. It creates `tideleaf.blend`, `tideleaf.glb`, and three gray plus three beauty studio views. `make_sheets.ps1` combines those views with the CC0 reference photo for paired review. The Blender source is the master; no Hunyuan/provider asset was used.

Build with the locally installed Blender 5.2 binary:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python assets\godfrey\plant\build_plant.py
& assets\godfrey\plant\make_sheets.ps1
```

The shape, material, import, visual and scale gates are recorded in `GATES.md` after the export is inspected. This directory intentionally contains only the asset and its evidence, not a production integration.
