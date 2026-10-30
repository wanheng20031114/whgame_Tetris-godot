shader_type canvas_item;

// 主题切换：旧画面快照以圆形向外溶解，露出新主题
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.5, 0.5);
uniform float aspect = 1.7778;
uniform float edge = 0.04;

void fragment() {
	vec2 d = (UV - origin) * vec2(aspect, 1.0);
	float r = progress * (length(vec2(aspect, 1.0)) + edge);
	float a = smoothstep(r - edge, r, length(d));
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * a);
}
