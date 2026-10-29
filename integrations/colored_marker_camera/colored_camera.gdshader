shader_type canvas_item;
render_mode unshaded;
uniform sampler2D chroma_texture : filter_linear, repeat_disable;
uniform bool luminance_only = false;
void fragment() {
	float y = texture(TEXTURE, UV).r;
	vec2 chroma = texture(chroma_texture, UV).rg - vec2(0.5);
	// Full-range BT.601 YCbCr. Hue segmentation tolerates modest range errors.
	vec3 rgb = clamp(vec3(y + 1.402 * chroma.y,
		y - 0.344136 * chroma.x - 0.714136 * chroma.y,
		y + 1.772 * chroma.x), vec3(0.0), vec3(1.0));
	float hi = max(rgb.r, max(rgb.g, rgb.b));
	float lo = min(rgb.r, min(rgb.g, rgb.b));
	float delta = hi - lo;
	float h = 0.0;
	if (delta > 0.0001) {
		if (hi == rgb.r) h = mod((rgb.g - rgb.b) / delta, 6.0);
		else if (hi == rgb.g) h = (rgb.b - rgb.r) / delta + 2.0;
		else h = (rgb.r - rgb.g) / delta + 4.0;
		h = mod(h * 30.0 + 180.0, 180.0);
	}
	float saturation = delta / max(hi, 0.0001);
	float value = y;
	if (!luminance_only && saturation >= 0.20 && hi >= 0.20) {
		if (h >= 90.0 && h <= 130.0) value = 1.0;
		else if (h <= 30.0) value = 0.0;
	}
	COLOR = vec4(vec3(value), 1.0);
}
