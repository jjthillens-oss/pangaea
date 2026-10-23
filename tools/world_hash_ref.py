"""Independent reference for WorldHash (game/domain/world_hash.gd; S1 spine section 3.2).

The endless world's stateless hashes, written again in Python from the published algorithms and
not from the GDScript, so the definition is pinned twice:
  - hash_ints: MurmurHash3_x86_32 (public domain) over each value's little-endian 64-bit two's
    complement encoding, seed 0x9747B28C. Computed here two ways: over 32-bit words (low word
    first, as the GDScript does) and over the bytes, as the published algorithm reads them;
  - str32: FNV-1a 32 (public domain) over the UTF-8 bytes;
  - mix32(a, b) = hash_ints([a, b]);
  - key(seed, gen_version, band, tx, ty, purpose) = hash_ints([seed, gen_version, band, tx, ty, str32(purpose)]).

`python3 -I tools/world_hash_ref.py --check` checks both MurmurHash3 versions against published
test vectors, str32 against published FNV-1a vectors, and the twenty goldens that
tests/test_world_hash.gd pins, and exits 0 when all hold. With no flag it prints the goldens.
CI does not run it (Godot is the build); it documents the definition independently of GDScript.
"""
import struct
import sys

MASK = 0xFFFFFFFF
SEED0 = 0x9747B28C


def _rotl(x, r):
    return ((x << r) | (x >> (32 - r))) & MASK


def _fmix(h):
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & MASK
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & MASK
    h ^= h >> 16
    return h


def _mix_block(h, k):
    k = (k * 0xCC9E2D51) & MASK
    k = _rotl(k, 15)
    k = (k * 0x1B873593) & MASK
    h ^= k
    h = _rotl(h, 13)
    return (h * 5 + 0xE6546B64) & MASK


def mm3_bytes(data, seed):
    """MurmurHash3_x86_32 over a byte string, tail included, as published."""
    h = seed & MASK
    n = len(data) // 4
    for i in range(n):
        (k,) = struct.unpack_from("<I", data, 4 * i)
        h = _mix_block(h, k)
    tail = data[4 * n:]
    k = 0
    if len(tail) >= 3:
        k ^= tail[2] << 16
    if len(tail) >= 2:
        k ^= tail[1] << 8
    if len(tail) >= 1:
        k ^= tail[0]
        k = (k * 0xCC9E2D51) & MASK
        k = _rotl(k, 15)
        k = (k * 0x1B873593) & MASK
        h ^= k
    h ^= len(data)
    return _fmix(h)


def mm3_blocks(words, seed):
    """MurmurHash3_x86_32 over whole 32-bit blocks (no tail): 4 bytes per word."""
    h = seed & MASK
    for w in words:
        h = _mix_block(h, w & MASK)
    h ^= (4 * len(words)) & MASK
    return _fmix(h)


def _words(values):
    out = []
    for v in values:
        bits = v & 0xFFFFFFFFFFFFFFFF   # the two's complement pattern of a signed 64-bit int
        out.append(bits & MASK)
        out.append(bits >> 32)
    return out


def hash_ints(values):
    return mm3_blocks(_words(values), SEED0)


def hash_ints_bytes(values):
    return mm3_bytes(b"".join(struct.pack("<q", v) for v in values), SEED0)


def str32(s):
    h = 0x811C9DC5
    for byte in s.encode("utf-8"):
        h = ((h ^ byte) * 0x01000193) & MASK
    return h


def mix32(a, b):
    return hash_ints([a, b])


def key(seed, gen_version, band, tx, ty, purpose):
    return hash_ints([seed, gen_version, band, tx, ty, str32(purpose)])


# Published MurmurHash3_x86_32 vectors: (bytes, seed, value).
MM3_VECTORS = [
    (b"", 0, 0x00000000),
    (b"", 1, 0x514E28B7),
    (b"", 0xFFFFFFFF, 0x81F16F39),
    (b"\x00\x00\x00\x00", 0, 0x2362F9DE),
    (b"\xff\xff\xff\xff", 0, 0x76293B50),
    (b"\x21\x43\x65\x87", 0, 0xF55B516B),
    (b"\x21\x43\x65\x87", 0x5082EDEE, 0x2362F9DE),
    (b"\x21\x43\x65", 0, 0x7E4A8634),
    (b"\x21\x43", 0, 0xA0F7B07A),
    (b"\x21", 0, 0x72661CF4),
    (b"aaaa", 0x9747B28C, 0x5A97808A),
    (b"Hello, world!", 0x9747B28C, 0x24884CBA),
]

# Published FNV-1a 32 vectors.
FNV_VECTORS = [("", 0x811C9DC5), ("a", 0xE40C292C), ("foobar", 0xBF9CF968)]

# The twenty goldens of S1 spine 3.2: (row, expression, value). tests/test_world_hash.gd pins them too.
GOLDENS = [
    (1, lambda: hash_ints([]), 3954623016),
    (2, lambda: hash_ints([0]), 773692376),
    (3, lambda: hash_ints([1]), 619189011),
    (4, lambda: hash_ints([-1]), 1971636267),
    (5, lambda: hash_ints([4294967295]), 4209728847),
    (6, lambda: hash_ints([4294967296]), 3342626163),
    (7, lambda: hash_ints([-9223372036854775808]), 3700897005),
    (8, lambda: hash_ints([9223372036854775807]), 3188012228),
    (9, lambda: mix32(0, 0), 205331723),
    (10, lambda: mix32(1, 2), 4166365685),
    (11, lambda: mix32(2, 1), 770582150),
    (12, lambda: mix32(-3, 5), 2158776994),
    (13, lambda: str32("tile"), 1899658441),
    (14, lambda: str32("plankton"), 719942472),
    (15, lambda: key(0, 1, 0, 0, 0, "tile"), 4436494),
    (16, lambda: key(4242, 1, 0, -1, -1, "tile"), 2926877857),
    (17, lambda: key(4242, 1, 0, 2, -1, "rare"), 4053045797),
    (18, lambda: key(4294967295, 1, 0, 1000, -1000, "landmark"), 3684426704),
    (19, lambda: 1 + mix32(str32("lair_se"), 0) % 1073741824, 246455513),
    (20, lambda: hash_ints([4242, 1, str32("t_0_3_7_r1"), 2, str32("brain")]), 2622104930),
]


def check():
    bad = 0
    for data, seed, want in MM3_VECTORS:
        got = mm3_bytes(data, seed)
        if got != want:
            bad += 1
            print("mm3_bytes(%r, 0x%08X) = 0x%08X, published 0x%08X" % (data, seed, got, want))
        if len(data) % 4 == 0:
            words = [struct.unpack_from("<I", data, i)[0] for i in range(0, len(data), 4)]
            got = mm3_blocks(words, seed)
            if got != want:
                bad += 1
                print("mm3_blocks(%r, 0x%08X) = 0x%08X, published 0x%08X" % (data, seed, got, want))
    for s, want in FNV_VECTORS:
        if str32(s) != want:
            bad += 1
            print("str32(%r) = 0x%08X, published 0x%08X" % (s, str32(s), want))
    for row, expr, want in GOLDENS:
        got = expr()
        if got != want:
            bad += 1
            print("golden row %d = %d, pinned %d" % (row, got, want))
    for values in ([], [0], [-1], [1 << 62], [-(1 << 63)], [(1 << 63) - 1], [3, -7, 1 << 40, -(1 << 33)]):
        if hash_ints(values) != hash_ints_bytes(values):
            bad += 1
            print("hash_ints(%r) differs from the byte-wise hash" % values)
    total = len(MM3_VECTORS) + len(FNV_VECTORS) + len(GOLDENS)
    print("%d published vectors and goldens, %d failed" % (total, bad))
    return bad == 0


def main(argv):
    if "--check" in argv:
        return 0 if check() else 1
    for row, expr, _want in GOLDENS:
        print("%2d %d" % (row, expr()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
