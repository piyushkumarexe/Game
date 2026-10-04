shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dirt_color : source_color = vec3(0.34, 0.19, 0.12);
uniform vec3 sun_color : source_color = vec3(0.57, 0.32, 0.18);
uniform vec3 stone_color : source_color = vec3(0.20, 0.22, 0.21);
uniform float texture_scale = 0.15;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float broad = value_noise(world_position.xz * texture_scale);
	float fine = value_noise(world_position.xz * texture_scale * 4.3);
	float steepness = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	vec3 ground = mix(dirt_color, sun_color, broad * 0.58 + fine * 0.15);
	ALBEDO = mix(ground, stone_color * (0.78 + broad * 0.3), smoothstep(0.30, 0.72, steepness));
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
}
