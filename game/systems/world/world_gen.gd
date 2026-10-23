class_name WorldGen
extends RefCounted
## The endless world's generator (S1): which tile lies where, and what each 32 x 32 tm chunk holds,
## as a pure function of (world_seed, gen_version, content, size, chunk). It binds the seed, the
## generator version and the content at creation (docs/s1/s1-interfaces.md, D-7), reads no clock,
## input, tree or global random numbers, and gives the same chunk along any route.
##
## T1.1 stub: chunk() gives an empty chunk until the arrangement (T1.8) and the chunk content (T1.9)
## land; the pinned API is in place for the streaming block to build on.

var content: WorldContent
var species: SpeciesCatalog
var world_seed := 0
var gen_version := 1


static func create(p_content: WorldContent, p_species: SpeciesCatalog, p_world_seed: int) -> WorldGen:
	var gen := WorldGen.new()
	gen.setup(p_content, p_species, p_world_seed)
	return gen


## Binds the immutable inputs. create() calls it; a subclass (a test's fake generator) made with
## new() calls it too.
func setup(p_content: WorldContent, p_species: SpeciesCatalog, p_world_seed: int) -> void:
	content = p_content
	species = p_species
	world_seed = p_world_seed
	gen_version = p_content.config.gen_version if p_content != null and p_content.config != null else 1


## The chunk (cx, cy) at size n: every object whose centre lies in it, in absolute tm.
func chunk(n: int, cx: int, cy: int) -> WorldChunk:
	var out := WorldChunk.new()
	out.key = Vector2i(cx, cy)
	out.size = n
	return out


## {id, region: "sunlit"|"reef"|"drift"|"home"|"rare", rare, set, orientation} of tile (tx, ty) in band b.
func tile_info(_band: int, _tx: int, _ty: int) -> Dictionary:
	return {}


## {tile: Vector2i, model, dressing} of landmark cell (lx, ly) in band b, or {} when it has none.
func landmark_of_cell(_band: int, _lx: int, _ly: int) -> Dictionary:
	return {}
