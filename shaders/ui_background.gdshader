shader_type canvas_item;

// 主题全局色（UITheme 写入 RenderingServer 全局参数）
global uniform vec4 ui_bg;
global uniform vec4 ui_surface;
global uniform vec4 ui_accent;
global uniform vec4 ui_accent2;
global uniform vec4 ui_border;
global uniform vec4 ui_cyan;
global uniform vec4 ui_amber;
global uniform vec4 ui_pink;
global uniform vec4 ui_violet;
global uniform vec4 ui_ink;
global uniform float ui_dark;

uniform float aurora_strength = 1.0;
uniform float piece_strength = 1.0;
uniform float drift_speed = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 piece_color(int k) {
	if (k == 0) return ui_cyan.rgb;
	if (k == 1) return ui_amber.rgb;
	if (k == 2) return ui_violet.rgb;
	if (k == 3) return ui_accent.rgb;
	if (k == 4) return ui_pink.rgb;
	if (k == 5) return ui_cyan.rgb;
	return ui_amber.rgb;
}

int piece_mask(int k) {
	if (k == 0) return 0x0F00; // I
	if (k == 1) return 0x6600; // O
	if (k == 2) return 0x4E00; // T
	if (k == 3) return 0x6C00; // S
	if (k == 4) return 0xC600; // Z
	if (k == 5) return 0x8E00; // J
	return 0x2E00;             // L
}

// 一层漂浮的方块：输出颜色、填充覆盖度与描边覆盖度
void piece_layer(vec2 px, float cell, float speed, float seed, float density, out vec3 pc, out float inside, out float rim) {
	pc = vec3(0.0);
	inside = 0.0;
	rim = 0.0;
	const float SUPER = 7.0;
	vec2 g = px / cell;
	float col_id = floor(g.x / SUPER);
	g.y += TIME * speed * (0.55 + 0.9 * hash(vec2(col_id, seed)));
	vec2 sid = floor(g / SUPER);
	float h = hash(sid + seed * 17.0);
	if (h > density) {
		return;
	}
	vec2 local = g - sid * SUPER;           // 0..7
	vec2 off = floor(vec2(hash(sid + 3.1), hash(sid + 7.7)) * 2.0) + 1.0;
	vec2 c = floor(local - off);            // 方块 4x4 坐标
	vec2 f = fract(local);
	if (c.x < 0.0 || c.y < 0.0 || c.x > 3.0 || c.y > 3.0) {
		return;
	}
	int rot = int(hash(sid + 11.3) * 4.0);
	vec2 rc = c;
	if (rot == 1) rc = vec2(c.y, 3.0 - c.x);
	if (rot == 2) rc = vec2(3.0 - c.x, 3.0 - c.y);
	if (rot == 3) rc = vec2(3.0 - c.y, c.x);
	int kind = int(hash(sid + 5.9) * 7.0);
	int bit = 15 - (int(rc.y) * 4 + int(rc.x));
	if (((piece_mask(kind) >> bit) & 1) == 0) {
		return;
	}
	// 圆角方格：内部填充 + 描边
	vec2 q = abs(f - 0.5);
	float r = 0.12;
	float d = length(max(q - (0.5 - 0.06 - r), 0.0)) - r;
	float aa = 1.5 / cell;
	inside = 1.0 - smoothstep(-aa, aa, d);
	float edge_w = mix(1.8, 1.4, ui_dark) / cell;
	rim = inside * smoothstep(-edge_w - aa, -edge_w + aa, d);
	pc = piece_color(kind);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = FRAGCOORD.xy;
	vec2 uv = px / res;
	float aspect = res.x / res.y;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * 0.04 * drift_speed;
	bool dark = ui_dark > 0.5;

	// --- 底色 + 极淡的暖色场 ---
	vec3 col = ui_bg.rgb;
	vec2 c1 = vec2(aspect * (0.8 + 0.1 * sin(t * 2.1)), 0.2 + 0.08 * cos(t * 1.7));
	vec2 c2 = vec2(aspect * (0.15 + 0.08 * cos(t * 1.3)), 0.85 + 0.06 * sin(t * 2.3));
	float w1 = exp(-pow(distance(p, c1) / 0.6, 2.0));
	float w2 = exp(-pow(distance(p, c2) / 0.55, 2.0));
	float a_amt = (dark ? 0.10 : 0.12) * aurora_strength;
	col = mix(col, ui_accent.rgb, w1 * a_amt);
	col = mix(col, ui_accent2.rgb, w2 * a_amt * 0.8);

	// --- 圆角方格纹理（低对比）---
	float cell = 46.0;
	vec2 gp = px / cell + vec2(t * 2.0, -t * 1.2);
	vec2 gf = fract(gp) - 0.5;
	vec2 q = abs(gf) - (0.5 - 0.09 - 0.14);
	float d = length(max(q, 0.0)) - 0.14;
	float tile = 1.0 - smoothstep(-0.02, 0.02, d);
	vec3 tile_col = dark ? ui_surface.rgb : mix(ui_bg.rgb, ui_surface.rgb, 0.9);
	col = mix(col, tile_col, tile * (dark ? 0.22 : 0.3));

	// --- 漂浮的柔色方块剪影（无描边）---
	for (int i = 0; i < 2; i++) {
		vec3 pc;
		float inside;
		float rim;
		if (i == 0) {
			piece_layer(px, 22.0, 0.3 * drift_speed, 1.0, 0.18, pc, inside, rim);
		} else {
			piece_layer(px + vec2(311.0, 97.0), 36.0, 0.5 * drift_speed, 2.0, 0.13, pc, inside, rim);
		}
		float depth = i == 0 ? 0.6 : 1.0;
		col = mix(col, pc, inside * (dark ? 0.09 : 0.14) * depth * piece_strength);
	}

	// --- 柔和暗角 ---
	float vig = 1.0 - smoothstep(0.35, 1.35, distance(uv, vec2(0.5)));
	col = mix(col * (dark ? 0.82 : 0.96), col, vig);
	COLOR = vec4(col, 1.0);
}
