extends Control

## A Smart Pro 4K HD força toda Activity para 1920x1080. Pedir Portrait faz
## o firmware criar uma janela de compatibilidade pequena. Este adaptador deixa
## o Android em paisagem (tela cheia), renderiza o jogo numa tela real de
## 1080x1920 e gira o resultado 90 graus dentro do próprio APK.

const PORTRAIT_SIZE := Vector2i(1080, 1920)
const MAIN_SCENE := preload("res://scenes/main.tscn")

var _portrait_viewport: SubViewport
var _portrait_texture: TextureRect

func _ready() -> void:
	set_process_input(true)
	_portrait_viewport = SubViewport.new()
	_portrait_viewport.name = "JogoRetrato1080x1920"
	_portrait_viewport.size = PORTRAIT_SIZE
	_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_portrait_viewport.handle_input_locally = true
	_portrait_viewport.gui_disable_input = false
	add_child(_portrait_viewport)
	_portrait_viewport.add_child(MAIN_SCENE.instantiate())

	_portrait_texture = TextureRect.new()
	_portrait_texture.name = "QuadroVerticalGirado"
	_portrait_texture.texture = _portrait_viewport.get_texture()
	_portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_texture)
	_encaixar_na_tela()
	get_viewport().size_changed.connect(_encaixar_na_tela)

func _encaixar_na_tela() -> void:
	if _portrait_texture == null:
		return
	var janela := get_viewport_rect().size
	# O retângulo 1080x1920 vira 1920x1080 após -90 graus. Escala de
	# preenchimento cobre qualquer saída 16:9 sem barras ou deformação.
	var escala := maxf(janela.x / 1920.0, janela.y / 1080.0)
	_portrait_texture.size = Vector2(PORTRAIT_SIZE) * escala
	_portrait_texture.position = Vector2(0.0, janela.y)
	_portrait_texture.rotation = -PI * 0.5

func _input(event: InputEvent) -> void:
	if _portrait_viewport == null:
		return
	var encaminhado := event.duplicate()
	if encaminhado is InputEventMouse:
		var mouse := encaminhado as InputEventMouse
		var ponto_tela := mouse.position
		var escala := maxf(get_viewport_rect().size.x / 1920.0, get_viewport_rect().size.y / 1080.0)
		mouse.position = Vector2(
			PORTRAIT_SIZE.x - ponto_tela.y / escala,
			ponto_tela.x / escala
		)
		if mouse is InputEventMouseMotion:
			var movimento := mouse.relative
			mouse.relative = Vector2(-movimento.y, movimento.x) / escala
	elif encaminhado is InputEventScreenTouch:
		var toque := encaminhado as InputEventScreenTouch
		var ponto_tela := toque.position
		var escala := maxf(get_viewport_rect().size.x / 1920.0, get_viewport_rect().size.y / 1080.0)
		toque.position = Vector2(PORTRAIT_SIZE.x - ponto_tela.y / escala, ponto_tela.x / escala)
	elif encaminhado is InputEventScreenDrag:
		var arrasto := encaminhado as InputEventScreenDrag
		var ponto_tela := arrasto.position
		var movimento := arrasto.relative
		var escala := maxf(get_viewport_rect().size.x / 1920.0, get_viewport_rect().size.y / 1080.0)
		arrasto.position = Vector2(PORTRAIT_SIZE.x - ponto_tela.y / escala, ponto_tela.x / escala)
		arrasto.relative = Vector2(-movimento.y, movimento.x) / escala
	_portrait_viewport.push_input(encaminhado, true)
