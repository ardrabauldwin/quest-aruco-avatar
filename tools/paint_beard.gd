extends SceneTree
## Paints Marek's beard into a copy of the male bystander's skin texture.
##   godot --headless --xr-mode off --path . --script tools/paint_beard.gd
## Marek and the instructor share human_bystander_male.glb; only the texture differs
## (NaretBystander.set_look). The beard region comes from the model itself, so it
## follows a regenerated face: the vertices the jaw_open morph moves are the lower jaw
## and chin, fading out up the cheeks; the lower lip is cut out, a moustache added.
const MODEL := "res://assets/models/human_bystander_male.glb"
const OUT := "res://assets/models/human_bystander_marek_skin.png"
const HAIR := Color(0.105, 0.075, 0.055)
const DENSITY := 0.88

func _init() -> void:
	var model: Node3D = load(MODEL).instantiate()
	var body: MeshInstance3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).ends_with("Body"): body = node
	var mesh := body.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var jaw := -1
	for i in mesh.get_blend_shape_count():
		if String(mesh.get_blend_shape_name(i)).to_lower() in ["jaw_open", "jawopen"]: jaw = i
	var shape: PackedVector3Array = mesh.surface_get_blend_shape_arrays(0)[jaw][Mesh.ARRAY_VERTEX]
	# Stored either as positions or as offsets; offsets are small against the body.
	var absolute := 0.0
	for i in range(0, vertices.size(), 50): absolute += shape[i].length()
	var is_offset := absolute / (vertices.size() / 50.0) < 0.05 * mesh.get_aabb().size.y
	var move := PackedFloat32Array()
	move.resize(vertices.size())
	var peak := 0.0
	for i in vertices.size():
		move[i] = (shape[i] if is_offset else shape[i] - vertices[i]).length()
		peak = maxf(peak, move[i])
	var unit := mesh.get_aabb().size.y / 1.78 # mesh units per metre of a 1.78 m man
	# Mouth line: where still upper-lip vertices meet moving lower-lip ones at the front.
	var front := -INF
	for i in vertices.size():
		if move[i] > 0.5 * peak: front = maxf(front, vertices[i].z)
	var mouth := Vector3.ZERO
	var count := 0
	for i in vertices.size():
		if move[i] > 0.6 * peak and absf(vertices[i].x) < 0.012 * unit and vertices[i].z > front - 0.02 * unit:
			for j in vertices.size():
				if move[j] < 0.05 * peak and vertices[j].distance_to(vertices[i]) < 0.008 * unit:
					mouth += (vertices[i] + vertices[j]) * 0.5
					count += 1
	if count == 0:
		push_error("mouth line not found")
		quit(1)
		return
	mouth /= count
	print("BEARD mouth=", mouth / unit, " unit=", unit, " offsets=", is_offset, " peak_m=", peak / unit)
	var weight := PackedFloat32Array()
	weight.resize(vertices.size())
	for i in vertices.size():
		var p := (vertices[i] - mouth) / unit # metres from the mouth centre
		var w := clampf(move[i] / peak * 1.9 - 0.12, 0.0, 1.0)
		# Sideburn fade is the morph's own falloff; keep the throat below the chin clear.
		w *= clampf((p.y + 0.085) / 0.03, 0.0, 1.0)
		# Lower lip: a flat ellipse just under the mouth line.
		var lip := Vector2(p.x / 0.030, (p.y + 0.008) / 0.011).length()
		if p.z > -0.03: w *= clampf((lip - 0.85) / 0.35, 0.0, 1.0)
		# Moustache: between the upper lip's edge and the nose, out to the mouth corners.
		if p.z > -0.035 and p.y > 0.0:
			var band := clampf((p.y - 0.007) / 0.004, 0.0, 1.0) * clampf((0.021 - p.y) / 0.005, 0.0, 1.0)
			var wide := clampf((0.036 - absf(p.x)) / 0.008, 0.0, 1.0)
			w = maxf(w, band * wide)
		# Down past the mouth corners, joining moustache and chin.
		if p.z > -0.04 and p.y <= 0.008 and p.y > -0.03 and absf(p.x) > 0.024 and absf(p.x) < 0.040:
			w = maxf(w, 0.9)
		weight[i] = w
	var source := load(MODEL.get_base_dir() + "/human_bystander_male_young_lightskinned_male_diffuse.png") as Texture2D
	var image := source.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var size := image.get_size()
	var mask := PackedFloat32Array()
	mask.resize(size.x * size.y)
	for t in range(0, indices.size(), 3):
		var a := indices[t]; var b := indices[t + 1]; var c := indices[t + 2]
		if weight[a] + weight[b] + weight[c] <= 0.0: continue
		var pa := uvs[a] * Vector2(size); var pb := uvs[b] * Vector2(size); var pc := uvs[c] * Vector2(size)
		var lo := pa.min(pb).min(pc).floor()
		var hi := pa.max(pb).max(pc).ceil()
		var area := (pb - pa).cross(pc - pa)
		if absf(area) < 0.0001: continue
		for y in range(maxi(int(lo.y) - 1, 0), mini(int(hi.y) + 2, size.y)):
			for x in range(maxi(int(lo.x) - 1, 0), mini(int(hi.x) + 2, size.x)):
				var p := Vector2(x + 0.5, y + 0.5)
				var wa := (pb - p).cross(pc - p) / area
				var wb := (pc - p).cross(pa - p) / area
				var wc := 1.0 - wa - wb
				if wa < -0.03 or wb < -0.03 or wc < -0.03: continue
				mask[y * size.x + x] = maxf(mask[y * size.x + x], clampf(wa * weight[a] + wb * weight[b] + wc * weight[c], 0.0, 1.0))
	# Soften the edge, then break it up with short-hair grain.
	var radius := maxi(size.x / 512, 1)
	var soft := mask.duplicate()
	for y in range(radius, size.y - radius):
		for x in range(radius, size.x - radius):
			var here := y * size.x + x
			if mask[here] <= 0.0 and mask[here - radius] <= 0.0 and mask[here + radius] <= 0.0 and mask[here - radius * size.x] <= 0.0 and mask[here + radius * size.x] <= 0.0: continue
			var total := 0.0
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1): total += mask[here + dy * size.x + dx]
			soft[here] = total / float((2 * radius + 1) * (2 * radius + 1))
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.35
	var painted := 0
	for y in size.y:
		for x in size.x:
			var w := soft[y * size.x + x]
			if w <= 0.01: continue
			var grain := 0.5 + 0.5 * noise.get_noise_2d(x * 2048.0 / size.x, y * 2048.0 / size.y)
			var amount := clampf(w * DENSITY * (0.72 + 0.28 * grain) - (1.0 - w) * 0.25 * grain, 0.0, 1.0)
			var skin := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(lerpf(skin.r, HAIR.r, amount), lerpf(skin.g, HAIR.g, amount), lerpf(skin.b, HAIR.b, amount), skin.a))
			painted += 1
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("BEARD painted_pixels=", painted, " size=", size, " -> ", OUT)
	model.free()
	quit()
