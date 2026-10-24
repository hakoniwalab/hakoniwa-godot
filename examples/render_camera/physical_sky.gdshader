// Godot PhysicalSkyMaterial's shader (MIT, Copyright (c) Godot Engine contributors),
// copied from godotengine/godot tag 4.6-stable, scene/resources/3d/sky_material.cpp
// (PhysicalSkyMaterial::_update_shader). Changes from that version, to recheck when
// Godot is updated:
//   1. sun_energy is multiplied by sun_energy_scale (the camera exposure taken out)
//   2. the radiance cubemap pass (AT_CUBEMAP_PASS) is multiplied by sun_energy_scale
//   3. the night sky texture and use_debanding options are left out
//   4. the sun disk: Godot's disk (light angular distance, through the same power curve
//      as the sky) is replaced by a physical one added after the curve (memo 027):
//      angular diameter 0.53 deg, luminance = sun illuminance / disk solid angle,
//      edge smoothed over one pixel so the summed disk keeps its energy; not in the
//      radiance cubemap (the sun already lights the scene as the directional light)
// Why (hakoniwa-scenario memo 024):
// with physical light units Godot passes the sun to sky shaders as lux times the
// camera's exposure normalization, and this shader raises it to a power
// (pow 1.5, then 1 / 2.4) before Godot multiplies the sky by the normalization again.
// The sky then changes as exposure^1.63 instead of exposure^1 (measured 3.09x for
// one stop). sun_energy_scale (set per camera: reference normalization / current
// normalization) takes the camera's exposure back out, so the sky has one luminance
// and only the camera decides how bright it looks.
// The radiance cubemap (ambient light and reflections) is also baked with the
// normalization and the scene applies it once more, so the cubemap pass is scaled
// back the same way (measured: the ambient part changed as exposure^2).

shader_type sky;

uniform float rayleigh : hint_range(0, 64) = 2.0;
uniform vec4 rayleigh_color : source_color = vec4(0.3, 0.405, 0.6, 1.0);
uniform float mie : hint_range(0, 1) = 0.005;
uniform float mie_eccentricity : hint_range(-1, 1) = 0.8;
uniform vec4 mie_color : source_color = vec4(0.69, 0.729, 0.812, 1.0);

uniform float turbidity : hint_range(0, 1000) = 10.0;
uniform float sun_disk_scale : hint_range(0, 360) = 1.0;
uniform vec4 ground_color : source_color = vec4(0.1, 0.07, 0.034, 1.0);
uniform float exposure : hint_range(0, 128) = 1.0;
uniform float sun_energy_scale = 1.0;
// Physical sun disk (change 4): its colour times luminance in cd/m2, divided by the
// sky's background intensity (Godot multiplies the sky output by it); half its
// angular diameter; and the angle of one pixel (to smooth the edge).
uniform vec3 sun_disk_radiance = vec3(0.0);
uniform float sun_disk_radius = 0.004625;
uniform float pixel_angle = 0.002;

const vec3 UP = vec3(0.0, 1.0, 0.0);

// Optical length at zenith for molecules.
const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;

float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

void sky() {
	if (LIGHT0_ENABLED) {
		float zenith_angle = clamp(dot(UP, normalize(LIGHT0_DIRECTION)), -1.0, 1.0);
		float sun_energy = max(0.0, 0.757 * zenith_angle) * LIGHT0_ENERGY * sun_energy_scale;
		float sun_fade = 1.0 - clamp(1.0 - exp(LIGHT0_DIRECTION.y), 0.0, 1.0);

		// Rayleigh coefficients.
		float rayleigh_coefficient = rayleigh - (1.0 * (1.0 - sun_fade));
		vec3 rayleigh_beta = rayleigh_coefficient * rayleigh_color.rgb * 0.0001;
		// mie coefficients from Preetham
		vec3 mie_beta = turbidity * mie * mie_color.rgb * 0.000434;

		// Optical length.
		float zenith = max(0.0, dot(UP, EYEDIR));
		float optical_mass = 1.0 / (zenith + 0.15 * pow(3.885 + 54.5 * zenith, -1.253));
		float rayleigh_scatter = rayleigh_zenith_size * optical_mass;
		float mie_scatter = mie_zenith_size * optical_mass;

		// Light extinction based on thickness of atmosphere.
		vec3 extinction = exp(-(rayleigh_beta * rayleigh_scatter + mie_beta * mie_scatter));

		// In scattering.
		float cos_theta = dot(EYEDIR, normalize(LIGHT0_DIRECTION));

		float rayleigh_phase = (3.0 / (16.0 * PI)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
		vec3 betaRTheta = rayleigh_beta * rayleigh_phase;

		float mie_phase = henyey_greenstein(cos_theta, mie_eccentricity);
		vec3 betaMTheta = mie_beta * mie_phase;

		vec3 Lin = pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * (1.0 - extinction), vec3(1.5));
		// Hack from https://github.com/mrdoob/three.js/blob/master/examples/jsm/objects/Sky.js
		Lin *= mix(vec3(1.0), pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * extinction, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));

		// Hack in the ground color.
		Lin *= mix(ground_color.rgb, vec3(1.0), smoothstep(-0.1, 0.1, dot(UP, EYEDIR)));

		vec3 color = Lin;
		COLOR = pow(color, vec3(1.0 / (1.2 + (1.2 * sun_fade))));
		COLOR *= exposure;
		if (AT_CUBEMAP_PASS) {
			COLOR *= sun_energy_scale;
		} else {
			float angle = acos(clamp(cos_theta, -1.0, 1.0));
			float coverage = clamp((sun_disk_radius - angle) / pixel_angle + 0.5, 0.0, 1.0);
			COLOR += coverage * sun_disk_radiance;
		}
	} else {
		COLOR = vec3(0.0);
	}
}
