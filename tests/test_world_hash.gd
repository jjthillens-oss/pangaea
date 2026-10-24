extends TestCase
## WorldHash (S1 spine 3.2, gate G23): the twenty goldens, which tools/world_hash_ref.py computes
## independently in Python; hash_ints against a byte-wise MurmurHash3 written here from the published
## algorithm (and checked against published vectors); mul32 against a product split another way;
## str32 against published FNV-1a vectors; and no use of the engine's hash().

const SEED0 := 0x9747B28C


## The twenty rows of spine 3.2, (row, value, expected).
func _goldens() -> Array:
	var int64_min := -9223372036854775807 - 1   # GDScript cannot write -9223372036854775808
	return [
		[1, WorldHash.hash_ints(PackedInt64Array([])), 3954623016],
		[2, WorldHash.hash_ints(PackedInt64Array([0])), 773692376],
		[3, WorldHash.hash_ints(PackedInt64Array([1])), 619189011],
		[4, WorldHash.hash_ints(PackedInt64Array([-1])), 1971636267],
		[5, WorldHash.hash_ints(PackedInt64Array([4294967295])), 4209728847],
		[6, WorldHash.hash_ints(PackedInt64Array([4294967296])), 3342626163],
		[7, WorldHash.hash_ints(PackedInt64Array([int64_min])), 3700897005],
		[8, WorldHash.hash_ints(PackedInt64Array([9223372036854775807])), 3188012228],
		[9, WorldHash.mix32(0, 0), 205331723],
		[10, WorldHash.mix32(1, 2), 4166365685],
		[11, WorldHash.mix32(2, 1), 770582150],
		[12, WorldHash.mix32(-3, 5), 2158776994],
		[13, WorldHash.str32("tile"), 1899658441],
		[14, WorldHash.str32("plankton"), 719942472],
		[15, WorldHash.key(0, 1, 0, 0, 0, "tile"), 4436494],
		[16, WorldHash.key(4242, 1, 0, -1, -1, "tile"), 2926877857],
		[17, WorldHash.key(4242, 1, 0, 2, -1, "rare"), 4053045797],
		[18, WorldHash.key(4294967295, 1, 0, 1000, -1000, "landmark"), 3684426704],
		[19, 1 + WorldHash.mix32(WorldHash.str32("lair_se"), 0) % 1073741824, 246455513],
		[20, WorldHash.hash_ints(PackedInt64Array([4242, 1, WorldHash.str32("t_0_3_7_r1"), 2, WorldHash.str32("brain")])), 2622104930],
	]


func test_the_twenty_goldens_hold() -> void:
	var rows := _goldens()
	check_eq(rows.size(), 20, "rows")
	for row in rows:
		check_eq(row[1], row[2], "golden row %d" % row[0])


## MurmurHash3_x86_32 over `data`, read in 4-byte little-endian blocks as the published algorithm
## reads them (the tail is handled too, so the published vectors can check this function). Unlike
## WorldHash.mul32 it multiplies whole 32-bit values: the product may pass 2^63 and wrap negative,
## and & mask still keeps its low 32 bits exactly.
static func _murmur3_bytes(data: PackedByteArray, seed_value: int) -> int:
	var mask := 0xFFFFFFFF
	var h := seed_value & mask
	var blocks := data.size() / 4
	for i in blocks:
		var k := data.decode_u32(4 * i)
		k = (k * 0xCC9E2D51) & mask
		k = ((k << 15) | (k >> 17)) & mask
		k = (k * 0x1B873593) & mask
		h ^= k
		h = ((h << 13) | (h >> 19)) & mask
		h = (h * 5 + 0xE6546B64) & mask
	var tail := data.size() - 4 * blocks
	if tail > 0:
		var k := 0
		for j in range(tail - 1, -1, -1):
			k = (k << 8) | data[4 * blocks + j]
		k = (k * 0xCC9E2D51) & mask
		k = ((k << 15) | (k >> 17)) & mask
		k = (k * 0x1B873593) & mask
		h ^= k
	h ^= data.size()
	h ^= h >> 16
	h = (h * 0x85EBCA6B) & mask
	h ^= h >> 13
	h = (h * 0xC2B2AE35) & mask
	h ^= h >> 16
	return h


func _bytes_of(values: PackedInt64Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(8 * values.size())
	for i in values.size():
		data.encode_s64(8 * i, values[i])
	return data


func test_the_byte_wise_reference_matches_published_murmur3_vectors() -> void:
	var vectors := [
		[PackedByteArray(), 0, 0x00000000],
		[PackedByteArray(), 1, 0x514E28B7],
		[PackedByteArray(), 0xFFFFFFFF, 0x81F16F39],
		[PackedByteArray([0, 0, 0, 0]), 0, 0x2362F9DE],
		[PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF]), 0, 0x76293B50],
		[PackedByteArray([0x21, 0x43, 0x65, 0x87]), 0, 0xF55B516B],
		[PackedByteArray([0x21, 0x43, 0x65, 0x87]), 0x5082EDEE, 0x2362F9DE],
		[PackedByteArray([0x21, 0x43, 0x65]), 0, 0x7E4A8634],
		[PackedByteArray([0x21, 0x43]), 0, 0xA0F7B07A],
		[PackedByteArray([0x21]), 0, 0x72661CF4],
		["aaaa".to_utf8_buffer(), SEED0, 0x5A97808A],
		["Hello, world!".to_utf8_buffer(), SEED0, 0x24884CBA],
	]
	for v in vectors:
		check_eq(_murmur3_bytes(v[0], v[1]), v[2], "murmur3 of %s seed 0x%X" % [v[0], v[1]])


func test_hash_ints_equals_byte_wise_murmur3_on_little_endian_int64s() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lists: Array[PackedInt64Array] = [PackedInt64Array([0]), PackedInt64Array([-1]), PackedInt64Array([1 << 62]),
		PackedInt64Array([-9223372036854775807 - 1]), PackedInt64Array([9223372036854775807])]
	for n in 200:
		var values := PackedInt64Array()
		for i in rng.randi_range(0, 8):
			values.append((rng.randi() << 32) | rng.randi())   # any 64-bit pattern, negatives included
		lists.append(values)
	for values in lists:
		check_eq(WorldHash.hash_ints(values), _murmur3_bytes(_bytes_of(values), SEED0), "hash_ints(%s)" % values)


func test_mul32_never_overflows_and_matches_the_masked_product() -> void:
	var edges := [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]
	var pairs: Array = []
	for a in edges:
		for b in edges:
			pairs.append([a, b])
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for i in 10000:
		pairs.append([rng.randi(), rng.randi()])
	for p in pairs:
		var a: int = p[0]
		var b: int = p[1]
		var got := WorldHash.mul32(a, b)
		check(got >= 0 and got <= 0xFFFFFFFF, "mul32(%d, %d) = %d in [0, 2^32)" % [a, b, got])
		# Both operands split into 16-bit halves: not the implementation's formula.
		var al := a & 0xFFFF
		var ah := a >> 16
		var bl := b & 0xFFFF
		var bh := b >> 16
		var want := (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF
		if got != want:
			check_eq(got, want, "mul32(%d, %d)" % [a, b])
			return
	check_eq(WorldHash.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1, "(2^32 - 1)^2 mod 2^32")


func test_str32_matches_fnv1a_vectors() -> void:
	check_eq(WorldHash.str32(""), 0x811C9DC5, "empty")
	check_eq(WorldHash.str32("a"), 0xE40C292C, "a")
	check_eq(WorldHash.str32("foobar"), 0xBF9CF968, "foobar")
	var bytes := "é".to_utf8_buffer()
	check_eq(bytes.size(), 2, "é is two UTF-8 bytes")
	var h := 0x811C9DC5
	for byte in bytes:
		h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
	check_eq(WorldHash.str32("é"), h, "é hashes its UTF-8 bytes")


func test_key_hashes_its_inputs_in_the_pinned_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var purposes := ["tile", "shell", "landmark", "rare", "region"]
	for i in 50:
		var s := rng.randi()
		var g := rng.randi_range(1, 4)
		var b := rng.randi_range(0, 4)
		var tx := rng.randi_range(-100000, 100000)
		var ty := rng.randi_range(-100000, 100000)
		var p: String = purposes[i % purposes.size()]
		check_eq(WorldHash.key(s, g, b, tx, ty, p), WorldHash.hash_ints(PackedInt64Array([s, g, b, tx, ty, WorldHash.str32(p)])),
			"key(%d, %d, %d, %d, %d, %s)" % [s, g, b, tx, ty, p])
	check(WorldHash.key(4242, 1, 0, 3, 5, "tile") != WorldHash.key(4242, 1, 0, 5, 3, "tile"), "tx and ty are not interchangeable")
	check(WorldHash.mix32(1, 2) != WorldHash.mix32(2, 1), "mix32 is ordered")


func test_unit_and_pick_ranges() -> void:
	check_eq(WorldHash.unit(0), 0.0, "unit(0)")
	check_eq(WorldHash.unit(0xFFFFFFFF), 4294967295.0 / 4294967296.0, "unit of the largest hash")
	check(WorldHash.unit(0xFFFFFFFF) < 1.0, "unit stays below 1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 1000:
		var h := WorldHash.mix32(i, rng.randi())
		check(h >= 0 and h <= 0xFFFFFFFF, "a hash is in [0, 2^32)")
		for n in [1, 3, 8]:
			var k := WorldHash.pick(h, n)
			check(k >= 0 and k < n, "pick(%d, %d) = %d" % [h, n, k])
	check_eq(WorldHash.pick(12345, 0), 0, "pick with no choices gives 0 (and an error)")


func test_world_hash_uses_no_engine_hash() -> void:
	var source := FileAccess.get_file_as_string("res://game/domain/world_hash.gd")
	check(source.contains("static func hash_ints"), "world_hash.gd readable")
	var code := PackedStringArray()
	for line in source.split("\n"):
		code.append(line.get_slice("#", 0))   # comments may name hash(); the file has no "#" in a string
	var re := RegEx.new()
	re.compile("(?<![A-Za-z_])hash\\(")
	check(re.search("\n".join(code)) == null, "world_hash.gd calls the engine's hash()")
	check(re.search("var h := hash(x)") != null and re.search("var h := s.hash()") != null, "the scan sees a call")
	check(re.search("var h := hash_ints(x)") == null and re.search("rehash(x)") == null, "other names are fine")
