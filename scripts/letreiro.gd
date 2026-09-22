class_name Letreiro
extends Control

## O NOME DO JOGO, NUM NÓ SÓ PARA ELE — e o motivo é o shader.
##
## No Godot, material é propriedade do NÓ: não existe trocar de shader
## entre duas chamadas dentro do mesmo `_draw`. Como o resto da tela é
## desenhado à mão num único Control, pôr o brilho no nó principal
## aplicaria o efeito a tudo — fundo, cartões, placar. Então o nome sai
## do desenho geral e passa a morar aqui, sozinho, com o shader dele.

const SHADER := preload("res://shaders/brilho_letras.gdshader")
const PASSAGEM := 1.15
const DESCANSO := 3.10
const CICLO := PASSAGEM + DESCANSO
const DE := -0.22
const ATE := 1.22

var fonte: Font
var _linhas: Array = []
var _tempo := 0.0
var _material := ShaderMaterial.new()
var _inicio_x := -1.0
var _extensao_x := -1.0

func _ready() -> void:
	_material.shader = SHADER
	material = _material
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# O relógio vem de `main.gd`, em `avancar`. Um nó com brilho correndo
	# por cima das letras no seu próprio tempo é mais uma camada
	# chacoalhando por conta própria. Ver `Ritmo`.
	set_process(false)

## O PASSO VEM DE FORA, e é o mesmo do jogo inteiro.
func avancar(passo: float) -> void:
	_tempo += passo
	var fase := fmod(_tempo, CICLO)
	var posicao := DE - 0.5
	if fase < PASSAGEM:
		posicao = lerpf(DE, ATE, fase / PASSAGEM)
	_material.set_shader_parameter("posicao", posicao)
	# Uniformes atualizam o material sem reconstruir os comandos de texto.

## Recebe o que desenhar neste quadro. Cada entrada é
## {texto, y, tamanho, cor}. Chamado pelo desenho da tela: assim o nome
## continua obedecendo à mesma animação de entrada de antes, e este nó
## não precisa saber nada sobre estados do jogo.
func mostrar(linhas: Array, inicio_x: float, extensao_x: float) -> void:
	if _linhas == linhas and _inicio_x == inicio_x and _extensao_x == extensao_x:
		return
	_linhas = linhas
	_inicio_x = inicio_x
	_extensao_x = extensao_x
	_material.set_shader_parameter("inicio_x", inicio_x)
	_material.set_shader_parameter("extensao_x", extensao_x)
	queue_redraw()

func esconder() -> void:
	if not _linhas.is_empty():
		_linhas = []
		queue_redraw()

func _draw() -> void:
	if fonte == null or _linhas.is_empty():
		return
	for linha in _linhas:
		var texto: String = linha["texto"]
		var tamanho: int = int(linha["tamanho"])
		var cor: Color = linha["cor"]
		var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
		var pos := Vector2(float(linha["x"]) - medida.x * 0.5, float(linha["y"]))
		# As mesmas três passadas do letreiro de sempre: halo, contorno
		# grosso e a letra. O shader trata as três — e é por isso que ele
		# exige luminância além do alfa, para não acender o contorno.
		draw_string_outline(
			fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
			int(tamanho * 0.34), Color(cor, cor.a * 0.28)
		)
		draw_string_outline(
			fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
			maxi(6, int(tamanho * 0.17)), Color(Paleta.CONTORNO, cor.a)
		)
		draw_string(
			fonte, pos - Vector2(0.0, tamanho * 0.055), texto,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, Color(cor.lightened(0.42), cor.a)
		)
		draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)
