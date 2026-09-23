class_name PunchFX
extends RefCounted

## EFEITOS 2D: faíscas, brasas, raios, estilhaços, poeira e confete.
##
## A simulação é do MOTOR, não do GDScript. Cada tipo de partícula tem um
## pequeno banco de emissores `CPUParticles2D` (C++, desenhados num lote
## só) com textura própria em alta resolução (`assets/fx`, gerada por
## `tools/gerar_fx.py`). Um pedido de 80 faíscas dispara 8 emissores de
## 10; nada é alocado depois do arranque e nenhum laço por partícula roda
## em script — era esse laço que derrubava o quadro depois de cada soco.
##
## Duas camadas: FRENTE (impacto, por cima da tela) e FUNDO (confete do
## ranking, por trás dos cartões, para a festa nunca cobrir a informação).
##
## As ondas de choque continuam desenhadas pelo `desenhar(tela)` de quem
## usa, com uma malha de anel: só os pixels do anel, um desenho cada.

enum Tipo { FAISCA, BRASA, CHUVA, RAIO, ESTILHACO, POEIRA, CONFETE }

## Por tipo: textura, quantas partículas por emissor, quantos emissores,
## vida (s), gravidade (px/s²), amortecimento, escala, aditivo, camada.
const RECEITAS := {
	Tipo.FAISCA: {"tex": "faisca", "lote": 10, "banco": 14, "vida": 0.85, "grav": 420.0,
		"amort": 520.0, "escala": [0.55, 1.10], "soma": true, "alinha": true},
	Tipo.BRASA: {"tex": "faisca", "lote": 12, "banco": 18, "vida": 1.45, "grav": 700.0,
		"amort": 260.0, "escala": [0.70, 1.35], "soma": true, "alinha": true},
	Tipo.CHUVA: {"tex": "faisca", "lote": 10, "banco": 8, "vida": 2.3, "grav": 560.0,
		"amort": 20.0, "escala": [0.60, 1.10], "soma": true, "alinha": true},
	Tipo.RAIO: {"tex": "raio", "lote": 4, "banco": 8, "vida": 1.2, "grav": 560.0,
		"amort": 380.0, "escala": [0.26, 0.42], "soma": false, "alinha": false},
	Tipo.ESTILHACO: {"tex": "estilhaco", "lote": 5, "banco": 4, "vida": 1.6, "grav": 1150.0,
		"amort": 60.0, "escala": [0.16, 0.30], "soma": false, "alinha": false},
	Tipo.POEIRA: {"tex": "fumaca", "lote": 4, "banco": 10, "vida": 1.5, "grav": -60.0,
		"amort": 180.0, "escala": [0.30, 0.65], "soma": false, "alinha": false},
	Tipo.CONFETE: {"tex": "confete", "lote": 14, "banco": 8, "vida": 3.4, "grav": 520.0,
		"amort": 150.0, "escala": [0.42, 0.72], "soma": false, "alinha": false},
}

var vigia: Desempenho = null

var _frente: Node2D = null
var _fundo: Node2D = null
var _bancos := {}          # Tipo -> Array[CPUParticles2D]
var _proximo := {}         # Tipo -> índice do próximo emissor
var _chuva_confete: CPUParticles2D = null
var _chuva_confete_ate := 0.0
var _brisas := {}          # nome -> CPUParticles2D
var _rampas := {}          # hash das cores -> Gradient
var _ondas: Array[Dictionary] = []
var _relogio := 0.0
var _aquecendo := 0

static var _texturas := {}


static func _textura(nome: String) -> Texture2D:
	if not _texturas.has(nome):
		_texturas[nome] = load("res://assets/fx/%s.png" % nome)
	return _texturas[nome]


## Cria as camadas e todos os emissores. Chamar uma vez, no `_ready` de
## quem vai exibir os efeitos.
func montar(pai: CanvasItem, z_frente := 1, z_fundo := -1) -> void:
	if _frente != null:
		return
	_frente = _camada(pai, "EfeitosFrente", z_frente)
	_fundo = _camada(pai, "EfeitosFundo", z_fundo)
	for tipo in RECEITAS:
		var banco: Array[CPUParticles2D] = []
		for i in range(int(RECEITAS[tipo]["banco"])):
			# O confete é só do ranking: mora no fundo, atrás dos cartões.
			banco.append(_emissor(tipo, _fundo if tipo == Tipo.CONFETE else _frente))
		_bancos[tipo] = banco
		_proximo[tipo] = 0
	_chuva_confete = _emissor(Tipo.CONFETE, _fundo)
	_chuva_confete.one_shot = false
	_chuva_confete.explosiveness = 0.0
	_chuva_confete.amount = 170
	_chuva_confete.lifetime = 4.6
	_chuva_confete.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_chuva_confete.emission_rect_extents = Vector2(560.0, 30.0)
	_chuva_confete.position = Vector2(540.0, -60.0)
	_chuva_confete.direction = Vector2(0.0, 1.0)
	_chuva_confete.spread = 18.0
	_chuva_confete.gravity = Vector2(0.0, 150.0)
	_chuva_confete.damping_min = 4.0
	_chuva_confete.damping_max = 12.0


static func _camada(pai: CanvasItem, nome: String, z: int) -> Node2D:
	var camada := Node2D.new()
	camada.name = nome
	camada.z_index = z
	pai.add_child(camada)
	return camada


func _emissor(tipo: Tipo, camada: Node2D) -> CPUParticles2D:
	var r: Dictionary = RECEITAS[tipo]
	var p := CPUParticles2D.new()
	p.emitting = false
	p.visible = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(r["lote"])
	p.lifetime = float(r["vida"])
	p.lifetime_randomness = 0.45
	# Coordenadas locais: gravidade e direção valem no espaço do jogo,
	# inclusive com a tela girada 90° na TV Box, e as partículas tremem
	# junto com a tela.
	p.local_coords = true
	p.texture = _textura(str(r["tex"]))
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	p.gravity = Vector2(0.0, float(r["grav"]))
	p.damping_min = float(r["amort"]) * 0.6
	p.damping_max = float(r["amort"])
	p.scale_amount_min = float(r["escala"][0])
	p.scale_amount_max = float(r["escala"][1])
	p.particle_flag_align_y = bool(r["alinha"])
	p.spread = 180.0
	var some := Gradient.new()
	some.set_color(0, Color(1, 1, 1, 1))
	some.set_color(1, Color(1, 1, 1, 0))
	some.add_point(0.7, Color(1, 1, 1, 0.85))
	p.color_ramp = some
	var mat := CanvasItemMaterial.new()
	if bool(r["soma"]):
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if tipo == Tipo.CONFETE:
		mat.particles_animation = true
		mat.particles_anim_h_frames = 8
		mat.particles_anim_v_frames = 1
		mat.particles_anim_loop = true
		p.anim_speed_min = 3.0
		p.anim_speed_max = 7.0
		p.anim_offset_max = 1.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -260.0
		p.angular_velocity_max = 260.0
		var papel := Gradient.new()
		papel.set_color(0, Color(1, 1, 1, 1))
		papel.set_color(1, Color(1, 1, 1, 0))
		papel.add_point(0.85, Color(1, 1, 1, 1))
		p.color_ramp = papel
	elif tipo in [Tipo.RAIO, Tipo.ESTILHACO]:
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -300.0
		p.angular_velocity_max = 300.0
	elif tipo == Tipo.POEIRA:
		var cresce := Curve.new()
		cresce.add_point(Vector2(0.0, 0.55))
		cresce.add_point(Vector2(1.0, 1.25))
		p.scale_amount_curve = cresce
	if tipo in [Tipo.FAISCA, Tipo.BRASA, Tipo.CHUVA]:
		var afina := Curve.new()
		afina.add_point(Vector2(0.0, 1.0))
		afina.add_point(Vector2(1.0, 0.35))
		p.scale_amount_curve = afina
	p.material = mat
	camada.add_child(p)
	return p


# ------------------------------------------------------------ controle
func limpar() -> void:
	_ondas.clear()
	for banco in _bancos.values():
		for p: CPUParticles2D in banco:
			p.emitting = false
			p.visible = false
	if _chuva_confete != null:
		_chuva_confete.emitting = false
		_chuva_confete.visible = false


func vivo() -> bool:
	return not _ondas.is_empty()


## A frente acompanha o tremor e o zoom da tela, como o resto do desenho.
func seguir(origem: Vector2, escala: Vector2) -> void:
	if _frente != null:
		_frente.position = origem
		_frente.scale = escala


func atualizar(delta: float) -> void:
	_relogio += delta
	for k in range(_ondas.size() - 1, -1, -1):
		var o := _ondas[k]
		o["tempo"] = float(o["tempo"]) + delta
		if float(o["tempo"]) >= float(o["duracao"]):
			_ondas.remove_at(k)
	if _chuva_confete != null and _chuva_confete.emitting and _relogio > _chuva_confete_ate:
		_chuva_confete.emitting = false
	if _aquecendo > 0:
		_aquecendo -= 1
		if _aquecendo == 0:
			limpar()
			_frente.modulate = Color.WHITE
			_fundo.modulate = Color.WHITE


## Dispara um lote de cada tipo quase invisível: compila o shader das
## partículas e sobe as texturas antes do primeiro soco.
func aquecer() -> void:
	if _frente == null:
		return
	_frente.modulate = Color(1, 1, 1, 0.004)
	_fundo.modulate = Color(1, 1, 1, 0.004)
	var meio := Vector2(540.0, 960.0)
	for tipo in RECEITAS:
		_disparar(tipo, meio, 1, Color.WHITE, 300.0)
	chuva_de_confete(1080.0, 10, [Color.WHITE])
	_aquecendo = 4


func desenhar(tela: CanvasItem) -> void:
	if _ondas.is_empty():
		return
	var anel := _malha_do_anel()
	for o in _ondas:
		var t: float = float(o["tempo"]) / float(o["duracao"])
		var raio: float = lerpf(float(o["raio_inicial"]), float(o["raio_final"]), ease(t, 0.35))
		var cor: Color = o["cor"]
		cor.a *= (1.0 - t) * (1.0 - t)
		tela.draw_mesh(anel, null, Transform2D(0.0, Vector2(raio, raio), 0.0, o["centro"]), cor)


## Anel de raio 1 feito de triângulos, com borda que some para dentro e
## para fora. Desenhado com escala, preenche só os pixels do anel — um
## quadrado com textura de anel preencheria a tela inteira a cada onda.
static var _anel: ArrayMesh = null

static func _malha_do_anel() -> ArrayMesh:
	if _anel != null:
		return _anel
	const LADOS := 96
	const RAIOS := [0.86, 0.955, 1.0]
	const ALFAS := [0.0, 1.0, 0.0]
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for i in range(LADOS):
		var dir := Vector2.from_angle(float(i) / float(LADOS) * TAU)
		for k in range(3):
			v.append(dir * float(RAIOS[k]))
			c.append(Color(1, 1, 1, float(ALFAS[k])))
	for i in range(LADOS):
		var a := i * 3
		var b := ((i + 1) % LADOS) * 3
		for k in range(2):
			idx.append_array([a + k, b + k, b + k + 1, a + k, b + k + 1, a + k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	_anel = ArrayMesh.new()
	_anel.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _anel


# ------------------------------------------------------------ disparo
func _quantos_lotes(tipo: Tipo, pedido: int) -> int:
	var n := pedido if vigia == null else vigia.quantas(pedido)
	var lote := int(RECEITAS[tipo]["lote"])
	return clampi(int(ceil(float(n) / float(lote))), 1, int(RECEITAS[tipo]["banco"]))


func _proximo_emissor(tipo: Tipo) -> CPUParticles2D:
	var banco: Array = _bancos[tipo]
	var i: int = _proximo[tipo]
	_proximo[tipo] = (i + 1) % banco.size()
	return banco[i]


func _rampa(cores: Array) -> Gradient:
	# Uma cor sorteada por partícula: degraus constantes, um por cor.
	var chave := hash(cores)
	if _rampas.has(chave):
		return _rampas[chave]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var n := maxi(cores.size(), 1)
	g.offsets = PackedFloat32Array([0.0])
	g.colors = PackedColorArray([cores[0] if not cores.is_empty() else Color.WHITE])
	for i in range(1, n):
		g.add_point(float(i) / float(n), cores[i])
	_rampas[chave] = g
	return g


## Configura e solta `lotes` emissores do tipo, no ponto. `cor` tinge; se
## `cores` vier, cada partícula sorteia uma delas.
func _disparar(
	tipo: Tipo, onde: Vector2, lotes: int, cor: Color, forca: float,
	cores: Array = [], direcao := Vector2.ZERO, abertura := 180.0, espalhar := 0.0
) -> void:
	if _frente == null:
		return
	for _i in range(lotes):
		var p := _proximo_emissor(tipo)
		p.position = onde
		p.color = cor
		p.color_initial_ramp = _rampa(cores) if not cores.is_empty() else null
		p.initial_velocity_min = forca * 0.30
		p.initial_velocity_max = forca
		p.direction = direcao if direcao != Vector2.ZERO else Vector2.RIGHT
		p.spread = abertura
		if espalhar > 0.0:
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = espalhar
		else:
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
		p.visible = true
		p.restart()


# --------------------------------------------------- a API dos efeitos
func onda(centro: Vector2, raio_inicial: float, raio_final: float, cor: Color, _espessura: float = 8.0, duracao: float = 0.7) -> void:
	_ondas.append({
		"centro": centro, "raio_inicial": raio_inicial, "raio_final": raio_final,
		"cor": cor, "duracao": maxf(0.05, duracao), "tempo": 0.0,
	})


func faiscas(centro: Vector2, quantidade: int, cor: Color, forca: float = 1000.0) -> void:
	_disparar(Tipo.FAISCA, centro, _quantos_lotes(Tipo.FAISCA, quantidade), cor, forca)


func explosao(centro: Vector2, quantidade: int, cores: Array, forca: float = 1100.0) -> void:
	_disparar(Tipo.BRASA, centro, _quantos_lotes(Tipo.BRASA, quantidade), Color.WHITE, forca, cores, Vector2.ZERO, 180.0, 40.0)


func raios(centro: Vector2, quantidade: int, cor: Color, forca: float = 780.0) -> void:
	_disparar(Tipo.RAIO, centro, _quantos_lotes(Tipo.RAIO, quantidade), cor, forca)


func estilhacos(centro: Vector2, quantidade: int, cor: Color) -> void:
	_disparar(Tipo.ESTILHACO, centro, _quantos_lotes(Tipo.ESTILHACO, quantidade), cor, 420.0, [], Vector2.UP, 55.0, 90.0)


func poeira(centro: Vector2, quantidade: int, cor: Color, alcance: float = 420.0) -> void:
	_disparar(Tipo.POEIRA, centro, _quantos_lotes(Tipo.POEIRA, quantidade), cor, alcance, [], Vector2.ZERO, 180.0, 40.0)


## Brasas caindo do teto, espalhadas pela largura da tela.
func chuva_de_brasas(largura: float, quantidade: int, cores: Array) -> void:
	if _frente == null:
		return
	for _i in range(_quantos_lotes(Tipo.CHUVA, quantidade)):
		var p := _proximo_emissor(Tipo.CHUVA)
		p.position = Vector2(largura * 0.5, -120.0)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(largura * 0.5, 120.0)
		p.color = Color.WHITE
		p.color_initial_ramp = _rampa(cores)
		p.direction = Vector2.DOWN
		p.spread = 8.0
		p.initial_velocity_min = 480.0
		p.initial_velocity_max = 900.0
		p.visible = true
		p.restart()


## Canhão de confete: sai do ponto para cima, abre e cai girando.
func confete(centro: Vector2, quantidade: int, cores: Array, forca: float = 900.0) -> void:
	_disparar(Tipo.CONFETE, centro, _quantos_lotes(Tipo.CONFETE, quantidade), Color.WHITE, forca * 1.25, cores, Vector2.UP, 24.0, 30.0)


## Chuva contínua de confete (por trás dos cartões). Cada chamada mantém
## a chuva ligada por mais um instante; parar de chamar é parar a chuva.
func chuva_de_confete(largura: float, _quantidade: int, cores: Array, intensidade := 1.0) -> void:
	if _chuva_confete == null:
		return
	_chuva_confete.position.x = largura * 0.5
	_chuva_confete.color_initial_ramp = _rampa(cores)
	var escala := clampf(intensidade, 0.35, 1.4)
	_chuva_confete.initial_velocity_min = 90.0 * escala
	_chuva_confete.initial_velocity_max = 220.0 * escala
	_chuva_confete_ate = _relogio + 0.45
	if not _chuva_confete.emitting:
		_chuva_confete.visible = true
		_chuva_confete.emitting = true


func fogos(centro: Vector2, cores: Array) -> void:
	var cor: Color = cores[randi() % cores.size()]
	onda(centro, 6.0, randf_range(120.0, 210.0), Color(cor, 0.55), 5.0, 0.55)
	faiscas(centro, 40, cor, 780.0)


## Poeira ambiente contínua (a respiração do cenário). Um emissor por
## nome, criado na primeira chamada; `ligada` liga e desliga.
func brisa(nome: String, area: Rect2, cor: Color, por_segundo := 3.0, ligada := true) -> void:
	if _fundo == null:
		return
	var p: CPUParticles2D = _brisas.get(nome)
	if p == null:
		p = _emissor(Tipo.POEIRA, _fundo)
		p.one_shot = false
		p.explosiveness = 0.0
		p.lifetime = 3.2
		p.amount = maxi(2, int(ceil(por_segundo * 3.2)))
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.direction = Vector2.UP
		p.spread = 35.0
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 70.0
		p.gravity = Vector2(0.0, -18.0)
		p.damping_min = 0.0
		p.damping_max = 6.0
		_brisas[nome] = p
	p.position = area.get_center()
	p.emission_rect_extents = area.size * 0.5
	p.color = cor
	if ligada and not p.emitting:
		p.visible = true
		p.emitting = true
	elif not ligada:
		p.emitting = false
