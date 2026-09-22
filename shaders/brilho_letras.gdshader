shader_type canvas_item;
render_mode blend_mix, unshaded;

// Reflexo recortado pela própria letra, sem desenhar faixas no fundo.
uniform float inicio_x = 0.0;
uniform float extensao_x = 1080.0;
uniform float posicao = -0.5;
uniform float largura = 0.085;
uniform float inclinacao = 0.28;
uniform float forca = 1.0;
uniform vec3 nucleo : source_color = vec3(1.0, 1.0, 1.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float corpo = base.a * smoothstep(0.22, 0.55, max(max(base.r, base.g), base.b));
	float u = (local.x - inicio_x + local.y * inclinacao) / max(extensao_x, 1.0);
	float d = abs(u - posicao);
	float halo = 1.0 - smoothstep(largura * 0.30, largura, d);
	float centro = 1.0 - smoothstep(0.0, largura * 0.30, d);
	float brilho = (halo * 0.55 + centro * 0.45) * forca * corpo;
	float vizinhanca = 1.0 - smoothstep(largura, largura * 3.2, d);
	float escurece = clamp(vizinhanca - halo, 0.0, 1.0) * corpo;
	vec3 cor = base.rgb * mix(1.0, 0.82, escurece);
	cor = mix(cor, nucleo, clamp(brilho * 0.9, 0.0, 1.0));
	cor += nucleo * brilho * 0.30;
	COLOR = vec4(cor, base.a);
}
