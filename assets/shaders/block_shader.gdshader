shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_offset_strength : hint_range(0.0, 0.3) = 0.16;
uniform float color_variation : hint_range(0.0, 0.3) = 0.08;
uniform float rotation_strength : hint_range(0.0, 0.2) = 0.16;
varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 block_pos = floor(world_pos + 0.5);
	float r1 = hash(block_pos + vec3(0.0, 0.0, 0.0));
	float r2 = hash(block_pos + vec3(13.7, 5.3, 7.1));
	float r3 = hash(block_pos + vec3(3.1, 11.3, 2.7));
	float r4 = hash(block_pos + vec3(23.1, 7.7, 19.3));

	vec2 centered = UV - vec2(0.5);
	float angle = (r4 - 0.5) * rotation_strength;
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 rotated = vec2(ca * centered.x - sa * centered.y, sa * centered.x + ca * centered.y) + vec2(0.5);

	vec2 uv = rotated + vec2(r1, r2) * uv_offset_strength;
	float brightness = 1.0 + (r3 - 0.5) * color_variation * 2.0;

	ALBEDO = texture(albedo_tex, uv).rgb * brightness;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
