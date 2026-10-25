# Asset review gates (preparation only)

| Gate | State | Evidence needed |
| --- | --- | --- |
| CC0 provenance and actual image inspection | PASS | `PROVENANCE.md` and retained reference thumbnail; source/author/license reviewed on Commons |
| Shape-gray front, side and three-quarter | UNVERIFIED | Run Blender builder, inspect all three saved views and revise geometry |
| Defining three-piece silhouette at gameplay distance | UNVERIFIED | Inspect gameplay-distance material and gray views |
| PBR materials and neutral-light response | UNVERIFIED | Inspect Blender material render and isolated Godot render |
| GLB content, scale, origin and budget | UNVERIFIED | Parse GLB and inspect imported scene; record actual counts |
| Paired reference/result and close crops | UNVERIFIED | Generate sheet from final revision and open it for inspection |
| Godot visual review | UNVERIFIED | Pinned Godot import and actual rendered screenshot in isolated review project |

Three currently expected differences: photo is realistic, while model intentionally has stylized low-detail surfaces; the hidden underside is inferred; the source photo has a plate and studio highlights, which the asset excludes. Reassess after final renders. No acceptance claim has been made.
