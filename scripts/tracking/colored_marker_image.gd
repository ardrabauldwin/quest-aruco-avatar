extends RefCounted
## Orange replaces black; blue replaces white. Operates only on detector input.
## No resizing: camera intrinsics and detected-corner coordinates stay unchanged.
static func convert(image: Image) -> Image:
	var source := image.duplicate() as Image
	if source.get_format() == Image.FORMAT_R8 or source.get_format() == Image.FORMAT_L8:
		# Quest's luminance-only feed has no hue. Inversion assumes orange is
		# brighter than blue; real camera frames must validate that assumption.
		var pixels := source.get_data()
		for index in range(pixels.size()): pixels[index] = 255 - pixels[index]
		return Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_L8, pixels)
	source.convert(Image.FORMAT_RGB8)
	var rgb := source.get_data()
	var gray := PackedByteArray()
	gray.resize(source.get_width() * source.get_height())
	for index in range(gray.size()):
		var offset := index * 3
		var colour := Color8(rgb[offset], rgb[offset + 1], rgb[offset + 2])
		# Initial HSV bounds, not calibrated to the user's print or lighting.
		var hue := colour.h * 180.0
		if colour.s >= 0.20 and colour.v >= 0.20 and hue >= 90.0 and hue <= 130.0:
			gray[index] = 255 # blue cells become white
		elif colour.s >= 0.20 and colour.v >= 0.20 and hue <= 30.0:
			gray[index] = 0 # orange cells and border become black
		else:
			gray[index] = int(colour.v * (1.0 - colour.s) * 255.0)
	return Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_L8, gray)
