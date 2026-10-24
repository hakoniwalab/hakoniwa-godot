// Output pixel -> ray -> ideal pinhole source image (C4, hakoniwa-scenario memo 025).
// The per-pixel copy of hakoniwa_scenario/sensors/lens.py pixel_to_ray; lens.gd sets
// the parameters. Pixel centres at integers (OpenCV / ROS).

shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source_image : filter_linear, repeat_disable;
uniform vec2 output_size;
uniform vec4 intrinsics;  // fx, fy, cx, cy
uniform float skew;
uniform int projection;   // lens.gd PROJECTION_IDS
uniform bool use_brown;
uniform vec4 brown;       // k1, k2, p1, p2
uniform float brown_k3;
uniform vec4 kb;          // k0..k3
uniform float cutoff_angle;
uniform vec3 source;      // focal, cx, cy (pixels)
uniform vec2 source_size;
// Wide lenses: cube faces instead of one source (lens.py cube_faces, cube_position).
uniform bool cube;
uniform sampler2D face_front : filter_linear, repeat_disable;
uniform sampler2D face_right : filter_linear, repeat_disable;
uniform sampler2D face_left : filter_linear, repeat_disable;
uniform sampler2D face_up : filter_linear, repeat_disable;
uniform sampler2D face_down : filter_linear, repeat_disable;
uniform sampler2D face_back : filter_linear, repeat_disable;
uniform vec2 face;        // focal, centre (pixels)
uniform float face_size;

const int ITERATIONS = 20;
const float RESIDUAL_LIMIT = 1e-4;  // float32: looser than lens.py's 1e-6

vec2 distort_brown(vec2 p) {
	float r2 = dot(p, p);
	float radial = 1.0 + r2 * (brown.x + r2 * (brown.y + r2 * brown_k3));
	return vec2(p.x * radial + 2.0 * brown.z * p.x * p.y + brown.w * (r2 + 2.0 * p.x * p.x),
		p.y * radial + brown.z * (r2 + 2.0 * p.y * p.y) + 2.0 * brown.w * p.x * p.y);
}

float image_radius(float theta) {
	if (projection == 1) return theta;
	if (projection == 2) return 2.0 * sin(theta / 2.0);
	if (projection == 3) return 2.0 * tan(theta / 2.0);
	if (projection == 4) return sin(theta);
	float t2 = theta * theta;
	return theta * (1.0 + t2 * (kb.x + t2 * (kb.y + t2 * (kb.z + t2 * kb.w))));
}

// Angle from the axis for normalized image radius rho; negative when none.
float theta_of_radius(float rho) {
	if (projection == 1) return rho;
	if (projection == 2) return rho <= 2.0 ? 2.0 * asin(rho / 2.0) : -1.0;
	if (projection == 3) return 2.0 * atan(rho / 2.0);
	if (projection == 4) return rho <= 1.0 ? asin(rho) : -1.0;
	float theta = rho;
	for (int i = 0; i < ITERATIONS; i++) {
		float t2 = theta * theta;
		float f = theta * (1.0 + t2 * (kb.x + t2 * (kb.y + t2 * (kb.z + t2 * kb.w)))) - rho;
		float df = 1.0 + t2 * (3.0 * kb.x + t2 * (5.0 * kb.y + t2 * (7.0 * kb.z + t2 * 9.0 * kb.w)));
		if (df <= 0.0) return -1.0;
		theta -= f / df;
	}
	if (theta < 0.0 || theta >= PI || abs(image_radius(theta) - rho) > RESIDUAL_LIMIT) return -1.0;
	return theta;
}

// Unit ray for pixel (u, v); zero vector when none.
vec3 pixel_to_ray(vec2 pixel) {
	float yd = (pixel.y - intrinsics.w) / intrinsics.y;
	float xd = (pixel.x - intrinsics.z - skew * yd) / intrinsics.x;
	vec3 ray;
	if (projection == 0) {
		vec2 p = vec2(xd, yd);
		if (use_brown) {
			vec2 target = p;
			for (int i = 0; i < ITERATIONS; i++) {
				float r2 = dot(p, p);
				float icdist = 1.0 / (1.0 + r2 * (brown.x + r2 * (brown.y + r2 * brown_k3)));
				vec2 delta = vec2(2.0 * brown.z * p.x * p.y + brown.w * (r2 + 2.0 * p.x * p.x),
					brown.z * (r2 + 2.0 * p.y * p.y) + 2.0 * brown.w * p.x * p.y);
				p = (target - delta) * icdist;
			}
			if (length(distort_brown(p) - target) > RESIDUAL_LIMIT) return vec3(0.0);
		}
		ray = normalize(vec3(p, 1.0));
	} else {
		float rho = length(vec2(xd, yd));
		float theta = theta_of_radius(rho);
		if (theta < 0.0) return vec3(0.0);
		ray = rho > 0.0 ? vec3(sin(theta) * xd / rho, sin(theta) * yd / rho, cos(theta)) : vec3(0.0, 0.0, 1.0);
	}
	if (atan(length(ray.xy), ray.z) > cutoff_angle) return vec3(0.0);
	return ray;
}

// The ray in the face it falls on (lens.py CUBE_FACES): face-local optical x, y, z.
vec3 cube_sample(vec3 ray) {
	vec3 a = abs(ray);
	vec3 local;
	int id;
	if (a.z >= a.x && a.z >= a.y) {
		id = ray.z > 0.0 ? 0 : 5;
		local = ray.z > 0.0 ? ray : vec3(-ray.x, ray.y, -ray.z);
	} else if (a.x >= a.y) {
		id = ray.x > 0.0 ? 1 : 2;
		local = ray.x > 0.0 ? vec3(-ray.z, ray.y, ray.x) : vec3(ray.z, ray.y, -ray.x);
	} else {
		id = ray.y > 0.0 ? 4 : 3;
		local = ray.y > 0.0 ? vec3(ray.x, -ray.z, ray.y) : vec3(ray.x, ray.z, -ray.y);
	}
	vec2 uv = (face.x * local.xy / local.z + face.y + 0.5) / face_size;
	if (id == 0) return texture(face_front, uv).rgb;
	if (id == 1) return texture(face_right, uv).rgb;
	if (id == 2) return texture(face_left, uv).rgb;
	if (id == 3) return texture(face_up, uv).rgb;
	if (id == 4) return texture(face_down, uv).rgb;
	return texture(face_back, uv).rgb;
}

void fragment() {
	vec2 pixel = UV * output_size - 0.5;
	vec3 ray = pixel_to_ray(pixel);
	if (cube) {
		COLOR = vec4(dot(ray, ray) > 0.0 ? cube_sample(ray) : vec3(0.0), 1.0);
	} else if (ray.z <= 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 s = source.x * ray.xy / ray.z + source.yz;
		if (any(lessThan(s, vec2(-0.5))) || any(greaterThan(s, source_size - 0.5))) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		} else {
			COLOR = vec4(texture(source_image, (s + 0.5) / source_size).rgb, 1.0);
		}
	}
}
