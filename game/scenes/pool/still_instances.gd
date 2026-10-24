class_name StillInstances
extends MultiMeshInstance3D
## A MultiMeshInstance3D whose instances are set once and never move (the growth beat's old food copies
## and glitter, S2 s2-view 4.6). It keeps its instance transforms beside the MultiMesh, so they can be
## read where the renderer cannot hand a MultiMesh back (headless, the dummy renderer): the tests and
## the frame-0 checks read `transforms`.

## Every instance's transform, in the node's own space.
var transforms: Array[Transform3D] = []


## A still MultiMesh of `mesh` drawn at `p_transforms`, casting no shadow.
static func make(mesh: Mesh, p_transforms: Array[Transform3D]) -> StillInstances:
	var still := StillInstances.new()
	still.transforms = p_transforms
	still.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = p_transforms.size()
	for i in p_transforms.size():
		mm.set_instance_transform(i, p_transforms[i])
	still.multimesh = mm
	return still
