extends RefCounted
## Use the established local-floor reference, not a stream of independent floor
## measurements. Retain it in tracking coordinates for coordinate recentering.
var ready := false
var _point := Vector3.ZERO

func height_world(reference_y: float, tracking_to_world: Transform3D) -> float:
	if not tracking_to_world.is_finite() or absf(tracking_to_world.basis.determinant()) < 0.000001:
		return NAN
	if not ready:
		if not is_finite(reference_y):
			return NAN
		var world_point := tracking_to_world.origin
		world_point.y = reference_y
		_point = tracking_to_world.affine_inverse() * world_point
		ready = true
	return (tracking_to_world * _point).y
