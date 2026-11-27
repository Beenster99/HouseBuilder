shader_type canvas_item;
// Drawing paper: a warm off-white with fibre grain, a faint drafting grid and a soft
// vignette. Put it on a full-screen ColorRect behind menus (BsxTheme.paper_backdrop()).
uniform vec4 paper : source_color = vec4(0.953, 0.937, 0.894, 1.0);
uniform vec4 grid : source_color = vec4(0.33, 0.47, 0.62, 0.10);
uniform float grid_px = 32.0;
uniform float grain = 0.022;
uniform float vignette = 0.06;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float fibre = noise(px * vec2(0.9, 0.12)) * 0.6 + noise(px * 0.35) * 0.4;
	vec3 col = paper.rgb * (1.0 - grain + grain * fibre * 2.0 - grain * hash(px) * 0.5);
	float lines = 0.0;
	if (grid.a > 0.0 && grid_px > 1.0) {
		vec2 g = abs(fract(px / grid_px + 0.5) - 0.5) * grid_px;
		float minor = 1.0 - smoothstep(0.0, 1.0, min(g.x, g.y));
		vec2 g5 = abs(fract(px / (grid_px * 5.0) + 0.5) - 0.5) * grid_px * 5.0;
		float major = 1.0 - smoothstep(0.0, 1.2, min(g5.x, g5.y));
		lines = grid.a * max(minor * 0.6, major);
	}
	vec2 d = UV - 0.5;
	col *= 1.0 - vignette * dot(d, d) * 2.0;
	// Opaque paper with the grid drawn on it; with paper alpha 0, the grid lines alone (to
	// lay over a picture).
	vec3 out_col = mix(col, grid.rgb, lines);
	float a = paper.a;
	if (paper.a < 0.01) {
		out_col = grid.rgb;
		a = lines;
	}
	COLOR = vec4(out_col, a);
}
