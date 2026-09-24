shader_type spatial;
render_mode diffuse_lambert;

// Depth-banded smooth-terrain look (F11 shader rules, F14 fallback): the
// transvoxel mesher has no per-voxel visuals, so the ONE terrain material
// blends two band layers by depth below the PRISTINE surface, then overlays
// strata ores from a 3D volume texture. The height bake is written by
// SmoothGrid from the same TerrainGenDef math as TerrainStrata (F13 noise
// closed form / F10 heightmap wrap), so the visible bands line up with the
// mining strata bands. Authored blobs are identified by Decal markers (F14).
//
// PBR: every material contributes albedo, a normal map and a packed ORME map
// (Occlusion R, Roughness G, Metallic B) from three Texture2DArrays built by
// TerrainTextureArrays: layer 0 = surface band, layer 1 = deep band, layer
// (1 + palette index) = ore. A layer is chosen by array coordinate, never by
// indexing an array of samplers (Mesa GL rejects that, and it forces a
// waterfall loop on AMD). Normals and ORME are sampled for the band and for
// ONE ore layer per pixel, not for every blend tap, to bound the fetch count.
// Beyond detail_fade_end they are not sampled at all (flat normal, neutral ORM), which
// bounds far-field cost. Ore albedo is sampled once per DISTINCT layer among the
// boundary taps, not once per tap.
//
// textureGrad with derivatives taken once at the top of fragment(): the band
// and ore sampling sit inside non-uniform branches, where implicit
// derivatives are undefined and would corrupt mip selection.
//
// Triplanar weighting follows the standard zylann.voxel demo approach
// (assets/blocks/block_shader.gdshader uses the same world-hash variation
// trick); the normal blend is the whiteout method. Written from scratch for
// this project.

// R channel = pristine surface height in meters at world XZ
// (uv = xz / bake_span + 0.5, centered on the origin, repeats beyond).
uniform sampler2D height_map : repeat_enable, filter_linear, hint_default_black;

uniform sampler2DArray albedo_array : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2DArray normal_array : repeat_enable, filter_linear_mipmap;
uniform sampler2DArray orme_array : repeat_enable, filter_linear_mipmap;
// Per layer: triplanar texture repeats per meter, and an albedo tint (white
// for textured materials, the def's flat color for textureless ones).
uniform float layer_tiles[17];
uniform vec3 layer_tint[17];

// Depth in meters below the pristine surface where ground fades into rock,
// and the fade width. SmoothGrid pushes the surface material's max_depth.
uniform float band_center_depth = 3.0;
uniform float band_width = 2.0;
uniform float bake_span = 512.0;

// Look tuning: normal_strength scales bump depth; metallic_scale tames metallic
// ores, which read as black when the only reflection source is the sky.
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 1.0) = 0.5;
// Normals and ORME fade out between these view distances in meters (flat normal,
// neutral ORM beyond the end), which bounds far-field texture cost.
uniform float detail_fade_start = 80.0;
uniform float detail_fade_end = 160.0;

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
uniform float ore_warp_scale = 1.1;
uniform float ore_warp_strength = 0.7;
// Half-width of the soft boundary blend zone in meters. Offset taps at this
// distance from the warped position detect neighbouring materials and blend
// their colors; 0.5 = half a voxel cell (smooth but tight), 1.0 = full cell.
uniform float ore_blend_radius = 0.5;

// Procedural Ore Vein parameters (Option 1 fallback when volume_enabled is
// false). Albedo only, one sampler2D: see docs/architecture/tech-debt.md.
uniform bool ore_enabled = false;
uniform sampler2D ore_tex : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
uniform float ore_tex_tiles = 0.25;
uniform vec3 ore_tint = vec3(0.15, 0.15, 0.15);
uniform float ore_noise_scale = 0.125;
uniform float ore_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float ore_min_depth = 0.0;
uniform float ore_max_depth = 100000.0;
uniform vec3 ore_seed_offset = vec3(0.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;

struct LayerSample {
	vec3 albedo;
	// World-space normal.
	vec3 normal;
	// Occlusion, roughness, metallic.
	vec3 orm;
};

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Steep faces sample their side planes, flat tops sample XZ.
vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// Option 1 fallback only (implicit derivatives, single sampler2D).
vec3 fallback_triplanar_sample(sampler2D tex, vec3 p, vec3 w) {
	vec3 x = texture(tex, p.zy * ore_tex_tiles).rgb;
	vec3 y = texture(tex, p.xz * ore_tex_tiles).rgb;
	vec3 z = texture(tex, p.xy * ore_tex_tiles).rgb;
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

// Triplanar albedo of one layer, tinted.
vec3 sample_albedo(int layer, vec3 p, vec3 w, vec3 dpdx, vec3 dpdy) {
	float s = layer_tiles[layer];
	float l = float(layer);
	vec3 x = textureGrad(albedo_array, vec3(p.zy * s, l), dpdx.zy * s, dpdy.zy * s).rgb;
	vec3 y = textureGrad(albedo_array, vec3(p.xz * s, l), dpdx.xz * s, dpdy.xz * s).rgb;
	vec3 z = textureGrad(albedo_array, vec3(p.xy * s, l), dpdx.xy * s, dpdy.xy * s).rgb;
	return (x * w.x + y * w.y + z * w.z) * layer_tint[layer];
}

// Triplanar occlusion / roughness / metallic of one layer (ORME rgb).
vec3 sample_orm(int layer, vec3 p, vec3 w, vec3 dpdx, vec3 dpdy) {
	float s = layer_tiles[layer];
	float l = float(layer);
	vec3 x = textureGrad(orme_array, vec3(p.zy * s, l), dpdx.zy * s, dpdy.zy * s).rgb;
	vec3 y = textureGrad(orme_array, vec3(p.xz * s, l), dpdx.xz * s, dpdy.xz * s).rgb;
	vec3 z = textureGrad(orme_array, vec3(p.xy * s, l), dpdx.xy * s, dpdy.xy * s).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// Normals are imported as two-channel RGTC, so Z is rebuilt from XY.
// normal_strength scales XY before the rebuild (0 = flat, 1 = as authored).
vec3 decode_normal(vec2 encoded) {
	vec2 xy = (encoded * 2.0 - 1.0) * normal_strength;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Triplanar whiteout-blended world-space normal of one layer.
vec3 sample_world_normal(int layer, vec3 p, vec3 n, vec3 w, vec3 dpdx, vec3 dpdy) {
	float s = layer_tiles[layer];
	float l = float(layer);
	vec3 tx = decode_normal(textureGrad(normal_array, vec3(p.zy * s, l), dpdx.zy * s, dpdy.zy * s).rg);
	vec3 ty = decode_normal(textureGrad(normal_array, vec3(p.xz * s, l), dpdx.xz * s, dpdy.xz * s).rg);
	vec3 tz = decode_normal(textureGrad(normal_array, vec3(p.xy * s, l), dpdx.xy * s, dpdy.xy * s).rg);
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

// Normal + ORM only (albedo left zero): used for the ore layer, whose albedo
// is blended separately across the boundary taps. `detail` (1 near, 0 far)
// fades to a flat normal and neutral ORM and skips the fetches entirely at 0.
LayerSample sample_pbr(int layer, vec3 p, vec3 n, vec3 w, vec3 dpdx, vec3 dpdy, float detail) {
	LayerSample s = LayerSample(vec3(0.0), n, vec3(1.0, 1.0, 0.0));
	if (detail > 0.0) {
		s.normal = normalize(mix(n, sample_world_normal(layer, p, n, w, dpdx, dpdy), detail));
		s.orm = mix(vec3(1.0, 1.0, 0.0), sample_orm(layer, p, w, dpdx, dpdy), detail);
	}
	return s;
}

LayerSample sample_layer(int layer, vec3 p, vec3 n, vec3 w, vec3 dpdx, vec3 dpdy, float detail) {
	LayerSample s = sample_pbr(layer, p, n, w, dpdx, dpdy, detail);
	s.albedo = sample_albedo(layer, p, w, dpdx, dpdy);
	return s;
}

LayerSample mix_layers(LayerSample a, LayerSample b, float t) {
	LayerSample s;
	s.albedo = mix(a.albedo, b.albedo, t);
	s.normal = normalize(mix(a.normal, b.normal, t));
	s.orm = mix(a.orm, b.orm, t);
	return s;
}

// t is 0 or 1 everywhere except the transition zone, so most pixels sample ONE
// band layer instead of both.
LayerSample sample_band(float t, vec3 p, vec3 n, vec3 w, vec3 dpdx, vec3 dpdy, float detail) {
	if (t <= 0.001) {
		return sample_layer(0, p, n, w, dpdx, dpdy, detail);
	}
	if (t >= 0.999) {
		return sample_layer(1, p, n, w, dpdx, dpdy, detail);
	}
	return mix_layers(sample_layer(0, p, n, w, dpdx, dpdy, detail), sample_layer(1, p, n, w, dpdx, dpdy, detail), t);
}

void fragment() {
	vec3 p = v_world_pos;
	vec3 n = normalize(v_world_normal);
	// Derivatives taken here, in uniform control flow, for every textureGrad below.
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	vec3 w = triplanar_weights(n);
	// Fade factor for normal and ORME detail, computed in uniform control flow (1 near, 0 beyond detail_fade_end).
	float detail = 1.0 - smoothstep(detail_fade_start, detail_fade_end, length(VERTEX));

	vec2 uv = p.xz / bake_span + vec2(0.5);
	float surface = texture(height_map, uv).r;
	float depth = surface - p.y;
	float t = smoothstep(band_center_depth - band_width * 0.5,
			band_center_depth + band_width * 0.5, depth);
	float variation = mix(min_contrast, max_contrast, organic_noise2d(p.xz * noise_scale));

	// Ore first (3D strata volume): it decides whether the band sample is needed at all.
	float ore_fraction = 0.0;
	vec3 ore_albedo = vec3(0.0);
	int ore_layer = -1;
	if (volume_enabled && volume_size.x > 0.0 && volume_size.y > 0.0 && volume_size.z > 0.0) {
		// Sample 10 cm inside the solid terrain face along -normal to match player interaction hit_in
		vec3 sample_pos = p - n * 0.10;
		// Continuous 3D domain warp to eliminate rigid 1m Cartesian voxel stair-stepping
		vec3 warp = vec3(
			organic_noise3d(sample_pos * ore_warp_scale),
			organic_noise3d(sample_pos * ore_warp_scale + vec3(17.3, 31.7, 53.1)),
			organic_noise3d(sample_pos * ore_warp_scale + vec3(71.9, 13.5, 97.3))
		) - vec3(0.5);
		vec3 warped_pos = sample_pos + warp * ore_warp_strength;

		// Multi-tap boundary blend: 4 kernel positions (center with 2x weight + 3 axis offsets).
		// When near a material boundary, offset taps land in neighbouring regions and their
		// averaged colors produce a smooth blend zone of width ore_blend_radius.
		float br = ore_blend_radius;
		vec3 taps[4];
		taps[0] = warped_pos;
		taps[1] = warped_pos + vec3(br, 0.0, 0.0);
		taps[2] = warped_pos + vec3(0.0, br, 0.0);
		taps[3] = warped_pos + vec3(0.0, 0.0, br);
		// Weights: center gets 2, each offset gets 1 (total weight = 5).
		float tap_weights[4];
		tap_weights[0] = 2.0;
		tap_weights[1] = 1.0;
		tap_weights[2] = 1.0;
		tap_weights[3] = 1.0;

		// Distinct ore layers among the taps with their summed weights: a tap that lands on an
		// already-seen layer adds weight instead of costing another set of texture fetches.
		int ore_layers[4];
		float ore_layer_weights[4];
		int ore_count = 0;
		float accumulated_total_weight = 0.0;

		for (int i = 0; i < 4; i++) {
			vec3 tap_uvw = (taps[i] - volume_origin) / volume_size;
			float w_i = tap_weights[i];
			accumulated_total_weight += w_i;
			if (all(greaterThanEqual(tap_uvw, vec3(0.0))) && all(lessThanEqual(tap_uvw, vec3(1.0)))) {
				float val = texture(strata_volume, tap_uvw).r;
				int palette_idx = int(round(val * 255.0));
				if (palette_idx > 0 && palette_idx < 16) {
					int layer = palette_idx + 1;
					int slot = -1;
					for (int k = 0; k < ore_count; k++) {
						if (ore_layers[k] == layer) {
							slot = k;
						}
					}
					if (slot < 0) {
						slot = ore_count;
						ore_layers[slot] = layer;
						ore_layer_weights[slot] = 0.0;
						ore_count++;
					}
					ore_layer_weights[slot] += w_i;
				}
			}
		}

		// One albedo sample per distinct layer, weighted by the taps that landed on it.
		vec3 accumulated_ore = vec3(0.0);
		float accumulated_ore_weight = 0.0;
		float dominant_weight = 0.0;
		for (int k = 0; k < ore_count; k++) {
			accumulated_ore += sample_albedo(ore_layers[k], p, w, dpdx, dpdy) * ore_layer_weights[k];
			accumulated_ore_weight += ore_layer_weights[k];
			// The heaviest layer (the first on a tie) supplies the normal and ORM.
			if (ore_layer_weights[k] > dominant_weight) {
				dominant_weight = ore_layer_weights[k];
				ore_layer = ore_layers[k];
			}
		}

		if (accumulated_ore_weight > 0.0) {
			ore_albedo = accumulated_ore / accumulated_ore_weight;
			// Blend ore into terrain proportionally: full inside, gradual falloff at edges.
			ore_fraction = accumulated_ore_weight / accumulated_total_weight;
		}
	}

	// Band layers, skipped when the pixel is fully ore.
	LayerSample result = LayerSample(vec3(0.0), n, vec3(1.0, 1.0, 0.0));
	if (ore_fraction < 0.999) {
		result = sample_band(t, p, n, w, dpdx, dpdy, detail);
		result.albedo *= variation;
	} else {
		ore_fraction = 1.0;
	}
	if (ore_fraction > 0.0) {
		LayerSample ore_pbr = sample_pbr(ore_layer, p, n, w, dpdx, dpdy, detail);
		result.albedo = mix(result.albedo, ore_albedo, ore_fraction);
		result.normal = normalize(mix(result.normal, ore_pbr.normal, ore_fraction));
		result.orm = mix(result.orm, ore_pbr.orm, ore_fraction);
	}

	// Option 1 fallback: 3D Procedural Noise (when 3D volume is not enabled)
	if (ore_fraction <= 0.0 && ore_enabled && depth >= ore_min_depth && depth <= ore_max_depth) {
		float ore_noise = organic_noise3d(p * ore_noise_scale + ore_seed_offset);
		float depth_edge = 1.0;
		if (ore_min_depth > 0.0) {
			depth_edge = min(depth_edge, smoothstep(ore_min_depth, ore_min_depth + 1.0, depth));
		}
		if (ore_max_depth < 10000.0) {
			depth_edge = min(depth_edge, smoothstep(ore_max_depth, ore_max_depth - 1.0, depth));
		}
		float vein_factor = smoothstep(ore_threshold - 0.04, ore_threshold + 0.04, ore_noise) * depth_edge;
		if (vein_factor > 0.001) {
			vec3 ore_color = fallback_triplanar_sample(ore_tex, p, w) * ore_tint;
			result.albedo = mix(result.albedo, ore_color, vein_factor);
		}
	}

	ALBEDO = result.albedo;
	NORMAL = normalize((VIEW_MATRIX * vec4(result.normal, 0.0)).xyz);
	AO = result.orm.r;
	ROUGHNESS = result.orm.g;
	METALLIC = result.orm.b * metallic_scale;
}
