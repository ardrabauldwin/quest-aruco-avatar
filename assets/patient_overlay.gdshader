shader_type spatial;
render_mode cull_back;
uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.75;
uniform vec3 head_world;
uniform float surface_roughness = 0.8;
uniform bool clinical_skin = false;
uniform bool pe_visual_cues = false;
uniform vec3 mouth_world;
uniform vec3 calf_world;
uniform mat3 patient_inverse = mat3(1.0);
// Hand press (NaretMannequin.set_hand_press): the chest under the rescuer's
// hands is pushed down to the hands' height. press_point is the dent's lowest
// point in world space, press_depth how far it lies below the resting chest.
uniform vec3 press_point;
uniform float press_depth = 0.0;
uniform float press_radius = 0.05;
uniform float press_falloff = 0.09;

void vertex() {
    if (clinical_skin && pe_visual_cues) {
        vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        vec3 calf = patient_inverse * (world - calf_world);
        float mask = 1.0 - smoothstep(0.6, 1.0, length(calf / vec3(0.14, 0.14, 0.22)));
        // Mild local swelling, not a change to patient scale or alignment.
        vec3 shift = vec3(calf.x, calf.y, 0.0) * (0.12 * mask);
        VERTEX += (inverse(MODEL_MATRIX) * vec4(inverse(patient_inverse) * shift, 0.0)).xyz;
    }
    if (press_depth > 0.0005) {
        vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        vec3 rel = world - press_point;
        // Flat under the hand, easing back to rest around it. Only skin above
        // the hand moves, by at most press_depth: the back never does.
        float weight = 1.0 - smoothstep(press_radius, press_radius + press_falloff, length(rel.xz));
        float push = clamp(rel.y, 0.0, press_depth) * weight;
        VERTEX += (inverse(MODEL_MATRIX) * vec4(0.0, -push, 0.0, 0.0)).xyz;
    }
}

void fragment() {
    vec4 colour = tint;
    if (has_texture) colour *= texture(skin_texture, UV);
    if (colour.a < 0.1) discard;
    vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (clinical_skin && pe_visual_cues) {
        vec3 mouth = patient_inverse * (world_position - mouth_world);
        float lips = 1.0 - smoothstep(0.45, 1.0, length(mouth / vec3(0.045, 0.050, 0.035)));
        vec3 calf = patient_inverse * (world_position - calf_world);
        float leg = 1.0 - smoothstep(0.45, 1.0, length(calf / vec3(0.14, 0.14, 0.22)));
        colour.rgb = mix(colour.rgb, vec3(0.30, 0.34, 0.58), lips * 0.80);
        colour.rgb = mix(colour.rgb, vec3(0.48, 0.23, 0.28), leg * 0.65);
    }
    // Keep the face solid: teeth and eyeballs must not show through its skin.
    // Elsewhere use a fixed 4x4 coverage mask, with normal opaque depth testing.
    // This avoids blending every overlapping human surface into a ghost.
    if (distance(world_position, head_world) > 0.18) {
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float bayer[16] = float[16](0.0,8.0,2.0,10.0,12.0,4.0,14.0,6.0,3.0,11.0,1.0,9.0,15.0,7.0,13.0,5.0);
        if (opacity <= (bayer[y * 4 + x] + 0.5) / 16.0) discard;
    }
    ALBEDO = colour.rgb;
    ROUGHNESS = surface_roughness;
}
