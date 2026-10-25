#!/usr/bin/env python3
"""Writes game/data/creature/presets.json: the creature editor's preset creatures (PROPOSED designs, owner
playtest 2026-10-24: "a weird dragon, a velociraptor with long legs and small arms, a monkey..."). Each preset is a
body in the body codec's dictionary on the real spine, limb and part system, so the editor edits it like any body
and the world can spawn it as a rival species.

Coordinates are in 1/1000 of the body's reference length: x to the creature's left (mirrored limbs and parts get a
twin at -x), y up, z toward the tail (the head is at -z). Parts sit at u (per mille along the spine from the head,
or along a limb) and ring (per mille round it: 0 the top, 500 the belly). tests/test_creature_presets.gd checks that
every preset passes the body and part rules, builds a closed skin and walks on the gait planner.

Usage: python3 tools/make_creature_presets.py [--check | --report]

--report prints each preset's legs (as the gait planner reads them, with their two-bone lengths) and the standing
tilt their lengths give, which sets the posture: long front limbs stand front-up, long hind legs front-down.
"""
import json
import math
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "game" / "data" / "creature" / "presets.json"


class Body:
    def __init__(self, name, title, blurb, length_mm, skin):
        self.name, self.title, self.blurb = name, title, blurb
        self.length_mm = length_mm
        self.skin = skin
        self.vertebrae = []
        self.limbs = []
        self.parts = []
        self.head = {}
        self.covering = 0

    def look(self, covering=0, **head):
        """covering: 0 smooth, 1 fur, 2 scales, 3 wet (creature_look.gd); head: the head shape dials in per mille
        (domain/creature/head_shape.gd: snout, width, height, jaw, brow), only the ones off their default."""
        self.covering = covering
        self.head = head
        return self

    def spine(self, *points):
        """points: (y, z, r) from the head to the tail."""
        for y, z, r in points:
            self.vertebrae.append({"id": "v_%d" % (len(self.vertebrae) + 1), "p": [0, y, z], "r": r})
        return self

    def limb(self, attach, *joints, mirror=True, end=None, end_scale=1000, end_handles=None):
        """attach: vertebra number (1 = head); joints: (x, y, z, r) from the hip or shoulder out; end: a part type
        for the limb's tip."""
        lid = "l_%d" % (len(self.limbs) + 1)
        first = sum(len(l["joints"]) for l in self.limbs)
        js = [{"id": "j_%d" % (first + k + 1), "p": [x, y, z], "r": r} for k, (x, y, z, r) in enumerate(joints)]
        self.limbs.append({"id": lid, "attach": "v_%d" % attach, "mirror": mirror, "joints": js})
        if end:
            self.part(end, host=lid + ":end", u=500, scale=end_scale, mirror=mirror, handles=end_handles or [])
        return lid

    def part(self, type, host="spine", u=0, ring=0, elev=0, scale=1000, mirror=False, handles=None, turn=0, tilt=0,
             height=0):
        self.parts.append({"id": "p_%d" % (len(self.parts) + 1), "type": type, "host": host, "u": u, "ring": ring,
                           "elev": elev, "height": height, "turn": turn, "tilt": tilt, "roll": 0, "scale": scale,
                           "handles": handles or [], "mirror": mirror})
        return self

    def u(self, v):
        """The per mille along the spine (as parts' u counts it) at vertebra number v (1 = head)."""
        pts = [vt["p"] for vt in self.vertebrae]
        seg = [sum((a - b) ** 2 for a, b in zip(pts[k], pts[k + 1])) ** 0.5 for k in range(len(pts) - 1)]
        return int(round(1000 * sum(seg[:v - 1]) / sum(seg)))

    def stance(self, ratio=0.8):
        """The legs as game/domain/creature/gait_body.gd reads them and the standing tilt body_mechanics.gd fits (degrees, positive
        lifts the front), for --report."""
        chains = []
        for l in self.limbs:
            pts = [j["p"] for j in l["joints"]]
            chains.append((l["id"], pts))
        lowest = min(c[1][-1][1] for c in chains) if chains else 0
        legs = []
        for lid, pts in chains:
            d = lambda a, b: sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5
            length = sum(d(pts[k], pts[k + 1]) for k in range(len(pts) - 1))
            if len(pts) >= 3 and pts[0][1] - pts[-1][1] > 0.25 * length and pts[-1][1] - lowest < 0.25 * length:
                legs.append((lid, pts[0][2], d(pts[0], pts[1]) + d(pts[1], pts[-1])))
        if not legs:
            return legs, 0.0
        mz = sum(z for _, z, _ in legs) / len(legs)
        mh = sum(ratio * h for _, _, h in legs) / len(legs)
        szz = sum((z - mz) ** 2 for _, z, _ in legs)
        szh = sum((z - mz) * (ratio * h - mh) for _, z, h in legs)
        slope = szh / szz if szz > 1e-9 else 0.0
        return legs, max(-30.0, min(30.0, math.degrees(math.atan(-slope))))

    def to_dict(self):
        joints = sum(len(l["joints"]) for l in self.limbs)
        out = {"title": self.title, "blurb": self.blurb, "body": {
            "body_version": 3, "plan": "spine", "reference_length_mm": self.length_mm, "generator": "skin-1",
            "vertebrae": self.vertebrae, "limbs": self.limbs, "parts": self.parts,
            "next": {"j": joints + 1, "l": len(self.limbs) + 1, "p": len(self.parts) + 1,
                     "v": len(self.vertebrae) + 1},
            "skin_color": self.skin}}
        if self.head:
            out["body"]["head_shape"] = {k: self.head[k] for k in sorted(self.head)}
        if self.covering:
            out["body"]["skin_covering"] = self.covering
        return out


def raptor():
    b = Body("raptor", "Raptor", "A fast hunter on two long legs, with little clawed arms and a balancing tail.", 1400,
             "#4fc08a")
    b.spine((300, -580, 45), (285, -490, 62), (240, -400, 52), (190, -300, 82), (150, -170, 110), (145, -40, 112),
            (150, 90, 92), (160, 220, 66), (170, 350, 48), (180, 470, 36), (185, 580, 28))
    b.limb(6, (100, 90, -40, 75), (140, -110, -150, 58), (125, -330, -10, 40), (125, -420, -70, 34),
           end="foot_talon", end_scale=900)
    b.limb(4, (75, 150, -300, 36), (115, 70, -330, 30), (115, 20, -400, 28), end="claw_scythe", end_scale=800)
    b.part("jaw", u=0, ring=500, elev=20, scale=950)
    b.part("eye_slit", u=b.u(2), ring=170, scale=800, mirror=True)
    b.part("crest", u=b.u(3), ring=0, scale=700)
    b.part("quills", u=b.u(5), ring=0, scale=650)
    b.look(2, snout=1250, jaw=300, brow=300)
    return b


def dragon():
    b = Body("dragon", "Dragon", "Long neck, long spiked tail, horns and a pair of wings on its back.", 2000, "#c84b3c")
    b.spine((440, -720, 40), (460, -650, 62), (430, -580, 54), (370, -510, 50), (300, -440, 58), (240, -360, 78),
            (200, -250, 125), (190, -110, 138), (195, 30, 128), (205, 160, 112), (210, 290, 80), (210, 420, 58),
            (200, 545, 42), (185, 660, 36), (170, 760, 33))
    b.limb(7, (110, 190, -240, 80), (150, 40, -205, 68), (140, -160, -240, 54), (140, -205, -285, 50),
           end="foot_talon", end_scale=1150)
    b.limb(10, (115, 170, 160, 90), (165, 30, 220, 74), (150, -150, 160, 56), (150, -205, 115, 52),
           end="foot_talon", end_scale=1200)
    b.part("jaw", u=0, ring=500, elev=15, scale=1050)
    b.part("eye_slit", u=b.u(2), ring=190, scale=850, mirror=True)
    b.part("horn_swept", u=b.u(3) - 10, ring=60, scale=1700, mirror=True, tilt=-35)
    b.part("wing_dragon", u=b.u(7) + 25, ring=140, scale=2600, mirror=True)
    for v, sc in ((4, 650), (5, 700), (6, 800), (9, 900), (10, 850), (11, 750), (12, 650), (13, 550)):
        b.part("dorsal_spine", u=b.u(v), ring=0, scale=sc)
    b.part("tail_spikes", u=1000, ring=0, scale=1500)
    b.look(2, snout=1500, jaw=450, brow=700, width=1100)
    return b


def monkey():
    b = Body("monkey", "Monkey", "A big round head and a short muzzle, long arms it knuckle-walks on, a curling tail.",
             1000, "#a8703a")
    b.spine((330, -440, 66), (430, -370, 165), (400, -250, 76), (380, -150, 140), (350, -30, 128), (320, 90, 104),
            (330, 190, 40), (400, 270, 32), (500, 300, 28), (580, 250, 24))
    b.limb(4, (120, 400, -150, 66), (210, 200, -200, 56), (220, -20, -160, 46), (220, -70, -180, 42),
           end="hand_primate", end_scale=1500)
    b.limb(6, (100, 290, 90, 76), (150, 170, 20, 60), (140, -20, 100, 48), (140, -70, 50, 44), end="foot_primate",
           end_scale=1200)
    b.part("maw", u=0, ring=500, elev=30, scale=650)
    b.part("muzzle_primate", u=0, ring=0, elev=40, scale=1300)
    b.part("eye_round", u=b.u(2) // 2, ring=130, scale=850, mirror=True)
    b.part("ear_round", u=b.u(2), ring=260, scale=1700, mirror=True)
    b.look(1, height=1150, width=1100, brow=550)
    return b


def beetle():
    b = Body("beetle", "Beetle", "Six short legs splayed low, a big nose horn, pincer mandibles and feelers.", 700,
             "#2e4a6b")
    b.spine((60, -440, 60), (70, -340, 95), (90, -210, 120), (110, -60, 150), (110, 100, 155), (90, 250, 130),
            (60, 380, 80))
    for v, z in ((3, -200), (4, -40), (5, 120)):
        out = 1 if z > 0 else -1
        b.limb(v, (100, 40, z, 46), (190, 70, z + out * 30, 38), (230, -60, z + out * 70, 32), end="foot",
               end_scale=450)
    b.part("mandibles", u=0, ring=500, elev=25, scale=1300)
    b.part("horn_nose", u=b.u(2), ring=0, scale=1500, tilt=20)
    b.part("compound_eye", u=b.u(2) - 20, ring=210, scale=900, mirror=True)
    b.part("antenna", u=b.u(2) - 40, ring=110, scale=1400, mirror=True)
    b.look(0, width=1250, height=800)
    return b


def longneck():
    b = Body("longneck", "Longneck", "A tall grazer: a neck that reaches the treetops and four pillar legs.", 2400,
             "#4f8f6a")
    b.spine((760, -600, 34), (740, -540, 42), (660, -500, 44), (560, -450, 52), (450, -390, 64), (340, -320, 84),
            (250, -230, 118), (210, -110, 140), (210, 20, 142), (220, 150, 125), (220, 270, 90), (205, 380, 62),
            (180, 480, 42), (150, 570, 28))
    b.limb(7, (100, 150, -220, 80), (130, -40, -215, 72), (125, -260, -225, 64), (125, -300, -230, 62),
           end="hoof", end_scale=2300)
    b.limb(10, (105, 170, 150, 88), (140, -30, 175, 76), (130, -260, 150, 64), (130, -300, 145, 62), end="hoof",
           end_scale=2300)
    b.part("beak", u=0, ring=500, elev=20, scale=800)
    b.part("eye_round", u=b.u(2), ring=180, scale=650, mirror=True)
    b.part("horn_nose", u=b.u(2) + 10, ring=0, scale=700)
    b.part("ear_pointed", u=b.u(2) + 20, ring=230, scale=900, mirror=True)
    b.look(0, snout=1300, height=900)
    return b


def tortoise():
    b = Body("tortoise", "Tortoise", "A high domed shell, a beaked head on a short neck and a club on its tail.", 900,
             "#5f6b7a")
    b.spine((90, -480, 52), (110, -400, 64), (120, -320, 56), (170, -220, 150), (210, -90, 215), (210, 60, 215),
            (180, 190, 160), (120, 300, 70), (100, 400, 46))
    b.limb(4, (150, 110, -220, 72), (260, 30, -250, 64), (260, -120, -270, 58), end="foot", end_scale=1300)
    b.limb(7, (150, 110, 190, 72), (260, 30, 210, 64), (260, -120, 230, 58), end="foot", end_scale=1300)
    b.part("beak", u=0, ring=500, elev=15, scale=1000)
    b.part("eye", u=b.u(2), ring=190, scale=800, mirror=True)
    for v, sc in ((5, 900), (6, 950), (7, 800)):
        b.part("spike", u=b.u(v), ring=0, scale=sc)
    b.part("club_tail", u=1000, ring=0, scale=1800)
    b.look(2, snout=1100, brow=400)
    return b


def boar():
    b = Body("boar", "Boar", "Stocky, short-legged and tusked, with a bristling mane; charges first and asks later.",
             1100, "#a8664e")
    b.spine((170, -520, 80), (190, -420, 105), (230, -300, 145), (260, -150, 162), (245, 10, 150), (220, 160, 128),
            (210, 280, 80), (225, 370, 40))
    b.limb(3, (95, 140, -280, 68), (125, -10, -270, 56), (120, -170, -290, 46), (120, -210, -300, 44),
           end="hoof", end_scale=1300)
    b.limb(6, (100, 140, 160, 74), (130, -10, 190, 58), (120, -170, 160, 46), (120, -210, 150, 44), end="hoof",
           end_scale=1300)
    b.part("maw", u=0, ring=500, elev=20, scale=1100)
    b.part("tusk", u=b.u(1) + 20, ring=380, scale=1600, mirror=True)
    b.part("eye", u=b.u(2), ring=170, scale=650, mirror=True)
    b.part("ear_pointed", u=b.u(2) + 20, ring=220, scale=1100, mirror=True)
    b.part("mane", u=b.u(4), ring=0, scale=1100)
    b.look(1, snout=1600, width=1150, jaw=350, brow=500)
    return b


def stalker():
    b = Body("stalker", "Stalker", "Eight long legs round a small head, eyes on stalks and a swollen abdomen.", 800,
             "#a86fd6")
    b.spine((110, -460, 62), (130, -370, 100), (140, -250, 120), (140, -120, 120), (135, 0, 95), (140, 90, 60),
            (170, 190, 130), (175, 320, 140), (150, 430, 80))
    for v, z, spread in ((2, -360, -1.5), (3, -250, -0.5), (4, -130, 0.5), (5, -20, 1.5)):
        b.limb(v, (100, 130, z, 42), (210, 200, int(z + spread * 70), 34), (260, -40, int(z + spread * 160), 28),
               end="foot", end_scale=450)
    b.part("mandibles", u=0, ring=500, elev=25, scale=1100)
    b.part("eye_stalk", u=b.u(2), ring=80, scale=1400, mirror=True)
    b.part("eye_cluster", u=b.u(1) + 20, ring=0, scale=800)
    b.look(1, height=850)
    return b


def hopper():
    b = Body("hopper", "Hopper", "A wide mouth, big eyes on top, short front legs and long folded hind legs.", 700,
             "#7fbf4f")
    b.spine((150, -380, 90), (170, -300, 140), (160, -190, 165), (140, -60, 165), (120, 60, 145), (100, 160, 95))
    b.limb(2, (110, 170, -220, 50), (150, 30, -250, 42), (150, -110, -240, 36), end="hand_frog", end_scale=1300)
    b.limb(5, (140, 80, 70, 92), (220, 40, -20, 80), (250, 50, 290, 54), (250, -110, 80, 46),
           end="foot_frog", end_scale=1500)
    b.part("maw", u=0, ring=500, elev=25, scale=1000)
    b.part("eye_bulge", u=b.u(2), ring=120, scale=1300, mirror=True)
    b.part("throat_sac", u=b.u(2), ring=500, scale=1200)
    b.look(3, width=1450, height=700, jaw=250)
    return b


def strider():
    b = Body("strider", "Strider", "A long-legged bird with an S-necked head, a crest, stubby wings and a tail fan.",
             1200, "#e6e1c8")
    b.spine((600, -420, 40), (610, -350, 55), (560, -300, 42), (470, -280, 46), (380, -230, 58), (310, -140, 100),
            (280, -20, 125), (285, 100, 112), (305, 210, 70), (330, 290, 42))
    b.limb(7, (100, 240, 20, 72), (135, 40, -40, 56), (125, -300, 80, 40), (125, -420, 20, 34), end="foot_talon",
           end_scale=1000)
    b.part("beak", u=0, ring=500, elev=10, scale=850)
    b.part("eye_round", u=b.u(2), ring=180, scale=700, mirror=True)
    b.part("crest", u=b.u(2) + 15, ring=0, scale=800)
    b.part("wing", u=b.u(7), ring=210, scale=1200, mirror=True)
    b.part("tail_fluke", u=1000, ring=0, scale=1300)
    b.look(0, snout=1150, height=1100)
    return b


def prowler():
    b = Body("prowler", "Prowler", "A lithe cat-like hunter with a shaggy mane, a bushy tail and a long, low stride.",
             1500, "#c8873a")
    b.spine((300, -580, 70), (300, -500, 95), (275, -400, 70), (250, -300, 112), (235, -170, 116), (230, -40, 104),
            (240, 90, 106), (255, 200, 60), (285, 320, 40), (330, 440, 32), (360, 550, 28))
    b.limb(4, (95, 180, -290, 66), (125, 20, -265, 56), (115, -170, -290, 46), (115, -215, -310, 42),
           end="foot_paw", end_scale=1200)
    b.limb(7, (100, 180, 90, 75), (130, 20, 150, 62), (120, -150, 100, 48), (120, -215, 90, 44), end="foot_paw",
           end_scale=1200)
    b.part("maw", u=0, ring=500, elev=25, scale=1050)
    b.part("eye_slit", u=b.u(2), ring=160, scale=1000, mirror=True)
    b.part("ear_pointed", u=b.u(2), ring=230, scale=1300, mirror=True)
    b.part("mane", u=b.u(3), ring=0, scale=1500)
    b.part("tail_bushy", u=1000, ring=0, scale=1500)
    b.look(1, snout=1250, width=1100, brow=350)
    return b


def angler():
    b = Body("angler", "Angler", "A round ambusher on stumpy legs: a glowing lure, a huge mouth and finned back.", 900,
             "#3f6f8f")
    b.spine((150, -420, 120), (170, -300, 170), (180, -150, 200), (170, 10, 190), (150, 160, 150), (130, 290, 90),
            (120, 390, 50))
    b.limb(3, (140, 30, -150, 60), (230, -60, -170, 50), (230, -170, -190, 44), end="foot_webbed", end_scale=900)
    b.limb(5, (140, 30, 160, 60), (230, -60, 180, 50), (230, -170, 200, 44), end="foot_webbed", end_scale=900)
    b.part("maw", u=0, ring=500, elev=5, scale=1700)
    b.part("eye", u=b.u(2), ring=140, scale=900, mirror=True)
    b.part("lure", u=b.u(2) - 40, ring=0, scale=1400)
    b.part("fin", u=450, ring=0, scale=1300)
    b.part("gill_fan", u=b.u(3), ring=250, scale=900, mirror=True)
    b.part("tail_fluke", u=1000, ring=0, scale=1100)
    b.look(3, width=1350, jaw=650)
    return b


PRESETS = [raptor, dragon, monkey, beetle, longneck, tortoise, boar, stalker, hopper, strider, prowler, angler]


def build():
    bodies = {}
    for make in PRESETS:
        b = make()
        bodies[b.name] = b.to_dict()
    return {"_comment": "Generated by tools/make_creature_presets.py; do not edit by hand.",
            "status": "PROPOSED", "order": [m().name for m in PRESETS], "presets": bodies}


def main():
    text = json.dumps(build(), indent="\t") + "\n"
    if "--report" in sys.argv:
        for make in PRESETS:
            b = make()
            legs, pitch = b.stance()
            print("%-9s legs %s  tilt %+.1f deg  parts %d" % (b.name, ["%s:%d" % (l, h) for l, _, h in legs], pitch,
                                                                len(b.parts)))
        return 0
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            print("%s is out of date: run python3 tools/make_creature_presets.py" % OUT)
            return 1
        print("%s is up to date" % OUT)
        return 0
    OUT.write_text(text)
    print("wrote %s (%d presets)" % (OUT, len(PRESETS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
