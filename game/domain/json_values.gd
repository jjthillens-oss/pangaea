class_name JsonValues
extends RefCounted
## Reads fields of a parsed save without trusting their types (Bible section 18). A missing or
## wrong-typed field gets a neutral value and a message in `problems`; the owner reports those
## from validate(), so a damaged file fails to load and the backup is used, instead of loading
## with data quietly emptied (and then overwriting the good backup on the next save).


## A whole number. JSON numbers parse as floats, so 3.0 is accepted; 3.5, text or null are not.
static func whole(data: Dictionary, key: String, problems: Array) -> int:
	var value = data.get(key)
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	problems.append("Field '%s' must be a whole number." % key)
	return 0


static func text(data: Dictionary, key: String, problems: Array) -> String:
	var value = data.get(key)
	if value is String:
		return value
	problems.append("Field '%s' must be text." % key)
	return ""


## A deep copy of a list field.
static func array(data: Dictionary, key: String, problems: Array) -> Array:
	var value = data.get(key)
	if value is Array:
		return (value as Array).duplicate(true)
	problems.append("Field '%s' must be a list." % key)
	return []


## A deep copy of an object field.
static func dict(data: Dictionary, key: String, problems: Array) -> Dictionary:
	var value = data.get(key)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	problems.append("Field '%s' must be an object." % key)
	return {}
