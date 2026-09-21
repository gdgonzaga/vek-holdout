shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.22, 0.58, 0.72, 0.72);
uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.42, 0.94);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float wave_frequency : hint_range(0.1, 10.0) = 2.5;
uniform float depth_distance : hint_range(0.1, 10.0) = 3.0;
// Shoreline: water dissolves over shore_fade_distance where it meets ground or
// blocks, and a foam band of foam_width hugs the contact line so the cube-edge
// steps read as a soft bank instead of a hard polygon edge.
uniform float shore_fade_distance : hint_range(0.01, 3.0) = 0.35;
uniform float foam_width : hint_range(0.0, 2.0) = 0.3;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.7;
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
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

	// View-space distance from this water fragment to whatever opaque surface is behind it.
	float gap = max(-world_depth_pos.z - (-VERTEX.z), 0.0);
	float water_depth = clamp(gap / max(0.01, depth_distance), 0.0, 1.0);

	vec3 water_rgb = mix(shallow_color.rgb, deep_color.rgb, water_depth);
	water_rgb += (wave_factor - 0.5) * 0.05;

	// Shore fade: 0 at contact, full water alpha once gap passes shore_fade_distance.
	float shore = smoothstep(0.0, max(0.01, shore_fade_distance), gap);
	// Foam: strongest at contact, gone at foam_width; the wave nudges its edge so it shimmers.
	float foam = (1.0 - smoothstep(0.0, max(0.01, foam_width), gap)) * foam_strength;
	foam *= mix(0.8, 1.0, wave_factor);

	ALBEDO = mix(water_rgb, foam_color.rgb, foam);
	// Foam keeps the contact line visible even where the water itself has faded out.
	ALPHA = max(mix(shallow_color.a, deep_color.a, water_depth) * shore, foam * foam_color.a);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
}
