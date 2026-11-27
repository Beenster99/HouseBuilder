shader_type canvas_item;
// A copy of modules/ui/api/shaders/pencil_sketch.gdshader for the boot splash (Core draws without UI).
// Turns a picture into a pencil drawing on paper: graphite outlines from its edges,
// cross-hatching for its shadows, the rest left as paper. For the splash picture behind
// the main menu. `fade` blends the drawing out to plain paper towards the left.
uniform vec4 paper : source_color = vec4(0.953, 0.937, 0.894, 1.0);
uniform vec4 graphite : source_color = vec4(0.17, 0.18, 0.2, 1.0);
uniform float edge_strength = 3.2;
uniform float hatch_px = 6.0;
uniform float strength = 1.0;
uniform vec2 fade = vec2(0.30, 0.55);

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float hatch(vec2 px, float angle, float gap) {
	float c = cos(angle);
	float s = sin(angle);
	float d = (px.x * c + px.y * s) / gap;
	// A slightly broken line, as a pencil skips over paper grain.
	float dist = abs(fract(d) - 0.5) * gap;  // pixels from the line's centre
	float line = 1.0 - smoothstep(0.35, 1.1, dist);
	float along = (px.y * c - px.x * s) / 34.0;
	float gap_here = step(0.12, hash(vec2(floor(d), floor(along + hash(vec2(floor(d), 3.0))))));
	return line * gap_here * (0.75 + 0.25 * hash(vec2(floor(d), 7.0)));
}

void fragment() {
	vec2 t = TEXTURE_PIXEL_SIZE * 1.5;
	float tl = lum(texture(TEXTURE, UV + vec2(-t.x, -t.y)).rgb);
	float tc = lum(texture(TEXTURE, UV + vec2(0.0, -t.y)).rgb);
	float tr = lum(texture(TEXTURE, UV + vec2(t.x, -t.y)).rgb);
	float ml = lum(texture(TEXTURE, UV + vec2(-t.x, 0.0)).rgb);
	float mr = lum(texture(TEXTURE, UV + vec2(t.x, 0.0)).rgb);
	float bl = lum(texture(TEXTURE, UV + vec2(-t.x, t.y)).rgb);
	float bc = lum(texture(TEXTURE, UV + vec2(0.0, t.y)).rgb);
	float br = lum(texture(TEXTURE, UV + vec2(t.x, t.y)).rgb);
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	float edge = clamp(length(vec2(gx, gy)) * edge_strength - 0.12, 0.0, 1.0);
	float l = lum(texture(TEXTURE, UV).rgb);
	vec2 px = FRAGCOORD.xy;
	float shade = 0.0;
	shade = max(shade, hatch(px, 0.785, hatch_px) * (1.0 - smoothstep(0.5, 0.7, l)) * 0.4);
	shade = max(shade, hatch(px, -0.785, hatch_px) * (1.0 - smoothstep(0.28, 0.45, l)) * 0.45);
	shade = max(shade, hatch(px, 0.3, hatch_px * 1.3) * (1.0 - smoothstep(0.1, 0.22, l)) * 0.5);
	float ink = max(edge * 0.9, shade);
	float keep = smoothstep(fade.x, fade.y, UV.x) * strength;
	vec3 col = mix(paper.rgb, graphite.rgb, ink * keep);
	COLOR = vec4(col, 1.0);
}
