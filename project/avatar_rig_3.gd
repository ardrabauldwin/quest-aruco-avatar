extends Node3D
# Put the avatar on the manikin, from however many ArUco markers you list.
#
#   anchor   = centroid of the markers   (2 markers -> their midpoint; 3 -> centre of the triangle)
#   rotation = their average
#   then position_offset slides the mesh onto the body -- needed because the model's origin is not
#   a body part: it floats ~11cm BEHIND the manikin's back, wherever the scan happened to be authored.
#
# Markers (5cm, DICT_4X4_50) go on the chest: id0 left infraclavicular, id1 lower chest,
# id2 right infraclavicular. Not the head -- a skull is too curved for a 5cm marker to sit flat,
# and the bust is one rigid shell anyway, so the head cannot move on its own.

# Drag aruco_patch0 / 1 / 2 in here. Any number works.
@export var markers: Array[Node3D] = []
# Negated centroid of the three chest spots, measured off the mesh. Tune by eye from here.
@export var position_offset := Vector3(-0.003, -0.221, -0.085)
# Get this RIGHT FIRST: position_offset is applied through this rotation, so a wrong twist sends
# the nudge in a wrong direction and you will chase your tail.
@export var extra_rotation_degrees := Vector3(-90, 0, 0)

func _process(_delta: float) -> void:
	if markers.is_empty():
		return

	var centre := Vector3.ZERO
	var acc := Quaternion(0, 0, 0, 0)
	var ref: Quaternion = markers[0].global_basis.get_rotation_quaternion()
	for m in markers:
		centre += m.global_position
		var q: Quaternion = m.global_basis.get_rotation_quaternion()
		# q and -q are the SAME rotation. Without this they would cancel instead of averaging.
		if ref.dot(q) < 0.0:
			q = -q
		acc = Quaternion(acc.x + q.x, acc.y + q.y, acc.z + q.z, acc.w + q.w)
	centre /= float(markers.size())

	# Sum-then-normalise is the cheap quaternion mean. slerp can't do it: it only takes two, and
	# chaining it isn't associative (the result would depend on marker order).
	var basis := Basis(acc.normalized()) * Basis.from_euler(extra_rotation_degrees * (PI / 180.0))
	global_transform = Transform3D(basis, centre + basis * position_offset)
