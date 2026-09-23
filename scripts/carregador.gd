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
const EXTENSOES := ["png", "jpg", "webp", "svg", "wav", "ogg", "mp3", "ttf", "otf", "tres", "res"]

## Mesma geometria do jogo: quadro lógico 1080x1920.
const TELA := Vector2(1080.0, 1920.0)
const FUNDO := Color("19060d")
const SELO_CENTRO := Vector2(540.0, 900.0)
const SELO_TAMANHO := 560.0

## Quadros e tempo mínimos com o jogo já montado por baixo, aquecendo.
const AQUECER_QUADROS := 45
const AQUECER_SEGUNDOS := 0.9
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
			var parte := minf(float(_quadros_aquecendo) / AQUECER_QUADROS, _fase_tempo / AQUECER_SEGUNDOS)
			_progresso = lerpf(0.9, 1.0, clampf(parte, 0.0, 1.0))
			if parte >= 1.0 and _mostrado > 0.995:
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
	# A barra corre atrás do progresso real, sem saltos.
	_mostrado = move_toward(_mostrado, _progresso, delta * maxf(0.35, (_progresso - _mostrado) * 5.0))
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
	add_child(_jogo)
	move_child(_camada, -1)
	_progresso = 0.9
	_mudar(Fase.AQUECENDO)


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
		t.draw_circle(SELO_CENTRO, r, Color(1.0, 0.1, 0.2, (0.020 + 0.010 * pulso) * (1.0 - float(i) / 6.0) * clampf(_relogio / 0.35, 0.0, 1.0)), true, -1.0, true)
	if _selo != null:
		var lado := SELO_TAMANHO
		t.draw_texture_rect(_selo, Rect2(SELO_CENTRO - Vector2(lado, lado) * 0.5, Vector2(lado, lado)), false)

	# Barra de progresso, fina e com cantos redondos.
	var aparece := clampf(_relogio / 0.35, 0.0, 1.0)
	var largura := 620.0
	var altura := 14.0
	var topo := SELO_CENTRO.y + SELO_TAMANHO * 0.5 + 150.0
	var caixa := Rect2(Vector2(540.0 - largura * 0.5, topo), Vector2(largura, altura))
	_capsula(caixa.grow(3.0), Color(1, 1, 1, 0.08 * aparece))
	_capsula(caixa, Color("2d0b15", aparece))
	var cheio := Rect2(caixa.position, Vector2(maxf(altura, largura * _mostrado), altura))
	_capsula(cheio, Color("ff1934", aparece), Color("ffdc27", aparece))
	# Reflexo correndo por dentro do trecho cheio.
	var brilho_x := fmod(_relogio * 420.0, cheio.size.x + 160.0) - 80.0
	if brilho_x > 0.0 and brilho_x < cheio.size.x:
		var bx := cheio.position.x + brilho_x
		t.draw_rect(Rect2(bx - 30.0, topo + 2.0, 60.0, altura - 4.0), Color(1, 1, 1, 0.22 * aparece))
	# Ponta acesa.
	t.draw_circle(Vector2(cheio.end.x - altura * 0.5, topo + altura * 0.5), altura * 1.1, Color(1.0, 0.86, 0.15, 0.18 * aparece), true, -1.0, true)

	var pct := "%d%%" % int(round(_mostrado * 100.0))
	t.draw_string(_fonte_numero, Vector2(caixa.position.x, topo + 74.0), pct, HORIZONTAL_ALIGNMENT_CENTER, largura, 40, Color("ffdc27", aparece))
	var pontos := ".".repeat(1 + int(_relogio * 2.5) % 3)
	t.draw_string(_fonte, Vector2(caixa.position.x, topo + 124.0), _texto_status() + pontos, HORIZONTAL_ALIGNMENT_CENTER, largura, 28, Color("ead1ca", 0.9 * aparece))


## Retângulo com as pontas totalmente redondas, borda lisa, com gradiente
## horizontal opcional.
func _capsula(r: Rect2, cor: Color, cor_fim: Color = Color(0, 0, 0, 0)) -> void:
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
