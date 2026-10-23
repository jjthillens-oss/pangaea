# Writes data/stage1_bodies.json, the Stage 1 test matrix (invented shapes). Run: python3 tools/make_stage1_bodies.py data/stage1_bodies.json
import json, math, sys
bodies = {}

def body(name, ref_mm, spine, limbs=(), parts=()):
    verts = [{"id": "v_%d" % (i + 1), "p": [x, y, z], "r": r} for i, (x, y, z, r) in enumerate(spine)]
    out_limbs, j = [], 1
    for li, (attach, mirror, joints) in enumerate(limbs):
        js = []
        for (x, y, z, r) in joints:
            js.append({"id": "j_%d" % j, "p": [x, y, z], "r": r}); j += 1
        out_limbs.append({"id": "l_%d" % (li + 1), "attach": "v_%d" % attach, "mirror": mirror, "joints": js})
    out_parts = []
    for pi, (ptype, host, a) in enumerate(parts):
        e = {"id": "p_%d" % (pi + 1), "type": ptype, "host": host}
        for k, dflt in (("u", 500), ("ring", 0), ("elev", 0), ("height", 0), ("turn", 0), ("tilt", 0), ("roll", 0), ("scale", 1000)):
            e[k] = a.get(k, dflt)
        e["handles"] = a.get("handles", [])
        e["mirror"] = a.get("mirror", False)
        out_parts.append(e)
    bodies[name] = {"body_version": 3, "plan": "spine", "reference_length_mm": ref_mm, "generator": "skin-1",
        "vertebrae": verts, "limbs": out_limbs, "parts": out_parts,
        "next": {"j": j, "l": len(limbs) + 1, "p": len(parts) + 1, "v": len(spine) + 1}}

# Thin long snake: 20 vertebrae on an S curve.
body("snake", 2400, [(int(140 * math.sin(i * 0.55)), 0, -700 + i * 72, 70 if i < 2 else max(48, 80 - 2 * i)) for i in range(20)])

quad_spine = [(0, 40, -480, 60), (0, 20, -380, 80), (0, 0, -260, 110), (0, 0, -120, 120), (0, 0, 20, 120),
    (0, 0, 160, 110), (0, 10, 280, 80), (0, 30, 400, 55), (0, 50, 500, 40)]
quad_legs = [(3, True, [(90, -40, -260, 55), (110, -260, -240, 42), (110, -480, -260, 38), (110, -520, -320, 36)]),
    (6, True, [(90, -30, 160, 60), (115, -250, 200, 46), (110, -470, 170, 38), (110, -520, 110, 36)])]
body("quadruped", 1200, quad_spine, quad_legs, [
    ("eye", "spine", {"u": 60, "ring": 170, "mirror": True, "scale": 800}),
    ("beak", "spine", {"u": 0, "elev": 20, "ring": 500, "scale": 900}),
    ("horn", "spine", {"u": 90, "ring": 90, "mirror": True, "scale": 1200}),
    ("fin", "spine", {"u": 450, "ring": 0, "scale": 1300, "handles": [400, 300, 0]}),
    ("foot", "l_1:end", {"mirror": True, "scale": 650}), ("foot", "l_2:end", {"mirror": True, "scale": 650})])

body("biped", 1000, [(0, 420, -380, 70), (0, 380, -260, 60), (0, 320, -150, 90), (0, 260, -20, 110), (0, 220, 100, 100),
    (0, 200, 240, 70), (0, 190, 380, 50), (0, 190, 500, 40)],
    [(3, True, [(90, 300, -150, 45), (150, 180, -180, 38), (150, 90, -250, 36)]),
     (5, True, [(100, 180, 100, 70), (135, -50, 20, 50), (125, -330, 120, 40), (125, -400, 0, 36)])],
    [("eye", "spine", {"u": 50, "ring": 200, "mirror": True, "scale": 700}),
     ("beak", "spine", {"u": 0, "elev": 30, "ring": 500, "scale": 800, "handles": [500, 300, 600]}),
     ("foot", "l_2:end", {"mirror": True, "scale": 600})])

hz = [-400, -260, -130, 0, 130, 260, 400]
body("hexapod", 600, [(0, 0, z, r) for z, r in zip(hz, [70, 90, 100, 100, 100, 90, 70])],
    [(a, True, [(90, 0, hz[a - 1], 50), (260, 80, hz[a - 1] + dz, 40), (330, -250, hz[a - 1] + 2 * dz, 38)])
     for a, dz in [(2, -40), (4, 0), (6, 40)]],
    [("eye", "spine", {"u": 80, "ring": 150, "mirror": True, "scale": 500}),
     ("horn", "spine", {"u": 40, "ring": 60, "mirror": True, "scale": 700, "handles": [0, 800]}),
     ("fin", "spine", {"u": 600, "ring": 0, "scale": 600})])

cz = [-500 + i * 111 for i in range(10)]
body("twelve_limbs", 900, [(0, 0, z, 80 if 0 < i < 9 else 60) for i, z in enumerate(cz)],
    [(a, True, [(70, 0, cz[a - 1], 45), (180, -40, cz[a - 1], 40), (220, -200, cz[a - 1], 40)]) for a in range(3, 9)])

body("giant_limb", 800, [(0, 20, -380, 90), (0, 0, -170, 140), (0, 0, 0, 150), (0, 0, 170, 130), (0, 20, 350, 80)],
    [(2, False, [(140, 40, -170, 100), (380, 120, -300, 90), (520, 40, -560, 110), (560, 0, -720, 70)]),
     (4, True, [(100, -60, 170, 50), (150, -200, 190, 42), (150, -300, 150, 40)])])

body("tiny", 100, [(0, 0, -200, 170), (0, 20, 0, 220), (0, 0, 200, 170)],
    [(2, True, [(150, -80, -120, 80), (200, -260, -130, 60)]), (2, True, [(150, -80, 120, 80), (200, -260, 130, 60)])])

mz = [-1100 + 100 * i for i in range(24)]
mr = [90, 95, 100, 110, 115, 120, 125, 125, 125, 125, 125, 120, 115, 110, 105, 100, 95, 90, 88, 86, 84, 82, 80, 80]
body("max_vertebrae", 3000, [(0, 0, z, r) for z, r in zip(mz, mr)],
    [(a, True, [(120, -20, mz[a - 1], 95), (260, -60, mz[a - 1] + 20, 88), (340, -200, mz[a - 1] + 40, 82),
                (350, -330, mz[a - 1] + 10, 80), (360, -400, mz[a - 1] - 70, 80)]) for a in (6, 15)])

tz = [-500, -300, -100, 100, 300, 500]
body("thin", 1000, [(0, 0, z, 36) for z in tz],
    [(a, True, [(30, 0, tz[a - 1], 36), (300, 150, tz[a - 1], 36), (480, -300, tz[a - 1], 36)]) for a in (2, 3, 5)])

body("asymmetric", 900, [(0, 0, -400, 80), (40, 10, -250, 100), (60, 0, -80, 120), (40, 0, 90, 120), (0, 0, 250, 100),
    (-60, 20, 400, 70)],
    [(2, False, [(-80, -30, -250, 60), (-200, -250, -280, 45), (-210, -480, -250, 40)]),
     (4, False, [(140, -40, 90, 65), (250, -260, 110, 48), (260, -480, 90, 40)]),
     (5, False, [(-90, -40, 250, 60), (-180, -260, 290, 45), (-190, -480, 270, 40)]),
     (3, False, [(170, 60, -80, 50), (260, 250, -160, 40), (250, 380, -300, 38)])])

json.dump({"note": "Stage 1 test bodies (CREATURE_GEOMETRY_SPEC.md section 10 test matrix), in canonical description form. Invented shapes; no outside data.",
           "bodies": bodies}, open(sys.argv[1], "w"), indent="\t")
open(sys.argv[1], "a").write("\n")
print(list(bodies))
