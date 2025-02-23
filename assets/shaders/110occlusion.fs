#version 100

precision mediump float;

// raylib tex coord
varying vec2 fragTexCoord;

const float PI = 3.1415;
const float TAU = 2.0 * PI;


/// UNIFORMS
// scene texture
uniform sampler2D texture0;
// occlusion mask
uniform sampler2D occlusion;
// invisible scene
uniform sampler2D invisible_scene;

// TODO: 'fog of war' scene
// the scene that is 'not visible'
// uniform sampler2D fog_of_war_scene;

// the 'source' of vision.
// TODO: support multiple
uniform vec2 player_pos;
// dimension size
uniform vec2 size;

bool out_of_bounds(vec2 uv) {
	return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
}


// MAX_STEPS can be tuned for performance
#define THRESHOLD 0.02
#define MAX_STEPS 500
#define CREEP 1.0

// TODO the 'creep' macro is really trying to fix a fundamental problem that should be resolved in a different wave
// i.e we want to show the 'primary' occluding object similar to in 'real' life. Where we can see the front surface of an occlusion.
// However this creep is very innacurate in smaller resolution sizes. So we should really count the amount of occlusion while marching
// and only 'occlude' if it's 'behind' the occlusion, not including the occluder.
//
// and subsequently deprecate 'creep'

void main() {
	// convert player position to UV space.
	vec2 player_uv = player_pos / size;
	// we convert from 'raylib' position to 'opengl' position
	player_uv.y = 1.0 - player_uv.y;

	// calculate the normalized direction from the fragment to the player.
	vec2 direction = normalize(player_uv - fragTexCoord);

	// set up our ray starting at the fragment position.
	vec2 current_uv = fragTexCoord;
	float total_distance = length(player_uv - fragTexCoord);
	float step_size = total_distance / float(MAX_STEPS);

	bool occluded = false;

	// step along the ray toward the player.
	for (int i = 0; i < MAX_STEPS; i++) {
		current_uv += direction * step_size;

		if (out_of_bounds(current_uv)) {
			break;
		}

		if (length(player_uv - current_uv) < THRESHOLD) {
			break;
		}

		vec2 occlusion_sample_uv = current_uv + direction * (CREEP / size);
		vec4 occ_sample = texture2D(occlusion, occlusion_sample_uv);
		// if the occlusion texture is black, we hit a wall.
		if (occ_sample.rgb == vec3(0.0)) {
			occluded = true;
			break;
		}

	}

	if (occluded) gl_FragColor = texture2D(invisible_scene, fragTexCoord);
	else gl_FragColor = texture2D(texture0, fragTexCoord);
}
