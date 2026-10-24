extends SceneTree
## Sanity: does a --script SceneTree print on the runner's debug exe?
var n := 0


func _init() -> void:
	print("probe0: init")


func _process(_d: float) -> bool:
	n += 1
	if n % 30 == 0:
		print("probe0: frame %d" % n)
	return n >= 90
