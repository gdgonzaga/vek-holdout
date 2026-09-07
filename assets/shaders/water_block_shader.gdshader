shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.22, 0.58, 0.72, 0.72);
uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.42, 0.94);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float wave_frequency : hint_range(0.1, 10.0) = 2.5;
uniform float depth_distance : hint_range(0.1, 10.0) = 3.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float metallic : hint_range(0.0, 1.0) = 0.15;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Subtle animated wave coordinates based on world coordinates to align across block cells
	vec2 wave_uv = world_pos.xz * wave_frequency * 0.2 + vec2(TIME * wave_speed * 0.1, TIME * wave_speed * 0.07);
	float wave_factor = sin(wave_uv.x * 3.1415 + wave_uv.y * 2.718) * 0.5 + 0.5;

	// Depth fade against submerged objects (smooth terrain, solid blocks)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 world_depth_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	world_depth_pos.xyz /= world_depth_pos.w;

	float water_depth = clamp((-world_depth_pos.z - (-VERTEX.z)) / max(0.01, depth_distance), 0.0, 1.0);

	vec3 water_rgb = mix(shallow_color.rgb, deep_color.rgb, water_depth);
	water_rgb += (wave_factor - 0.5) * 0.05;

	ALBEDO = water_rgb;
	ALPHA = mix(shallow_color.a, deep_color.a, water_depth);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
}
