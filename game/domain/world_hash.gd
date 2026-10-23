class_name WorldHash
extends RefCounted
## The endless world's stateless hashes (S1 spine 3.2). Every endless stream that is not a seeded
## RandomNumberGenerator comes from here: tile picks, shell dressings, landmarks, rare blocks, zone
## stream seeds, creature numbers, brain seeds and respawn delays. Each is a pure function of the
## world seed, the generator version and fixed coordinates, so the same seed builds the same sea
## along any route.
##
## hash_ints is MurmurHash3_x86_32 (its author placed it in the public domain) over each int as two
## little-endian 32-bit words, low word first, with seed SEED0 and length 8 x count. Purpose strings
## use FNV-1a 32, also public domain. Every product goes through mul32, so no 64-bit int ever
## overflows. The engine's hash() is never used: it may change with an engine upgrade.
## tools/world_hash_ref.py is an independent Python reference, and tests/test_world_hash.gd pins
## twenty golden values both agree on.
##
## Callers precompute str32 of their fixed purposes once (a static var), since a str32 costs about a
## microsecond and hash_ints of six ints about 14 (S1 spine 0.4).

const MASK := 0xFFFFFFFF
const SEED0 := 0x9747B28C
const _C1 := 0xCC9E2D51
const _C2 := 0x1B873593
const _FNV_OFFSET := 0x811C9DC5
const _FNV_PRIME := 0x01000193


## (a * b) mod 2^32 for a, b in [0, 2^32), without a product above 2^48.
static func mul32(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK


## x in [0, 2^32) rotated left by r bits (0 < r < 32).
static func rotl32(x: int, r: int) -> int:
	return ((x << r) | (x >> (32 - r))) & MASK


## The MurmurHash3 finaliser.
static func fmix32(h: int) -> int:
	h &= MASK
	h ^= h >> 16
	h = mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


## MurmurHash3_x86_32 of the values' little-endian 64-bit encodings, in [0, 2^32).
static func hash_ints(values: PackedInt64Array) -> int:
	var h := SEED0
	for v in values:
		# >> is arithmetic, so & MASK takes each word's bit pattern, negative values included.
		h = _block(h, v & MASK)
		h = _block(h, (v >> 32) & MASK)
	h ^= (8 * values.size()) & MASK
	return fmix32(h)


## FNV-1a 32 over the string's UTF-8 bytes.
static func str32(s: String) -> int:
	var h := _FNV_OFFSET
	for byte in s.to_utf8_buffer():
		h = mul32(h ^ byte, _FNV_PRIME)
	return h


## hash_ints([a, b]).
static func mix32(a: int, b: int) -> int:
	return hash_ints(PackedInt64Array([a, b]))


## The hash of one purpose at one place: hash_ints([seed, gen_version, band, tx, ty, str32(purpose)]).
static func key(seed: int, gen_version: int, band: int, tx: int, ty: int, purpose: String) -> int:
	return hash_ints(PackedInt64Array([seed, gen_version, band, tx, ty, str32(purpose)]))


## A hash as a float in [0, 1).
static func unit(h: int) -> float:
	return h / 4294967296.0


## A hash as an index in [0, count). count must be at least 1 (0 and an error otherwise).
static func pick(h: int, count: int) -> int:
	if count < 1:
		push_error("WorldHash.pick: count %d < 1" % count)
		return 0
	return h % count


## One MurmurHash3 round: the 32-bit block `word` mixed into `h`.
static func _block(h: int, word: int) -> int:
	var k := mul32(word, _C1)
	k = rotl32(k, 15)
	k = mul32(k, _C2)
	h ^= k
	h = rotl32(h, 13)
	return (mul32(h, 5) + 0xE6546B64) & MASK
