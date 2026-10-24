// The clear sky in physical units (hakoniwa-scenario memo 027; the formula is a copy of
// hakoniwa_scenario/environment/sky.py, set up by sky_model.gd and lighting.gd):
//   - luminance: CIE standard general sky (ISO 15469) type 12, scaled to the zenith
//     luminance (cd/m2) from the sun's altitude and the luminous turbidity
//   - colour: a table of the single-scattering chromaticity (luminance 1) by view
//     zenith angle and angle from the sun
//   - below the horizon: the ground, a grey Lambertian reflector lit by the sun and sky
//   - the sun's disk: angular diameter 0.53 deg, luminance = sun illuminance / disk solid
//     angle, edge smoothed over one pixel; not in the radiance cubemap (the sun already
//     lights the scene as the directional light)
// Nothing here depends on the light's energy as Godot passes it (that includes the
// camera's exposure); the sun's direction comes from a uniform, so the sky is the same
// whatever the light or the camera. Godot multiplies the output by the environment's
// background intensity and the camera's exposure normalization; luminance_scale is
// 1 / background intensity, so the output is the luminance in cd/m2.

shader_type sky;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // toward the sun, Godot world frame
uniform float zenith_luminance = 0.0;              // cd/m2
uniform float luminance_scale = 1.0;
uniform float cubemap_scale = 1.0;
// CIE gradation (a, b) and indicatrix (c, d, e) parameters.
uniform float gradation_a = -1.0;
uniform float gradation_b = -0.32;
uniform float indicatrix_c = 10.0;
uniform float indicatrix_d = -3.0;
uniform float indicatrix_e = 0.45;
uniform sampler2D colour_table : filter_linear, repeat_disable;
uniform vec3 ground_radiance = vec3(0.0);          // linear sRGB, cd/m2
uniform vec3 sun_disk_radiance = vec3(0.0);        // linear sRGB, cd/m2
uniform float sun_disk_radius = 0.004625;
uniform float pixel_angle = 0.002;

float gradation(float cos_zenith) {
	return 1.0 + gradation_a * exp(gradation_b / cos_zenith);
}

float indicatrix(float chi) {
	float c = cos(chi);
	return 1.0 + indicatrix_c * (exp(indicatrix_d * chi) - exp(indicatrix_d * PI / 2.0)) + indicatrix_e * c * c;
}

void sky() {
	vec3 toward_sun = normalize(sun_direction);
	float cos_scatter = clamp(dot(EYEDIR, toward_sun), -1.0, 1.0);
	float chi = acos(cos_scatter);
	vec3 radiance;
	if (EYEDIR.y > 0.0) {
		float sun_zenith = acos(clamp(toward_sun.y, -1.0, 1.0));
		float relative = indicatrix(chi) * gradation(EYEDIR.y) / (indicatrix(sun_zenith) * gradation(1.0));
		float zenith = acos(EYEDIR.y);
		vec2 uv = vec2(chi / PI, zenith / (PI / 2.0));
		radiance = texture(colour_table, uv).rgb * zenith_luminance * relative;
	} else {
		radiance = ground_radiance;
	}
	if (AT_CUBEMAP_PASS) {
		radiance *= cubemap_scale;
	} else {
		float coverage = clamp((sun_disk_radius - chi) / pixel_angle + 0.5, 0.0, 1.0);
		radiance += coverage * sun_disk_radiance;
	}
	COLOR = radiance * luminance_scale;
}
