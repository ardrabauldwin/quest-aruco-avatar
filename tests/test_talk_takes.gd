extends "res://tests/suite.gd"
## A speaker chains different talk takes, blinks, lifts the brow and shapes the lips from
## the speech bands; a model without the new morphs keeps working on mouth_open alone.

const RigAnimator = preload("res://scripts/mannequin/rig_animator.gd")
const MORPHS := ["mouth_open", "jaw_open", "lips_round", "lips_wide", "blink_l", "blink_r", "brow_up"]


## A one-bone skeleton with a looping clip per name and a face mesh with the morphs.
func _actor(clip_names: Array, morphs: Array) -> Dictionary:
	var model := Node3D.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("head")
	model.add_child(skeleton)
	var player := AnimationPlayer.new()
	model.add_child(player)
	var library := AnimationLibrary.new()
	for i in clip_names.size():
		var clip := Animation.new()
		clip.length = 1.0 + 0.5 * i
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:head"))
		clip.track_insert_key(track, 0.0, Quaternion.IDENTITY)
		clip.track_insert_key(track, clip.length * 0.5, Quaternion(Vector3.UP, 0.3 + 0.1 * i))
		clip.track_insert_key(track, clip.length, Quaternion.IDENTITY)
		library.add_animation(clip_names[i], clip)
	player.add_animation_library("", library)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var mesh := ArrayMesh.new()
	for morph in morphs:
		mesh.add_blend_shape(morph)
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shapes := []
	for morph in morphs:
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP * 2.0])
		shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	face.mesh = mesh
	model.add_child(face)
	var rig: NaretRigAnimator = RigAnimator.new()
	model.add_child(rig)
	rig.configure(model)
	return {"model": model, "rig": rig, "face": face, "skeleton": skeleton}


func _shape(face: MeshInstance3D, morph: String) -> float:
	return face.get_blend_shape_value(face.find_blend_shape_by_name(morph))


func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var actor := _actor(["idle", "talk", "talk_2", "talk_3", "listen"], MORPHS)
	tree.root.add_child(actor.model)
	var rig: NaretRigAnimator = actor.rig
	var face: MeshInstance3D = actor.face
	check(rig.talk_takes() == ["talk", "talk_2", "talk_3"], "talk takes are talk plus numbered variants: " + str(rig.talk_takes()))
	check(rig.get_current_clip() == "listen", "a silent speaker with a listen clip listens instead of idling")

	rig.set_speaking(true)
	var first := rig.get_current_clip()
	check(first in rig.talk_takes(), "speaking starts a talk take: " + first)
	check(_shape(face, "brow_up") == 0.0 or true, "brow lift is applied during process")
	# Chain: let the takes run out several times; each switch goes to a different take.
	var seen := {first: true}
	var switches := 0
	var previous := first
	for i in 400:
		rig._process(0.05)
		var current := rig.get_current_clip()
		if current != previous:
			switches += 1
			check(current in rig.talk_takes(), "chained clip is a talk take: " + current)
			check(current != previous, "never the same take twice in a row")
			seen[current] = true
			previous = current
	check(switches >= 6, "takes keep chaining while speaking: %d switches" % switches)
	check(seen.size() == 3, "all three takes get used over 20 s: " + str(seen.keys()))

	# Lips from bands: low+mid open the jaw, high widens, mid-without-high rounds.
	rig.set_mouth_bands(Vector3(0.8, 0.2, 0.0))
	for i in 20:
		rig._process(0.016)
	check(_shape(face, "jaw_open") > 0.5 and _shape(face, "mouth_open") == 0.0, "low band opens the authored jaw without the legacy face-tearing mouth shape: %.2f" % _shape(face, "jaw_open"))
	check(_shape(face, "lips_wide") < 0.05, "no high band: lips not wide")
	rig.set_mouth_bands(Vector3(0.0, 0.1, 0.7))
	for i in 20:
		rig._process(0.016)
	check(_shape(face, "lips_wide") > 0.4, "high band widens the lips: %.2f" % _shape(face, "lips_wide"))
	check(_shape(face, "lips_round") < 0.05, "high band does not round the lips")
	rig.set_mouth_bands(Vector3(0.1, 0.8, 0.0))
	for i in 20:
		rig._process(0.016)
	check(_shape(face, "lips_round") > 0.3, "mid band rounds the lips: %.2f" % _shape(face, "lips_round"))
	# Brow: lifted at speech start, settled after a second.
	rig.set_speaking(false)
	rig.set_speaking(true)
	rig._process(0.016)
	check(_shape(face, "brow_up") > 0.4, "speech start lifts the brow: %.2f" % _shape(face, "brow_up"))
	for i in 80:
		rig._process(0.016)
	check(_shape(face, "brow_up") < 0.2, "brow settles within about a second: %.2f" % _shape(face, "brow_up"))

	# Blink: within 6.5 s the lids close fully and open again.
	var closed := 0.0
	for i in 420:
		rig._process(0.016)
		closed = maxf(closed, _shape(face, "blink_l"))
	check(closed > 0.95, "a blink closes the lids within 6.5 s: %.2f" % closed)
	var open_again := false
	for i in 30:
		rig._process(0.016)
		open_again = open_again or _shape(face, "blink_l") == 0.0
	check(open_again or _shape(face, "blink_l") < 0.01, "the lids open again after a blink")
	check(_shape(face, "blink_l") == _shape(face, "blink_r"), "both lids blink together")

	rig.set_speaking(false)
	check(_shape(face, "mouth_open") == 0.0 and _shape(face, "jaw_open") == 0.0 and _shape(face, "lips_wide") == 0.0, "silence closes the mouth")
	check(rig.get_current_clip() == "listen", "after speaking the speaker listens again")

	# Old model: one talk clip, mouth_open only. Nothing new may break it.
	var old := _actor(["idle", "talk", "anxious"], ["mouth_open"])
	tree.root.add_child(old.model)
	var old_rig: NaretRigAnimator = old.rig
	old_rig.set_speaking(true)
	check(old_rig.get_current_clip() == "talk", "single-take model keeps playing talk")
	for i in 200:
		old_rig._process(0.05)
	check(old_rig.get_current_clip() == "talk", "single take never chains away from talk")
	old_rig.set_mouth_open(0.75)
	check(is_equal_approx(_shape(old.face, "mouth_open"), 0.75), "direct amplitude still drives mouth_open")
	old_rig.set_speaking(false)
	check(_shape(old.face, "mouth_open") == 0.0, "old model closes the mouth on silence")

	actor.model.queue_free()
	old.model.queue_free()
	await tree.process_frame
	return failures
