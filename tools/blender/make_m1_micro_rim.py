"""Build pool_rim, the microscopic world's dish wall: the pool's edge once the floor is gone
(docs/micro-world-plan.md in the project files, commit C3).

An engineering placeholder. The owner is still choosing how the world's edge looks (a stone dish
wall, a membrane or brighter water), and production art belongs to make_m1_production.py, so the
record stays a blockout until the look is approved. The asset is not placed in the pool scene yet.

Writes (Bible section 16):
  assets/source/blender/pool_rim.blend   (editable source)
  assets/export/pool_rim.glb             (engine export)
  assets/records/pool_rim.json           (asset record: PROPOSED, a blockout, not visually approved)

Run with the pinned Blender (see docs/TOOLCHAIN.md):
  blender --background --python tools/blender/make_m1_micro_rim.py
or with the bpy module:
  python tools/blender/make_m1_micro_rim.py

One surface of revolution, inner edge to outer edge:
  * the skirt, an inward-facing wall just outside the cell's reach, from SKIRT_DEPTHS[0] up to
    the swim plane's underside, where the engine's height fog fades it into the fluid;
  * the floor's rim (make_m1_blockouts.floor_height from r 39 out, rocky noise included): the lip
    rises through the swim plane where the collision stops the cell, peaks at +1.2 m at r 42 and
    settles to the +1.0 m shelf, which runs past what the widest zoom shows from the wall.

Shape and colour are kept apart, so art can swap the look without touching the contract. The
shape is the gameplay contract that tests/test_assets.gd checks from the vertices alone, never the
material. The colour is vertex colours (dark, cool stone on the lip and shelf, a lighter navy on
the wall's shadowed inner face) drawn by assets/export/M_PoolRim.tres, which pool_rim.glb.import
maps; a new look points that import at another material.

The output is deterministic: fixed formulas and mathutils.noise at fixed offsets, no random
numbers (see make_m1_blockouts.py on the few bytes of a .blend that Blender takes from the clock).
"""
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first, which provides mathutils)
import make_m1_blockouts as mb  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

ASSET_ID = "pool_rim"
REVIEW_STATE = "blockout - M1 micro world, not visually approved"
GENERATOR = "tools/blender/make_m1_micro_rim.py"
BUDGET = 4000   # the plan's "about 4k"; also in tests/test_assets.gd

# Gameplay values the wall is built to fit (game/data/pool_m1.json, pool block): the collision
# stops the cell's side at the hard radius, so its centre never passes r 39, and the cell reaches
# 0.39 m below the swim plane. tests/test_assets.gd checks the export against the layout.
HARD_RADIUS = 39.5
CELL_CLEARANCE = (39.0, -0.45)    # inside this radius the rim stays at or below this height
INNER_EDGE = (38.5, 38.8)         # the wall's inner face lies in this band at every azimuth
PLANE_CROSSING = (HARD_RADIUS, HARD_RADIUS + 1.0)   # the surface crosses y 0 in this band

# Shape (PROPOSED). 128 segments put a vertex every 1.9 m around the lip; the curve is off by at
# most 12 mm between them. Rings are spent where the profile bends: the wall's top edge and the
# lip's S-curve every 0.5 m (its crossing of the swim plane lands within 4 cm of the smooth
# curve's), and only a few on the straight skirt and the flat shelf.
RIM_SEGMENTS = 128
SKIRT_RADIUS = 38.66
SKIRT_WOBBLE = 0.06               # radial undulation of the wall, so it is not a perfect cylinder
# The skirt reaches 30 m down, where the height fog is 93%. The plan's first sketch stopped at
# -6.4 m (38% fog) and its fallback at -20 m (82%), which in a Compatibility probe of the plan's
# look still left a faint step (2.7 L*) where the skirt ends, across the lower screen of a view of
# the north wall. Deeper costs no triangles.
SKIRT_DEPTHS = (-30.0, -12.0, -4.0, -1.0)
SKIRT_BEVEL = (38.78, -0.56)      # rounds the wall's top edge into the floor's rim
RIM_RINGS = (39.0, 39.5, 40.0, 40.5, 41.0, 41.5, 42.0, 43.5, 45.0, 52.0, 66.0)

# Colour (linear RGB, stored sRGB-encoded as in the other vertex-coloured assets; PROPOSED).
# The lip and shelf are dark, cool stone, about sRGB (0.19, 0.20, 0.23): the plan's darkened stone
# turned toward blue, so the edge reads as stone and the coral cell and food read first. The
# wall's inner face gets no sun on the north side (the light comes from the north-west and above),
# only the blue ambient, which turned the stone near black there; from WALL_AT_M down it takes a
# lighter navy, RIM_WALL, so the shadowed wall reads blue, never black, and fades into the fluid
# with depth. In a Compatibility probe of the plan's look (docs/DECISIONS.md) the sunlit stone
# renders at L* 34 to 38 and the north wall at L* 18 by the cell (6 in stone), against fluid at
# L* 24 to 32 and the coral cell at 54 or more. Blue at least equals green, which at least equals
# red, in every colour: nothing leans toward food's yellow-green or the threat's pink.
RIM_STONE = (0.030, 0.034, 0.045)
RIM_WALL = (0.070, 0.130, 0.190)
WALL_AT_M = (0.6, 1.0)            # depth over which the bevel's stone turns into the wall's navy
RIM_MOTTLE = 0.12                 # gentle light and dark mottling of the stone, as a share of its colour


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


def _around(a, scale):
    """A point on a circle in noise space, so noise around the rim joins up where it starts."""
    return Vector((math.cos(a) * scale, math.sin(a) * scale, 0.0))


def _wobble(a, z):
    """The wall's radial undulation at angle a and height z: bumps about 10 m apart around the rim."""
    return SKIRT_WOBBLE * noise.noise(_around(a, 4.0) + Vector((0.0, 0.0, z * 0.15 + 2.7)))


def _color(x, y, z):
    """Linear RGB at a vertex: mottled stone, turning into the wall's navy below the bevel."""
    mottle = 1.0 + RIM_MOTTLE * noise.noise(Vector((x * 0.2 + 3.3, y * 0.2 - 1.7, z * 0.2 + 5.1)))
    wall = bc.smoothstep((-z - WALL_AT_M[0]) / (WALL_AT_M[1] - WALL_AT_M[0]))
    return tuple(mottle * (s + (w - s) * wall) for s, w in zip(RIM_STONE, RIM_WALL))


def _crossings(rings):
    """Where each segment's profile crosses z 0, by linear interpolation along its edges."""
    out = []
    for j in range(RIM_SEGMENTS):
        for i in range(len(rings) - 1):
            (r0, z0), (r1, z1) = rings[i][j], rings[i + 1][j]
            if z0 < 0.0 <= z1:
                out.append(r0 + (r1 - r0) * (0.0 - z0) / (z1 - z0))
                break
    return out


def build_pool_rim():
    rim_mat = bc.material("M_PoolRim", (1.0, 1.0, 1.0), 0.9, vertex_colors="RimColor")
    # rings[i][j] is (r, z) of ring i at segment j: the skirt bottom first, the shelf's edge last.
    rings = []
    for r, z in [(SKIRT_RADIUS, z) for z in SKIRT_DEPTHS] + [SKIRT_BEVEL]:
        rings.append([(r + _wobble(2.0 * math.pi * j / RIM_SEGMENTS, z), z) for j in range(RIM_SEGMENTS)])
    skirt = [r for ring in rings[:len(SKIRT_DEPTHS)] for r, _ in ring]
    for r in RIM_RINGS:
        ring = []
        for j in range(RIM_SEGMENTS):
            a = 2.0 * math.pi * j / RIM_SEGMENTS
            ring.append((r, mb.floor_height(r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    verts = []
    for ring in rings:
        for j, (r, z) in enumerate(ring):
            a = 2.0 * math.pi * j / RIM_SEGMENTS
            verts.append((r * math.cos(a), r * math.sin(a), z))
    # The profile runs up the wall and then outward, so this winding (as the floor's) turns every
    # face toward the pool: inward on the skirt, up on the lip and shelf.
    index = lambda i, j: i * RIM_SEGMENTS + j % RIM_SEGMENTS  # noqa: E731
    faces = []
    for i in range(len(rings) - 1):
        for j in range(RIM_SEGMENTS):
            faces.append((index(i, j), index(i + 1, j), index(i + 1, j + 1), index(i, j + 1)))
    colors = [_color(*v) for v in verts]
    # UVs only so the importer can build tangents (no textures): around the rim, and down the
    # profile in metres over 70 (the skirt from 0.0, the shelf's edge at about 0.7).
    def uv(co):
        r = math.hypot(co.x, co.y)
        along = (co.z - SKIRT_DEPTHS[0]) if r < 38.95 else (SKIRT_BEVEL[1] - SKIRT_DEPTHS[0]) + (r - SKIRT_BEVEL[0])
        return (0.5 + 0.5 * math.atan2(co.y, co.x) / math.pi, along / 70.0)
    rim = bc.mesh_object("PoolRim", verts, faces, [rim_mat], fix_normals=False, uv=uv,
                         vertex_colors=("RimColor", colors))
    # Self-checks of the gameplay contract (tests/test_assets.gd checks the export the same way).
    bpy.context.view_layer.update()
    for poly in rim.data.polygons:
        c = poly.center
        inward = -Vector((c.x, c.y, 0.0)).normalized()
        _check(poly.normal.z + poly.normal.dot(inward) > 0.0, "pool_rim: every face looks up or into the pool")
    radii = [math.hypot(v[0], v[1]) for v in verts]
    _check(INNER_EDGE[0] <= min(radii) and max(skirt) <= INNER_EDGE[1], f"pool_rim: the wall's inner face is in r {INNER_EDGE}")
    crossings = _crossings(rings)
    _check(len(crossings) == RIM_SEGMENTS and PLANE_CROSSING[0] <= min(crossings) and max(crossings) <= PLANE_CROSSING[1],
           f"pool_rim: the surface crosses the swim plane in r {PLANE_CROSSING} all round")
    inside = [v[2] for v, r in zip(verts, radii) if r <= CELL_CLEARANCE[0] + 1e-6]
    lip = [v[2] for v, r in zip(verts, radii) if 41.5 <= r <= 43.0]
    shelf = [v[2] for v, r in zip(verts, radii) if r >= mb.FLOOR_SHELF[0]]
    _check(max(inside) <= CELL_CLEARANCE[1], "pool_rim: at or below -0.45 m inside r 39")
    _check(min(lip) > 0.8, "pool_rim: lip above +0.8 m over r 41.5-43")
    brightest = max(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] for c in colors)
    return {
        "purpose": "M1 microscopic world's edge (engineering placeholder until the owner picks the look): a dark dish wall that drops from the swim plane into the fluid where the collision stops the cell, the floor's rim lip and a shelf out past the edge of the camera view. Not yet placed in the pool scene.",
        "category": "rim",
        "revision": 1,
        "dependencies": ["assets/export/M_PoolRim.tres"],
        "vertex_colors_attribute": "RimColor",
        "pivot": "pool centre on the swim plane (Godot y = 0)",
        "radius_m": RIM_RINGS[-1],
        "vertex_colors": {
            "attribute": "RimColor",
            "encoding": "sRGB-encoded in COLOR_0; the engine material sets vertex_color_is_srgb (assets/export/M_PoolRim.tres)",
            "note": "Linear RGB, with gentle mottling: dark, cool stone on the lip and shelf, and a lighter navy on the wall's inner face from %.0f m down, which the sun never reaches on the north side." % WALL_AT_M[1],
            "stone": list(RIM_STONE),
            "wall": list(RIM_WALL),
            "max_luminance": round(brightest, 4),
        },
        "profile_m": {
            "inner_edge": [round(min(skirt), 3), round(max(skirt), 3)],
            "plane_crossing": [round(min(crossings), 3), round(max(crossings), 3)],
            "skirt_bottom": SKIRT_DEPTHS[0],
            "lip": list(mb.FLOOR_LIP),
            "shelf": list(mb.FLOOR_SHELF),
            "max_height_inside_r39": round(max(inside), 3),
            "min_height_r41_5_to_43": round(min(lip), 3),
            "shelf_heights": [round(min(shelf), 3), round(max(shelf), 3)],
        },
        "contract": "Shape only, whatever the material: the wall's inner face in r 38.5-38.8 at every azimuth down to at least 5 m, the surface crossing the swim plane between the hard radius and 1 m outside it, at or below -0.45 m inside r 39, the lip above +0.8 m over r 41.5-43, a level shelf at about +1.0 m past the widest view, every face looking up or into the pool (tests/test_assets.gd).",
    }


def main():
    bc.reset_scene()
    fields = build_pool_rim()
    record = bc.export(ASSET_ID, BUDGET, fields, review_state=REVIEW_STATE, generator=GENERATOR)
    dims = record["dimensions_m"]
    print(f"{ASSET_ID}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m, "
          f"crossing {record['profile_m']['plane_crossing']}, inner edge {record['profile_m']['inner_edge']}")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
