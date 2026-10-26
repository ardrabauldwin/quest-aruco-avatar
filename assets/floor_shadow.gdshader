shader_type spatial;
// Overlay pass that flattens a mesh onto the floor along the key light, so a
// virtual person casts a shadow onto the real floor seen through passthrough.
// The Compatibility renderer never writes shadow-map shadows to alpha, so a
// shadow-catcher plane (shadow_to_opacity) cannot do this.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled, world_vertex_coords;
// Overlapping limbs (and both bystanders) darken the floor once, not twice.
stencil_mode read, write, compare_not_equal, 1;

uniform vec3 light_direction = vec3(0.0, -1.0, 0.0);
uniform float floor_y = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.45;
varying float height;

void vertex() {
    height = max(VERTEX.y - floor_y, 0.0);
    vec3 direction = normalize(light_direction);
    // A grazing light would stretch the shadow across the room; clamp it.
    VERTEX += direction * (height / max(-direction.y, 0.3));
    VERTEX.y = floor_y + 0.003;
}

void fragment() {
    ALBEDO = vec3(0.0);
    // Indoor light is diffuse: dark at the feet, fainter where the head falls.
    ALPHA = opacity * mix(1.0, 0.55, smoothstep(0.0, 1.7, height));
}
