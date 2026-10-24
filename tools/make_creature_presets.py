#!/usr/bin/env python3
"""Writes game/data/creature/presets.json: the creature editor's preset creatures (PROPOSED designs, owner
playtest 2026-10-24: "a weird dragon, a velociraptor with long legs and small arms, a monkey..."). Each preset is a
body in the body codec's dictionary on the real spine, limb and part system, so the editor edits it like any body
and the world can spawn it as a rival species.

Coordinates are in 1/1000 of the body's reference length: x to the creature's left (mirrored limbs and parts get a
twin at -x), y up, z toward the tail (the head is at -z). Parts sit at u (per mille along the spine from the head,
or along a limb) and ring (per mille round it: 0 the top, 500 the belly). tests/test_creature_presets.gd checks that
every preset passes the body and part rules, builds a closed skin and walks on the gait planner.

Usage: python3 tools/make_creature_presets.py [--check]
"""
import json
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

    def to_dict(self):
        joints = sum(len(l["joints"]) for l in self.limbs)
        return {"title": self.title, "blurb": self.blurb, "body": {
            "body_version": 3, "plan": "spine", "reference_length_mm": self.length_mm, "generator": "skin-1",
            "vertebrae": self.vertebrae, "limbs": self.limbs, "parts": self.parts,
            "next": {"j": joints + 1, "l": len(self.limbs) + 1, "p": len(self.parts) + 1,
                     "v": len(self.vertebrae) + 1},
            "skin_color": self.skin}}


def raptor():
    b = Body("raptor", "Raptor", "A fast hunter on two long legs, with little clawed arms and a balancing tail.", 1400,
             "#4fc08a")
    b.spine((300, -560, 55), (250, -460, 50), (170, -340, 80), (120, -200, 105), (110, -60, 110), (115, 80, 90),
            (125, 220, 65), (135, 360, 48), (145, 490, 36), (150, 590, 30))
    b.limb(5, (100, 70, -60, 70), (135, -150, -130, 55), (125, -360, 10, 40), (125, -440, -60, 34), end="foot",
           end_scale=900)
    b.limb(3, (70, 140, -330, 38), (110, 70, -360, 32), (110, 30, -420, 30), end="claw", end_scale=800)
    b.part("maw", u=0, ring=500, elev=25, scale=900)
    b.part("eye", u=70, ring=170, scale=700, mirror=True)
    b.part("quills", u=150, ring=0, scale=700)
    return b


def dragon():
    b = Body("dragon", "Dragon", "Long neck, long spiked tail, horns and a pair of wings on its back.", 2000, "#d2604e")
    b.spine((360, -640, 42), (310, -560, 45), (230, -480, 55), (150, -390, 70), (90, -280, 100), (75, -150, 110),
            (75, -20, 110), (80, 110, 100), (90, 230, 75), (100, 350, 55), (110, 470, 40), (115, 590, 28))
    b.limb(5, (90, 40, -280, 55), (120, -150, -250, 44), (120, -330, -280, 36), (120, -380, -330, 32), end="foot",
           end_scale=1100)
    b.limb(8, (95, 40, 110, 65), (125, -130, 160, 50), (120, -320, 120, 38), (120, -380, 70, 34), end="foot",
           end_scale=1100)
    b.part("maw", u=0, ring=500, elev=20, scale=1000)
    b.part("eye", u=40, ring=180, scale=800, mirror=True)
    b.part("horn", u=50, ring=90, scale=1400, mirror=True)
    b.part("wing", u=330, ring=180, scale=2200, mirror=True)
    b.part("crest", u=150, ring=0, scale=900)
    b.part("tail_spikes", u=1000, ring=0, scale=1200)
    return b


def monkey():
    b = Body("monkey", "Monkey", "Sits up on short legs and reaches with long arms; a curled tail for balance.", 1000,
             "#d9a441")
    b.spine((600, -260, 95), (560, -170, 55), (450, -130, 110), (340, -70, 105), (250, 0, 95), (200, 90, 40),
            (210, 190, 30), (280, 260, 26), (380, 290, 22))
    b.limb(5, (90, 210, 0, 60), (125, 50, -70, 48), (120, -110, 0, 40), (120, -170, -70, 36), end="foot",
           end_scale=800)
    b.limb(3, (110, 460, -130, 45), (220, 310, -160, 38), (250, 110, -180, 32), (250, -40, -190, 28), end="hand",
           end_scale=1100)
    b.part("maw", u=0, ring=500, elev=35, scale=700)
    b.part("eye", u=40, ring=140, scale=750, mirror=True)
    return b


def beetle():
    b = Body("beetle", "Beetle", "Six legs low to the ground, pincer mandibles and feelers.", 700, "#2e4a6b")
    b.spine((0, -420, 70), (10, -290, 95), (20, -150, 115), (25, 0, 125), (20, 150, 120), (10, 290, 100),
            (0, 410, 70))
    for v, z in ((2, -290), (4, 0), (6, 290)):
        b.limb(v, (90, 0, z, 50), (280, 90, z - 30 if z < 0 else z + 30, 40), (360, -260, z * 1.15, 36),
               end="foot", end_scale=500)
    for l in b.limbs:
        for j in l["joints"]:
            j["p"] = [int(round(c)) for c in j["p"]]
    b.part("mandibles", u=0, ring=500, elev=20, scale=1300)
    b.part("compound_eye", u=50, ring=190, scale=900, mirror=True)
    b.part("antenna", u=30, ring=90, scale=1500, mirror=True)
    return b


def longneck():
    b = Body("longneck", "Longneck", "A tall grazer: a neck that reaches the treetops and four pillar legs.", 2400,
             "#4f8f6a")
    b.spine((700, -560, 40), (620, -500, 42), (520, -450, 48), (410, -400, 58), (300, -340, 75), (210, -250, 110),
            (180, -120, 130), (180, 20, 130), (190, 150, 115), (180, 280, 80), (160, 400, 55), (140, 510, 35))
    b.limb(6, (95, 140, -250, 65), (125, -60, -240, 55), (120, -280, -250, 48), (120, -330, -265, 46),
           end="hoof", end_scale=1900)
    b.limb(9, (100, 150, 150, 70), (130, -40, 170, 58), (120, -280, 150, 48), (120, -330, 140, 46), end="hoof",
           end_scale=1900)
    b.part("beak", u=0, ring=500, elev=20, scale=900)
    b.part("eye", u=30, ring=170, scale=700, mirror=True)
    return b


def tortoise():
    b = Body("tortoise", "Tortoise", "Wide, low and armoured, with a beak and a club on its tail.", 900, "#5f6b7a")
    b.spine((120, -460, 55), (100, -370, 60), (110, -250, 150), (130, -100, 190), (130, 50, 190), (110, 200, 150),
            (90, 320, 70), (80, 420, 45))
    b.limb(3, (130, 60, -250, 70), (250, -40, -270, 60), (250, -190, -290, 52), end="foot", end_scale=1300)
    b.limb(6, (130, 60, 200, 70), (250, -40, 220, 60), (250, -190, 240, 52), end="foot", end_scale=1300)
    b.part("beak", u=0, ring=500, elev=15, scale=1000)
    b.part("eye", u=40, ring=180, scale=800, mirror=True)
    b.part("quills", u=450, ring=0, scale=2200)
    b.part("club_tail", u=1000, ring=0, scale=1800)
    return b


def boar():
    b = Body("boar", "Boar", "Stocky, short-legged and tusked; charges first and asks later.", 1100, "#a8664e")
    b.spine((180, -500, 85), (200, -400, 105), (230, -280, 140), (240, -130, 150), (230, 20, 145), (210, 160, 125),
            (200, 280, 80), (210, 370, 40))
    b.limb(3, (95, 140, -280, 65), (125, -10, -270, 52), (120, -170, -290, 44), (120, -210, -300, 42),
           end="hoof", end_scale=1300)
    b.limb(6, (100, 140, 160, 70), (130, -10, 190, 55), (120, -170, 160, 44), (120, -210, 150, 42), end="hoof",
           end_scale=1300)
    b.part("maw", u=0, ring=500, elev=20, scale=1100)
    b.part("tusk", u=30, ring=380, scale=1500, mirror=True)
    b.part("eye", u=90, ring=170, scale=700, mirror=True)
    b.part("crest", u=300, ring=0, scale=1100)
    return b


def stalker():
    b = Body("stalker", "Stalker", "Eight long legs, eyes on stalks and a pair of mandibles.", 800, "#a86fd6")
    b.spine((80, -380, 80), (90, -260, 110), (100, -120, 120), (110, 30, 140), (100, 180, 150), (80, 320, 120),
            (60, 440, 70))
    for v, z in ((2, -260), (3, -120), (4, 30), (5, 180)):
        spread = 1 if z > 0 else -1
        b.limb(v, (90, 80, z, 45), (320, 260, z + spread * 60, 36), (480, -200, z + spread * 140, 30),
               end="foot", end_scale=500)
    b.part("mandibles", u=0, ring=500, elev=25, scale=1100)
    b.part("eye_stalk", u=60, ring=110, scale=1400, mirror=True)
    return b


def hopper():
    b = Body("hopper", "Hopper", "A wide mouth, eyes on top, and big folded hind legs for springing.", 700, "#7fbf4f")
    b.spine((80, -400, 110), (110, -290, 140), (130, -150, 150), (120, 0, 145), (90, 140, 120), (60, 250, 70))
    b.limb(2, (110, 40, -290, 50), (180, -80, -330, 40), (180, -220, -360, 36), end="foot", end_scale=700)
    b.limb(5, (120, 40, 140, 75), (300, 120, 40, 60), (300, -150, 230, 50), (280, -220, 120, 44), end="foot",
           end_scale=1300)
    b.part("maw", u=0, ring=500, elev=10, scale=1500)
    b.part("eye", u=150, ring=90, scale=1200, mirror=True)
    return b


def strider():
    b = Body("strider", "Strider", "A long-legged bird with a crest and stubby wings.", 1200, "#e6e1c8")
    b.spine((560, -380, 50), (500, -320, 45), (420, -260, 50), (320, -180, 90), (270, -60, 115), (260, 70, 110),
            (270, 190, 75), (290, 290, 45))
    b.limb(6, (100, 220, 70, 70), (135, 20, 0, 52), (125, -330, 100, 40), (125, -420, 30, 34), end="foot",
           end_scale=900)
    b.part("beak", u=0, ring=500, elev=10, scale=1300)
    b.part("eye", u=50, ring=170, scale=700, mirror=True)
    b.part("crest", u=60, ring=0, scale=900)
    b.part("wing", u=420, ring=200, scale=900, mirror=True)
    return b


def prowler():
    b = Body("prowler", "Prowler", "A lithe four-legged hunter with a frilled mane and a long, low stride.", 1500,
             "#c8873a")
    b.spine((260, -560, 85), (255, -460, 90), (235, -370, 75), (215, -270, 115), (205, -140, 120), (200, -10, 110),
            (205, 120, 105), (215, 240, 65), (235, 360, 46), (265, 480, 36), (295, 580, 30))
    b.limb(4, (95, 160, -270, 68), (125, 20, -255, 58), (115, -150, -280, 48), (115, -190, -305, 44),
           end="foot", end_scale=1100)
    b.limb(7, (100, 160, 120, 75), (130, 20, 165, 62), (120, -150, 120, 48), (120, -190, 110, 44), end="foot",
           end_scale=1100)
    b.part("maw", u=0, ring=500, elev=25, scale=1100)
    b.part("eye", u=60, ring=160, scale=800, mirror=True)
    b.part("frill", u=190, ring=0, scale=2000)
    return b


def angler():
    b = Body("angler", "Angler", "A round ambusher on stumpy legs: a glowing lure, a huge mouth and finned back.", 900,
             "#3f6f8f")
    b.spine((150, -420, 120), (170, -300, 170), (180, -150, 200), (170, 10, 190), (150, 160, 150), (130, 290, 90),
            (120, 390, 50))
    b.limb(3, (140, 30, -150, 60), (230, -60, -170, 50), (230, -170, -190, 44), end="foot", end_scale=900)
    b.limb(5, (140, 30, 160, 60), (230, -60, 180, 50), (230, -170, 200, 44), end="foot", end_scale=900)
    b.part("maw", u=0, ring=500, elev=5, scale=1700)
    b.part("eye", u=80, ring=140, scale=900, mirror=True)
    b.part("lure", u=60, ring=0, scale=1400)
    b.part("fin", u=450, ring=0, scale=1300)
    b.part("gill_fan", u=170, ring=250, scale=900, mirror=True)
    b.part("tail_fluke", u=1000, ring=0, scale=1100)
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
