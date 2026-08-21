shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Depth-banded smooth-terrain look (F11 shader rules, F14 fallback): the
// transvoxel mesher has no per-voxel visuals, so the ONE terrain material
// blends two triplanar band textures by depth below the PRISTINE surface.
// The height bake is written by SmoothGrid from the same TerrainGenDef math
// as TerrainStrata (F13 noise closed form / F10 heightmap wrap), so the
// visible bands line up with the mining strata bands. Authored blobs are
// visually identified by Decal markers instead of voxel data (F14).
//
// Decode idiom (floatBitsToUint byte packing for CUSTOM1) intentionally NOT
// used: this shader predates the F14 no-go and reads no custom attributes.
// Triplanar weighting follows the standard zylann.voxel demo approach
// (assets/blocks/block_shader.gdshader uses the same world-hash variation
// trick); written from scratch for this project.

// R channel = pristine surface height in meters at world XZ
// (uv = xz / bake_span + 0.5, centered on the origin, repeats beyond).
uniform sampler2D height_map : repeat_enable, filter_linear, hint_default_black;
uniform sampler2D ground_tex : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
uniform vec3 ground_tint = vec3(0.545, 0.435, 0.278);
uniform vec3 rock_tint = vec3(0.541, 0.541, 0.561);
// Depth in meters below the pristine surface where ground fades into rock,
// and the fade width. Defaults match the shipped defs (ground max_depth 3);
// SmoothGrid pushes the catalog's actual values.
uniform float band_center_depth = 3.0;
uniform float band_width = 2.0;
uniform float texels_per_meter = 0.25;
uniform float bake_span = 512.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Steep faces sample their side planes, flat tops sample XZ.
vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec3 triplanar_sample(sampler2D tex, vec3 p, vec3 w) {
	vec3 x = texture(tex, p.zy * texels_per_meter).rgb;
	vec3 y = texture(tex, p.xz * texels_per_meter).rgb;
	vec3 z = texture(tex, p.xy * texels_per_meter).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// Subtle per-position brightness variation so a single repeating texture
// doesn't read as plastic.
float position_hash(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec2 uv = v_world_pos.xz / bake_span + vec2(0.5);
	float surface = texture(height_map, uv).r;
	float depth = surface - v_world_pos.y;
	float t = smoothstep(band_center_depth - band_width * 0.5,
			band_center_depth + band_width * 0.5, depth);
	vec3 w = triplanar_weights(v_world_normal);
	vec3 ground = triplanar_sample(ground_tex, v_world_pos, w) * ground_tint;
	vec3 rock = triplanar_sample(rock_tex, v_world_pos, w) * rock_tint;
	float variation = 0.92 + 0.16 * position_hash(v_world_pos);
	ALBEDO = mix(ground, rock, t) * variation;
	ROUGHNESS = 1.0;
}
