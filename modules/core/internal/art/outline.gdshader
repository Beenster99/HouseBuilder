// Hidden-line edges for the architectural model look: a screen quad in front of the camera
// finds silhouettes (depth jumps) and creases (the surface turning) in the depth buffer and
// draws them as ink lines, so every mesh gets SketchUp-style outlines with no extra geometry.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 line_colour : source_color = vec4(0.08, 0.08, 0.09, 1.0);
// Line width in pixels at 1080 lines; scales with the window.
uniform float width = 1.2;
// A neighbour this much nearer or further (fraction of the distance) is another object.
uniform float depth_jump = 0.04;
// Normals differing by more than this (1 - cos) make a crease: about 35 degrees, so a smooth
// pipe or cushion faceted finer than that draws no line per facet.
uniform float crease = 0.18;
// Lines fade out between these distances, m.
uniform float fade_near = 150.0;
uniform float fade_far = 600.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Nothing drawn here: the sky.
bool is_sky(vec2 uv) {
	// Cleared depth: 0 with reversed depth, 1 without. Neither is reachable by a surface
	// under the other convention (it would be in front of the near plane), so test both.
	float d = texture(depth_tex, uv).r;
	return d <= 0.000001 || d >= 0.999999;
}

vec3 view_at(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 v = inv_proj * ndc;
	return v.xyz / v.w;
}

void fragment() {
	vec2 px = max(width * VIEWPORT_SIZE.y / 1080.0, 1.0) / VIEWPORT_SIZE;
	vec3 c = view_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 l = view_at(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 r = view_at(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 u = view_at(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	vec3 d = view_at(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float zc = -c.z;
	// Silhouettes: a neighbour much nearer than this pixel (draw on the near side only).
	float zn = min(min(-l.z, -r.z), min(-u.z, -d.z));
	float jump = (zc - zn) / max(zn, 0.01);
	// A flat surface seen at a grazing angle (the ground towards the horizon) also changes
	// depth fast from pixel to pixel, so a jump alone drew a solid black band below the
	// horizon. On a plane 1/depth changes evenly across the screen, so a true silhouette is
	// where 1/depth bends: compare each pixel with the mean of its two neighbours.
	float ic = 1.0 / max(zc, 0.001);
	float il = 1.0 / max(-l.z, 0.001);
	float ir = 1.0 / max(-r.z, 0.001);
	float iu = 1.0 / max(-u.z, 0.001);
	float id = 1.0 / max(-d.z, 0.001);
	float bend = max(abs(il + ir - 2.0 * ic) / max(max(il, ir), ic),
			abs(iu + id - 2.0 * ic) / max(max(iu, id), ic));
	// Creases: the surface's normal on one side of the pixel against the other side.
	vec3 n1 = normalize(cross(r - c, u - c));
	vec3 n2 = normalize(cross(l - c, d - c));
	vec3 n3 = normalize(cross(u - c, l - c));
	vec3 n4 = normalize(cross(d - c, r - c));
	float turn = max(1.0 - dot(n1, n2), 1.0 - dot(n3, n4));
	// Next to the sky there is no surface to turn: that is a silhouette or nothing.
	if (is_sky(SCREEN_UV - vec2(px.x, 0.0)) || is_sky(SCREEN_UV + vec2(px.x, 0.0))
			|| is_sky(SCREEN_UV + vec2(0.0, px.y)) || is_sky(SCREEN_UV - vec2(0.0, px.y))) {
		turn = 0.0;
	}
	float edge = max(step(depth_jump, jump) * step(depth_jump, bend), step(crease, turn) * step(zc, fade_far));
	float fade = 1.0 - smoothstep(fade_near, fade_far, min(zc, zn));
	// The far edge of the ground against the sky is not an edge of anything: no line along
	// the horizon. Things standing up against the sky keep their outline (they are nearer).
	if (is_sky(SCREEN_UV)) {
		fade *= 1.0 - smoothstep(fade_near * 0.5, fade_near * 1.5, zn);
	}
	ALBEDO = line_colour.rgb;
	ALPHA = edge * fade * line_colour.a;
}
