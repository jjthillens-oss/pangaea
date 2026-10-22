class_name StableId
extends RefCounted
## Stable identifiers for lineages, genomes and other records. They never depend on scene paths
## or file names, so renaming files cannot break references (Bible sections 12 and 18).


static func generate(prefix: String) -> String:
	var bytes := Crypto.new().generate_random_bytes(8)
	return "%s_%s" % [prefix, bytes.hex_encode()]


static func is_valid(id: String, prefix: String) -> bool:
	if not id.begins_with(prefix + "_"):
		return false
	var body := id.substr(prefix.length() + 1)
	return body.length() == 16 and body.is_valid_hex_number()
