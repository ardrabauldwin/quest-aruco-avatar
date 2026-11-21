extends "res://tests/suite.gd"

func heading_error(a: Basis,b: Basis) -> float:
	return absf(wrapf(atan2(a.z.x,a.z.z)-atan2(b.z.x,b.z.z),-PI,PI))

func run() -> Array[String]:
	var estimator := NaretStartupPlacement.new()
	# Unique circular medoid near the +/-180degree boundary plus a large outlier.
	var angles := [179.0,-179.0,178.0,179.0,0.0]
	var positions := [Vector3(0,.20,0),Vector3(.01,.21,.01),Vector3(4,.19,.04),Vector3(.02,.22,.02),Vector3(.03,.18,.03)]
	var poses: Array[Transform3D] = []
	for i in range(angles.size()):
		poses.append(Transform3D(Basis(Vector3.UP,deg_to_rad(float(angles[i]))),positions[i]))
	var estimate := estimator._robust_estimate(poses)
	check(estimate.origin.is_equal_approx(Vector3(.02,.20,.02)), "XYZ coordinate medians remain independent of heading")
	check(heading_error(estimate.basis,Basis(Vector3.UP,deg_to_rad(179.0)))<.00001, "circular medoid chooses179degrees despite wraparound and zero-degree outlier")
	check(estimate.basis.y.is_equal_approx(Vector3.UP), "floor-locked estimate remains horizontal")
	for angle in [-179.0,-90.0,0.0,45.0,179.0]:
		var pose := Transform3D(Basis(Vector3.UP,deg_to_rad(angle)),Vector3(1,.2,3))
		var samples: Array[Transform3D] = [pose,pose,pose]
		check(estimator._robust_estimate(samples).is_equal_approx(pose), "observed yaw round-trips without a180degree axis reversal")
		var startup := NaretStartupPlacement.new()
		for i in range(41):
			check(startup.observe(pose,i).is_empty(), "yaw-only startup still waits for42stable detections")
		var accepted := startup.observe(pose,41)
		check(accepted.get("samples",0)==42 and (accepted.pose as Transform3D).is_equal_approx(pose), "yaw-only startup accepts the correct observed heading at42")
	# Stable estimates must agree across the +/-180 boundary, not see a360degree jump.
	var wrapped := NaretStartupPlacement.new()
	var accepted: Dictionary = {}
	for i in range(42):
		var angle := 179.9 if i%2==0 else -179.9
		accepted=wrapped.observe(Transform3D(Basis(Vector3.UP,deg_to_rad(angle)),Vector3.ZERO),i)
	check(accepted.get("samples",0)==42, "wrapped headings can converge without a false turn")
	# Explicitly preserve standalone 3D callers that have not floor-locked their input.
	var tilted := Transform3D(Basis(Vector3.UP,.7)*Basis(Vector3.RIGHT,.1),Vector3(1,.2,-1))
	var tilted_samples: Array[Transform3D] = [tilted,tilted,tilted]
	check(estimator._robust_estimate(tilted_samples).is_equal_approx(tilted), "non-floor-locked standalone pose retains pitch and roll")
	# Exercise real marker fusion to verify floor lock precedes the yaw estimator.
	var layout := NaretMarkerLayout.new()
	layout.offsets={0:Transform3D.IDENTITY}
	layout.floor_orientation=true
	var fused := layout.fuse({0:tilted})
	var fused_pose: Transform3D=fused.pose
	check(fused_pose.basis.y.is_equal_approx(Vector3.UP), "marker fusion produces horizontal pose before placement")
	var fused_samples: Array[Transform3D] = [fused_pose,fused_pose,fused_pose]
	check(estimator._robust_estimate(fused_samples).is_equal_approx(fused_pose), "post-floor-lock yaw estimator preserves marker heading and position")
	return failures
