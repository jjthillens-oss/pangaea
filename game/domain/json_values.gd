class_name JsonValues
extends RefCounted
## Reads values parsed from save files without trusting their types. A wrong or missing value
## becomes a fallback that validation then reports, instead of stopping the loader with a script
## error (Bible section 18: a damaged save must fail cleanly and fall back to the backup).


## A JSON number as an int (JSON numbers parse as floats); anything else becomes `fallback`.
static func whole(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(value)
	return fallback


## A deep copy of an array, or an empty array for anything else.
static func array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


## A deep copy of a dictionary, or an empty dictionary for anything else.
static func dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
