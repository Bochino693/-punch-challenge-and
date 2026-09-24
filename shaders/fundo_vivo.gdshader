shader_type canvas_item;
// O FUNDO DO GABINETE VIVO — tudo na placa de vídeo, nada no processador.
//   • respira: um zoom lento e uma deriva de poucos pixels;
//   • a luz corre pelos riscos, na mesma diagonal da arte do gabinete;
//   • de tempos em tempos um relâmpago acende os raios brancos.
// `forca` 1 na abertura; mais baixo durante a luta (o fundo não disputa
// atenção com a arena).
uniform float forca = 1.0;

void fragment() {
	float z = 1.02 + 0.016 * sin(TIME * 0.21);
	vec2 c = vec2(0.5, 0.47) + vec2(sin(TIME * 0.13), cos(TIME * 0.11)) * 0.007;
	vec2 uv = c + (UV - c) / z;
	vec3 base = texture(TEXTURE, uv).rgb;
	float lum = dot(base, vec3(0.3, 0.5, 0.2));
	vec2 p = UV * vec2(1.0, 1.78);
	float s1 = 0.5 + 0.5 * sin(dot(p, vec2(0.79, -0.62)) * 9.0 - TIME * 1.6);
	s1 *= s1; s1 *= s1; s1 *= s1;
	float s2 = 0.5 + 0.5 * sin(dot(p, vec2(0.62, 0.79)) * 5.0 + TIME * 0.9);
	s2 *= s2; s2 *= s2; s2 *= s2; s2 *= s2;
	float riscos = smoothstep(0.07, 0.32, lum);
	vec3 cor = base * (1.0 + (s1 * 1.5 + s2 * 0.7) * riscos * forca);
	float janela = floor(TIME * 0.45);
	float sorte = fract(sin(janela * 12.9898) * 43758.5453);
	float fase = fract(TIME * 0.45);
	float flash = step(0.6, sorte) * exp(-fase * 8.0) * (0.65 + 0.35 * sin(fase * 80.0));
	float branco = smoothstep(0.35, 0.75, min(base.r, min(base.g, base.b)) * 1.6);
	cor += vec3(0.55, 0.72, 1.0) * flash * (branco * 1.5 + 0.06) * forca;
	COLOR = vec4(cor, 1.0) * COLOR;
}
