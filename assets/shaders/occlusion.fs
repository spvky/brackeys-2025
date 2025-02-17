#version 330

// raylib tex coord
in vec2 fragTexCoord;

const float PI = 3.1415;
const float TAU = 2.0 * PI;


/// UNIFORMS
// scene texture
uniform sampler2D texture0;
// occlusion mask
uniform sampler2D occlusion;

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
#define THRESHOLD 0.01
#define MAX_STEPS 1000

void main() {
	// convert player position to UV space.
	vec2 player_uv = player_pos / size;

	// calculate the normalized direction from the fragment to the player.
	vec2 direction = normalize(player_uv - fragTexCoord);

	// set up our ray starting at the fragment position.
	vec2 current_uv = fragTexCoord;
	float total_distance = length(player_uv - fragTexCoord);
	float step_size = total_distance / float(MAX_STEPS);

	bool occluded = false;

	if (total_distance < THRESHOLD) {
		gl_FragColor = vec4(1);
		return;
	}


	// step along the ray toward the player.
	for (int i = 0; i < MAX_STEPS; i++) {
		current_uv += direction * step_size;

		if (out_of_bounds(current_uv)) {
			break;
		}

		if (length(player_uv - current_uv) < THRESHOLD) {
			break;
		}

		vec4 occ_sample = texture(occlusion, current_uv);
		// if the occlusion texture is black, we hit a wall.
		if (occ_sample.rgb == vec3(0.0)) {
			occluded = true;
			break;
		}

	}

	if (occluded) gl_FragColor = vec4(0, 0, 0, 1);
	else gl_FragColor = texture(texture0, fragTexCoord);
}
