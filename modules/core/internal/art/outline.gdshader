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
	// Creases: the surface's normal on one side of the pixel against the other side.
	vec3 n1 = normalize(cross(r - c, u - c));
	vec3 n2 = normalize(cross(l - c, d - c));
	vec3 n3 = normalize(cross(u - c, l - c));
	vec3 n4 = normalize(cross(d - c, r - c));
	float turn = max(1.0 - dot(n1, n2), 1.0 - dot(n3, n4));
	float edge = max(step(depth_jump, jump), step(crease, turn) * step(zc, fade_far));
	float fade = 1.0 - smoothstep(fade_near, fade_far, min(zc, zn));
	ALBEDO = line_colour.rgb;
	ALPHA = edge * fade * line_colour.a;
}
