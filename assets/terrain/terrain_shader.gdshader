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

// Procedural organic terrain variation parameters:
// Controls spatial frequency/density of organic patches (higher = smaller/denser patches, lower = larger sweeping patches).
uniform float noise_scale : hint_range(0.01, 2.0) = 0.35;
// Darkest brightness multiplier in noise valleys (e.g., 0.60 = 60% of base brightness for dark soil patches).
uniform float min_contrast : hint_range(0.0, 2.0) = 0.70;
// Brightest brightness multiplier in noise peaks (e.g., 0.90 = 90% of base brightness for light soil patches).
uniform float max_contrast : hint_range(0.0, 3.0) = 0.90;

// 3D Volumetric Strata Texture parameters (Option B2):
// Bakes TerrainStrata palette indices directly into a 3D volume texture (FORMAT_R8).
// Guaranteed 100% spatial lockstep between visuals and mined drops.
uniform bool volume_enabled = false;
uniform sampler3D strata_volume : filter_nearest;
uniform vec3 volume_origin = vec3(0.0);
uniform vec3 volume_size = vec3(256.0, 64.0, 256.0);
uniform vec3 ore_palette_tint[16];
uniform sampler2D ore_textures[16] : source_color;
uniform float ore_roughness = 0.9;
uniform float ore_metallic = 0.0;
uniform float ore_warp_scale = 0.8;
uniform float ore_warp_strength = 0.45;

// Procedural Ore Vein parameters (Option 1 fallback when volume_enabled is false):
uniform bool ore_enabled = false;
uniform sampler2D ore_tex : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
uniform vec3 ore_tint = vec3(0.15, 0.15, 0.15);
uniform float ore_noise_scale = 0.125;
uniform float ore_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float ore_min_depth = 0.0;
uniform float ore_max_depth = 100000.0;
uniform vec3 ore_seed_offset = vec3(0.0);

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

vec3 triplanar_sample_ore(int idx, vec3 p, vec3 w) {
	vec3 x = texture(ore_textures[idx], p.zy * texels_per_meter).rgb;
	vec3 y = texture(ore_textures[idx], p.xz * texels_per_meter).rgb;
	vec3 z = texture(ore_textures[idx], p.xy * texels_per_meter).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// 2D Hash function helper for procedural noise
float hash2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
// 2D Continuous Value Noise with smooth Hermite interpolation.
// Evaluates smooth, continuous organic patches across world space.
float organic_noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3D Hash and Value Noise for procedural 3D ore veins
float hash3d(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.1, 0.1));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float organic_noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = hash3d(i + vec3(0.0, 0.0, 0.0));
	float b = hash3d(i + vec3(1.0, 0.0, 0.0));
	float c = hash3d(i + vec3(0.0, 1.0, 0.0));
	float d = hash3d(i + vec3(1.0, 1.0, 0.0));
	float e = hash3d(i + vec3(0.0, 0.0, 1.0));
	float g = hash3d(i + vec3(1.0, 0.0, 1.0));
	float h = hash3d(i + vec3(0.0, 1.0, 1.0));
	float k = hash3d(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
		mix(mix(e, g, u.x), mix(h, k, u.x), u.y),
		u.z
	);
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
	// Sample continuous organic noise over XZ world coordinates
	float noise_val = organic_noise2d(v_world_pos.xz * noise_scale);
	float variation = mix(min_contrast, max_contrast, noise_val);
	vec3 base_color = mix(ground, rock, t) * variation;
	float mat_roughness = 1.0;
	float mat_metallic = 0.0;

	// Option B2: 3D Volumetric Strata Texture (100% spatial lockstep with TerrainStrata)
	bool is_ore = false;
	if (volume_enabled && volume_size.x > 0.0 && volume_size.y > 0.0 && volume_size.z > 0.0) {
		// Sample 10 cm inside the solid terrain face along -normal to match player interaction hit_in
		vec3 sample_pos = v_world_pos - v_world_normal * 0.10;
		// Continuous 3D domain warp to eliminate rigid 1m Cartesian voxel stair-stepping
		vec3 warp = vec3(
			organic_noise3d(sample_pos * ore_warp_scale),
			organic_noise3d(sample_pos * ore_warp_scale + vec3(17.3, 31.7, 53.1)),
			organic_noise3d(sample_pos * ore_warp_scale + vec3(71.9, 13.5, 97.3))
		) - vec3(0.5);
		vec3 warped_pos = sample_pos + warp * ore_warp_strength;
		vec3 uvw = (warped_pos - volume_origin) / volume_size;
		if (all(greaterThanEqual(uvw, vec3(0.0))) && all(lessThanEqual(uvw, vec3(1.0)))) {
			float val = texture(strata_volume, uvw).r;
			int palette_idx = int(round(val * 255.0));
			if (palette_idx > 0 && palette_idx < 16) {
				is_ore = true;
				vec3 tint = ore_palette_tint[palette_idx];
				if (dot(tint, tint) < 0.001) {
					tint = vec3(1.0);
				}
				vec3 ore_color = triplanar_sample_ore(palette_idx, v_world_pos, w) * tint;
				base_color = ore_color;
				mat_roughness = ore_roughness;
				mat_metallic = ore_metallic;
			}
		}
	}

	if (!is_ore) {
		base_color = mix(ground, rock, t) * variation;
	}

	// Option 1 fallback: 3D Procedural Noise (when 3D volume is not enabled)
	if (!is_ore && ore_enabled && depth >= ore_min_depth && depth <= ore_max_depth) {
		float ore_noise = organic_noise3d(v_world_pos * ore_noise_scale + ore_seed_offset);
		float depth_edge = 1.0;
		if (ore_min_depth > 0.0) {
			depth_edge = min(depth_edge, smoothstep(ore_min_depth, ore_min_depth + 1.0, depth));
		}
		if (ore_max_depth < 10000.0) {
			depth_edge = min(depth_edge, smoothstep(ore_max_depth, ore_max_depth - 1.0, depth));
		}
		float vein_factor = smoothstep(ore_threshold - 0.04, ore_threshold + 0.04, ore_noise) * depth_edge;
		if (vein_factor > 0.001) {
			vec3 ore_color = triplanar_sample(ore_tex, v_world_pos, w) * ore_tint;
			base_color = mix(base_color, ore_color, vein_factor);
		}
	}

	ALBEDO = base_color;
	ROUGHNESS = mat_roughness;
	METALLIC = mat_metallic;
}
