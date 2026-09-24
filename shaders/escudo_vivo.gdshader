shader_type canvas_item;
// O ESCUDO SUPER BOXING com vida: uma faixa de brilho varre o logo de
// tempos em tempos (só onde há logo, pelo alfa) e o miolo pulsa de leve.
uniform float brilho = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float x = UV.x + UV.y * 0.45;
	float pos = fract(TIME * 0.24) * 2.6 - 0.7;
	float faixa = smoothstep(0.10, 0.0, abs(x - pos));
	float fio = smoothstep(0.018, 0.0, abs(x - pos - 0.05));
	float luz = (faixa * 0.55 + fio * 0.6) * brilho;
	c.rgb += vec3(1.0, 0.96, 0.86) * luz * c.a;
	c.rgb *= 1.0 + 0.06 * sin(TIME * 2.6);
	COLOR = c * COLOR;
}
