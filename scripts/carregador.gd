extends Node

## A PRIMEIRA TELA: DE PÉ, VIVA E MOSTRANDO O QUANTO FALTA.
##
## Antes o Android abria direto na cena do jogo. Tudo o que ela precisa —
## sons, lutador, arena, fontes, efeitos — era carregado DENTRO do
## `_ready`, na linha do jogo, e enquanto isso a TV mostrava o selo de
## abertura DEITADO (o Android ainda não tinha recebido o giro) e depois
## uma tela parada por vários segundos.
##
## Agora:
##   1. o selo de abertura (boot splash) já vem girado no arquivo, então
##      aparece em pé no monitor vertical desde o primeiro instante;
##   2. esta cena é minúscula: sobe em um piscar, desenha o mesmo selo no
##      mesmo lugar e uma barra de progresso lisa por baixo;
##   3. os recursos pesados carregam em THREADS (`load_threaded_request`),
##      com o progresso real na barra, sem congelar a animação;
##   4. o jogo nasce por baixo desta tela, aquece shaders e texturas
##      coberto, e só então a tela some num esmaecer.

const CENA_DO_JOGO := "res://scenes/main.tscn"
const PASTAS := ["res://assets/"]
const EXTENSOES := ["png", "jpg", "webp", "svg", "wav", "ogg", "mp3", "ttf", "otf", "tres", "res", "glb", "gltf", "fbx"]

## Mesma geometria do jogo: quadro lógico 1080x1920.
const TELA := Vector2(1080.0, 1920.0)
const FUNDO := Color("10091d")
const SELO_CENTRO := Vector2(540.0, 900.0)
const SELO_TAMANHO := 560.0

## Quadros e tempo MÍNIMOS com o jogo já montado por baixo, aquecendo. O
## fim de verdade é o jogo dizer que o ensaio acabou
## (`aquecimento_pronto`): numa TV Box ele leva o tempo que levar, e a
## barra acompanha etapa por etapa em vez de parar num número.
const AQUECER_QUADROS := 20
const AQUECER_SEGUNDOS := 0.6
## Teto de segurança: se por algum motivo o jogo não responder, a tela
## some mesmo assim (melhor jogo um pouco engasgado que tela parada).
const AQUECER_TETO_SEGUNDOS := 45.0

## A BARRA É UM SHADER. Faixas diagonais e um brilho varrendo o TRILHO
## INTEIRO (o fundo da barra, e não só a parte cheia), movidos pelo
## relógio da GPU: a barra continua viva mesmo quando o número demora a
## subir — barra parada é o que dá a impressão de travamento.
const SHADER_BARRA := """
shader_type canvas_item;
uniform float progresso = 0.0;
uniform vec2 tamanho = vec2(640.0, 20.0);
uniform vec4 trilho : source_color = vec4(0.11, 0.06, 0.25, 1.0);
uniform vec4 cor_a : source_color = vec4(1.0, 0.15, 0.63, 1.0);
uniform vec4 cor_b : source_color = vec4(1.0, 0.82, 0.08, 1.0);
void fragment() {
	vec2 p = UV * tamanho;
	float r = tamanho.y * 0.5;
	vec2 c = vec2(clamp(p.x, r, tamanho.x - r), r);
	float d = length(p - c) - r;
	float dentro = 1.0 - smoothstep(-1.0, 0.6, d);
	float listra = step(0.5, fract((p.x - p.y * 1.4) / 24.0 - TIME * 1.1));
	float varre = fract(TIME * 0.42) * 1.5 - 0.25;
	float brilho = exp(-pow((UV.x - varre) / 0.07, 2.0));
	vec3 fundo = trilho.rgb * (0.80 + 0.35 * listra) + vec3(0.55, 0.40, 1.0) * brilho * 0.55;
	float cheio = step(p.x, max(progresso * tamanho.x, tamanho.y));
	vec3 fill = mix(cor_a.rgb, cor_b.rgb, UV.x) * (0.88 + 0.18 * listra) + vec3(1.0) * brilho * 0.35;
	float borda = smoothstep(-2.5, -1.0, d) * (1.0 - smoothstep(-1.0, 0.6, d));
	vec3 cor = mix(fundo, fill, cheio) + vec3(0.6, 0.5, 1.0) * borda * 0.35;
	COLOR = vec4(cor, dentro * COLOR.a);
}
"""
const BARRA_LARGURA := 640.0
const BARRA_ALTURA := 26.0
var _barra: ColorRect = null
var _barra_mat: ShaderMaterial = null
const SUMIR_SEGUNDOS := 0.45

enum Fase { CARREGANDO, MONTANDO, AQUECENDO, SUMINDO, PRONTO }

var fase := Fase.CARREGANDO
var _pendentes: Array[String] = []
var _guardados: Array[Resource] = []
var _total := 0
var _progresso := 0.0      ## real, 0..1
var _mostrado := 0.0       ## o que a barra mostra, correndo atrás do real
var _relogio := 0.0
var _fase_tempo := 0.0
var _quadros_aquecendo := 0
var _jogo: Node = null

var _camada: CanvasLayer
var _tela: Control
var _selo: Texture2D
var _fonte: Font
var _fonte_numero: Font


func _ready() -> void:
	_configurar_janela()
	_selo = load("res://assets/branding/selo_lazer.png")
	_fonte = _carregar_fonte("res://assets/fonts/SairaCondensed-ExtraBold.ttf")
	_fonte_numero = _carregar_fonte("res://assets/fonts/Bungee-Regular.ttf")

	_camada = CanvasLayer.new()
	_camada.layer = 120
	add_child(_camada)
	_tela = Control.new()
	_tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tela.size = TELA
	if OS.get_name() == "Android":
		# O MESMO GIRO de `main.gd`: jogo (x, y) -> tela (y, 1080 - x).
		_tela.rotation = -PI * 0.5
		_tela.position = Vector2(0.0, 1080.0)
	_tela.draw.connect(_desenhar)
	_camada.add_child(_tela)
	_barra_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_BARRA
	_barra_mat.shader = sh
	_barra_mat.set_shader_parameter("tamanho", Vector2(BARRA_LARGURA, BARRA_ALTURA))
	_barra = ColorRect.new()
	_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra.material = _barra_mat
	_barra.color = Color(1, 1, 1, 1)
	_barra.size = Vector2(BARRA_LARGURA, BARRA_ALTURA)
	_barra.position = Vector2(540.0 - BARRA_LARGURA * 0.5, _topo_da_barra())
	_tela.add_child(_barra)

	_pedir(CENA_DO_JOGO)
	for pasta in PASTAS:
		_listar(pasta)
	_total = _pendentes.size()


func _configurar_janela() -> void:
	var janela := get_window()
	if OS.get_name() == "Android":
		janela.content_scale_size = Vector2i(1920, 1080)
	else:
		janela.content_scale_size = Vector2i(int(TELA.x), int(TELA.y))
	janela.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	janela.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	janela.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _carregar_fonte(caminho: String) -> Font:
	if ResourceLoader.exists(caminho):
		return load(caminho)
	return ThemeDB.fallback_font


## `list_directory` enxerga os recursos também dentro do APK, onde só
## existem os `.import`/`.remap` e não os arquivos originais.
func _listar(pasta: String) -> void:
	for nome in ResourceLoader.list_directory(pasta):
		if nome.ends_with("/"):
			_listar(pasta + nome)
		elif nome.get_extension().to_lower() in EXTENSOES:
			_pedir(pasta + nome)


func _pedir(caminho: String) -> void:
	if caminho in _pendentes:
		return
	if ResourceLoader.load_threaded_request(caminho, "", true) == OK:
		_pendentes.append(caminho)


func _process(delta: float) -> void:
	_relogio += delta
	_fase_tempo += delta
	match fase:
		Fase.CARREGANDO:
			_acompanhar_carga()
		Fase.MONTANDO:
			# Um quadro com o texto "MONTANDO" já na tela antes do
			# instanciar, que é o único passo que precisa da linha do jogo.
			if _fase_tempo > 0.05:
				_montar_jogo()
		Fase.AQUECENDO:
			_quadros_aquecendo += 1
			var minimo := minf(float(_quadros_aquecendo) / AQUECER_QUADROS, _fase_tempo / AQUECER_SEGUNDOS)
			var parte := minimo
			var pronto := minimo >= 1.0
			if _jogo != null and _jogo.has_method("aquecimento_progresso"):
				parte = minf(minimo, float(_jogo.aquecimento_progresso()))
				pronto = pronto and bool(_jogo.aquecimento_pronto())
			if _fase_tempo > AQUECER_TETO_SEGUNDOS:
				pronto = true
				parte = 1.0
			_progresso = lerpf(0.9, 1.0, clampf(parte, 0.0, 1.0))
			if pronto and _mostrado > 0.995:
				_mudar(Fase.SUMINDO)
				if _jogo != null and _jogo.has_method("soltar_entrada"):
					_jogo.soltar_entrada()
		Fase.SUMINDO:
			_camada_alfa(1.0 - clampf(_fase_tempo / SUMIR_SEGUNDOS, 0.0, 1.0))
			if _fase_tempo >= SUMIR_SEGUNDOS:
				_mudar(Fase.PRONTO)
				_camada.queue_free()
				set_process(false)
				return
	# A barra corre atrás do progresso real, sem saltos. O passo por quadro
	# tem teto: depois de um quadro demorado ela não pula, continua
	# andando — e o brilho do shader nunca para.
	_mostrado = move_toward(_mostrado, _progresso, minf(delta, 0.05) * maxf(0.35, (_progresso - _mostrado) * 5.0))
	if _barra_mat != null:
		_barra_mat.set_shader_parameter("progresso", _mostrado)
		_barra.modulate.a = clampf(_relogio / 0.35, 0.0, 1.0)
	_tela.queue_redraw()


func _acompanhar_carga() -> void:
	var soma := 0.0
	var faltam := 0
	var andamento := []
	for caminho in _pendentes:
		var estado := ResourceLoader.load_threaded_get_status(caminho, andamento)
		match estado:
			ResourceLoader.THREAD_LOAD_LOADED:
				soma += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				soma += float(andamento[0]) if not andamento.is_empty() else 0.0
				faltam += 1
			_:
				# Falhou: não trava a abertura por um arquivo ruim.
				soma += 1.0
	_progresso = 0.85 * (soma / float(maxi(1, _total)))
	if faltam == 0:
		for caminho in _pendentes:
			# Guardar a referência mantém o recurso no cache: o `load()` do
			# jogo encontra tudo pronto e não lê o disco de novo.
			var recurso := ResourceLoader.load_threaded_get(caminho)
			if recurso != null:
				_guardados.append(recurso)
		_mudar(Fase.MONTANDO)
		_progresso = 0.87


func _montar_jogo() -> void:
	var cena: PackedScene = null
	for r in _guardados:
		if r is PackedScene and r.resource_path == CENA_DO_JOGO:
			cena = r
	if cena == null:
		cena = load(CENA_DO_JOGO)
	_jogo = cena.instantiate()
	if "entrada_segurada" in _jogo:
		_jogo.entrada_segurada = true
	if OS.get_name() == "Android" or OS.has_environment("PUNCH_SUBVIEWPORT"):
		_tela_vertical().add_child(_jogo)
	else:
		add_child(_jogo)
	move_child(_camada, -1)
	_progresso = 0.9
	_mudar(Fase.AQUECENDO)


## A TELA EM PÉ, DESENHADA INTEIRA E SÓ DEPOIS GIRADA.
##
## Antes o jogo era desenhado JÁ GIRADO na janela deitada: cada letra era
## rasterizada de pé e colada de lado, e em tela com escala fracionária
## (TV Box em 720p, por exemplo) os pixels da letra entortavam — o
## "chuviscado". Agora o jogo inteiro é desenhado num SubViewport de
## 1080x1920, sem giro nenhum (as letras saem exatamente como no PC), e o
## que gira é a IMAGEM pronta, uma vez só, no contêiner. Pixel de letra
## nunca mais passa por rotação.
func _tela_vertical() -> SubViewport:
	var caixa := SubViewportContainer.new()
	caixa.name = "TelaVertical"
	caixa.stretch = false
	caixa.size = TELA
	caixa.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if OS.get_name() == "Android":
		# jogo (x, y) -> tela (y, 1080 - x), igual ao giro antigo.
		caixa.rotation = -PI * 0.5
		caixa.position = Vector2(0.0, 1080.0)
	var vp := SubViewport.new()
	vp.name = "Jogo"
	vp.size = Vector2i(int(TELA.x), int(TELA.y))
	vp.disable_3d = false
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	caixa.add_child(vp)
	add_child(caixa)
	return vp


func _topo_da_barra() -> float:
	return SELO_CENTRO.y + SELO_TAMANHO * 0.5 + 150.0


func _mudar(nova: Fase) -> void:
	fase = nova
	_fase_tempo = 0.0


func _camada_alfa(a: float) -> void:
	_tela.modulate.a = a


func _texto_status() -> String:
	match fase:
		Fase.CARREGANDO:
			if _progresso < 0.30:
				return "CARREGANDO SONS E IMAGENS"
			if _progresso < 0.65:
				return "CARREGANDO O LUTADOR"
			return "CARREGANDO A ARENA"
		Fase.MONTANDO:
			return "MONTANDO O JOGO"
		_:
			return "PREPARANDO OS EFEITOS"


# ------------------------------------------------------------- desenho
func _desenhar() -> void:
	var t := _tela
	t.draw_rect(Rect2(Vector2.ZERO, TELA), FUNDO)
	# Luz suave atrás do selo, respirando devagar.
	var pulso := 0.5 + 0.5 * sin(_relogio * 2.2)
	for i in range(6):
		var r := SELO_TAMANHO * (0.42 + float(i) * 0.09)
		t.draw_circle(SELO_CENTRO, r, Color(0.55, 0.2, 1.0, (0.020 + 0.010 * pulso) * (1.0 - float(i) / 6.0) * clampf(_relogio / 0.35, 0.0, 1.0)), true, -1.0, true)
	if _selo != null:
		var lado := SELO_TAMANHO
		t.draw_texture_rect(_selo, Rect2(SELO_CENTRO - Vector2(lado, lado) * 0.5, Vector2(lado, lado)), false)

	# A BARRA é o nó com shader (`_barra`); aqui só o número e o texto.
	var aparece := clampf(_relogio / 0.35, 0.0, 1.0)
	var largura := BARRA_LARGURA
	var topo := _topo_da_barra()
	var caixa := Rect2(Vector2(540.0 - largura * 0.5, topo), Vector2(largura, BARRA_ALTURA))
	var pct := "%d%%" % int(round(_mostrado * 100.0))
	t.draw_string(_fonte_numero, Vector2(caixa.position.x, topo + 74.0), pct, HORIZONTAL_ALIGNMENT_CENTER, largura, 40, Color("ffd014", aparece))
	var pontos := ".".repeat(1 + int(_relogio * 2.5) % 3)
	t.draw_string(_fonte, Vector2(caixa.position.x, topo + 124.0), _texto_status() + pontos, HORIZONTAL_ALIGNMENT_CENTER, largura, 28, Color("d9d1ff", 0.9 * aparece))


## Retângulo com as pontas totalmente redondas, borda lisa, com gradiente
## horizontal opcional.
func _capsula(r: Rect2, cor: Color, cor_fim: Color = Color(0, 0, 0, 0)) -> void:
	# Mais estreita que alta, as duas pontas redondas se cruzariam e o
	# polígono deixaria de ser válido: nesse caso vira um círculo.
	if r.size.x <= r.size.y + 0.5:
		_tela.draw_circle(r.get_center(), r.size.y * 0.5, cor.lerp(cor_fim, 0.5) if cor_fim.a > 0.0 else cor, true, -1.0, true)
		return
	var raio := r.size.y * 0.5
	var pontos := PackedVector2Array()
	var cores := PackedColorArray()
	var gradiente := cor_fim.a > 0.0
	const LADOS := 20
	for i in range(LADOS + 1):
		var a := PI * 0.5 + PI * float(i) / LADOS
		pontos.append(Vector2(r.position.x + raio, r.position.y + raio) + Vector2.from_angle(a) * raio)
	for i in range(LADOS + 1):
		var a := -PI * 0.5 + PI * float(i) / LADOS
		pontos.append(Vector2(r.end.x - raio, r.position.y + raio) + Vector2.from_angle(a) * raio)
	for p in pontos:
		var k := clampf((p.x - r.position.x) / maxf(1.0, r.size.x), 0.0, 1.0)
		cores.append(cor.lerp(cor_fim, k) if gradiente else cor)
	_tela.draw_polygon(pontos, cores)
	var fecho := pontos.duplicate()
	fecho.append(pontos[0])
	var cores_fecho := cores.duplicate()
	cores_fecho.append(cores[0])
	_tela.draw_polyline_colors(fecho, cores_fecho, 1.0, true)
