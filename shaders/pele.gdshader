// PELE DO BOXEADOR — feita para o renderizador Compatibility (TV Box).
//
// O material padrão deixava a pele com cara de plástico: uma cor só,
// brilho liso e a sombra cortando seco. Aqui:
//   • LUZ QUE ATRAVESSA: a luz "embrulha" o corpo e, na passagem para a
//     sombra, a pele puxa para o vermelho — é o que a pele de verdade faz
//     (a luz entra, espalha no sangue e sai do outro lado da borda);
//   • DOIS BRILHOS: um largo e macio (a pele) e um fino e forte (o suor),
//     quebrado pelos POROS para não virar verniz;
//   • RELEVO DOS MÚSCULOS (pele_relevo) e poros repetidos de perto;
//   • CONTRA-LUZ na silhueta, que descola o lutador do fundo;
//   • o DANO avermelha a pele aos poucos.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D pintura : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D relevo : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D poros : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tom : source_color = vec4(1.0);
uniform float relevo_forca = 1.0;
uniform float poros_forca = 0.10;
uniform float poros_escala = 110.0;
uniform float embrulho = 0.30;
uniform vec3 cor_por_dentro : source_color = vec3(0.85, 0.22, 0.12);
uniform float por_dentro = 0.40;
uniform float suor = 0.30;
uniform float aspereza = 0.46;
uniform float contraluz = 0.30;
uniform float dano = 0.0;

varying float v_poros;
// Cabelo e sobrancelhas (o escuro da pintura): sem brilho de pele.
varying float v_brilho;

void fragment() {
	vec3 cor = texture(pintura, UV).rgb;
	float l = dot(cor, vec3(0.30, 0.55, 0.15));
	v_brilho = smoothstep(0.10, 0.24, l);
	cor *= tom.rgb;
	cor = mix(cor, cor * vec3(1.08, 0.80, 0.76), clamp(dano, 0.0, 1.0) * 0.55);
	ALBEDO = cor;
	vec3 n1 = texture(relevo, UV).rgb * 2.0 - 1.0;
	vec3 n2 = texture(poros, UV * poros_escala).rgb * 2.0 - 1.0;
	n1.xy *= relevo_forca;
	n2.xy *= poros_forca;
	vec3 n = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	v_poros = clamp(0.5 + (n2.x + n2.y) * 4.0, 0.0, 1.0);
	ROUGHNESS = mix(0.85, aspereza, v_brilho);
	SPECULAR = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Luz embrulhada (o corpo não corta a sombra seco) ...
	float difusa = clamp((ndl + embrulho) / (1.0 + embrulho), 0.0, 1.0);
	// ... e a faixa de passagem para a sombra fica avermelhada.
	float faixa = clamp(1.0 - abs(ndl) * 2.2, 0.0, 1.0) * step(-0.45, ndl);
	vec3 espalhada = cor_por_dentro * faixa * por_dentro;
	DIFFUSE_LIGHT += (vec3(difusa) + espalhada * (1.0 - difusa)) * ATTENUATION * LIGHT_COLOR / PI;

	vec3 h = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, h), 0.0);
	float nl = max(ndl, 0.0);
	// Brilho largo da pele + brilho fino do suor, quebrado pelos poros.
	float largo = pow(ndh, 18.0) * 0.10;
	float fino = pow(ndh, 70.0) * suor * mix(0.7, 1.2, v_poros);
	float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	SPECULAR_LIGHT += (largo + fino) * fresnel * 4.0 * nl * v_brilho * ATTENUATION * LIGHT_COLOR;

	// Contra-luz: luz vindo de trás acende a borda do corpo.
	float borda = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	float atras = max(dot(-VIEW, LIGHT), 0.0) * 0.6 + 0.4;
	SPECULAR_LIGHT += v_brilho * borda * atras * contraluz * max(ndl + 0.3, 0.0) * ATTENUATION * LIGHT_COLOR * vec3(1.0, 0.85, 0.75) * 0.5;
}
