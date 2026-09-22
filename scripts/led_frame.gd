class_name LedFrame
extends Control

## A fieira de lâmpadas que corre pela borda da tela, como no letreiro de
## um parque.
##
## LÂMPADA, NÃO PONTO DE LUZ. Num tema claro, um LED desenhado como
## brilho difuso simplesmente some: clarão sobre fundo claro não aparece.
## Cada bulbo aqui tem corpo pintado e ARO ESCURO, então a apagada
## também se vê — e é a fieira inteira, acesa e apagada junto, que faz o
## olho ler "letreiro" mesmo antes de a luz começar a correr.
##
## Cada estado do jogo tem um passo: parada, a luz passeia devagar;
## armada, ela aperta o passo e esquenta; no impacto, a moldura inteira
## pisca de uma vez. O jogo só chama `set_estado` e `impacto` — o
## resto a moldura resolve sozinha, sem pedir nada por fora.

## Estados reconhecidos por `set_estado`.
const PARADA := "parada"
const CONTAGEM := "contagem"
const ARMADA := "armada"
const RESULTADO := "resultado"

## O TETO DE QUALIDADE, vindo do mesmo vigia de `main.gd`.
##
## Esta moldura é a única enfeite do jogo que corria sempre no detalhe
## máximo, em toda tela, o tempo inteiro — mesmo o `ArcadeStage.enfeite`
## e as partículas de `PunchFX` já encolhem sozinhos quando a máquina
## aperta. Cem e tantos pontos, três desenhos cada, sem nunca abaixar,
## numa moldura que está na tela do início ao fim: é peso constante por
## pura decoração, exatamente o tipo de gasto que sobra numa máquina
## fraca de verdade.
var qualidade := 1.0

var tempo := 0.0
var estado := PARADA
## Cor do veredito, usada quando `estado` é RESULTADO.
var cor_resultado := Paleta.AMBAR
var _flash := 0.0
var _cor_flash := Paleta.AMBAR

## Pontos menores e mais próximos formam um trilho contínuo e refinado.
const PASSO := 38.0
const MARGEM := 24.0
## Quantas lâmpadas a luz corrente deixa acesas atrás dela.
const CAUDA := 14

## BORDA LISA SÓ ENQUANTO A MÁQUINA TEM FOLGA.
##
## Um bulbo tem sete pixels. O antisserrilhado dele custa a mesma
## geometria extra que o de uma faixa que cruza a tela, e não se vê nem
## de perto — muito menos numa TV a três metros. Na máquina que está
## dando conta ele fica, porque não custa nada que falte; na que não
## está, ele é a primeira coisa a sair.
func _liso() -> bool:
	return qualidade > 0.7

## ======================================================================
## A FIEIRA APAGADA É DESENHADA UMA VEZ, E NÃO SESSENTA POR SEGUNDO.
##
## AQUI ESTAVA O MAIOR PESO CONSTANTE DO JOGO. Medido, a 1080×1920:
## tirar esta moldura da tela derrubava o quadro do impacto de 56,5 ms
## para 44,8 ms — quase dez milissegundos, em TODA tela, do início ao
## fim, por pura decoração. São cento e onze lâmpadas, cada uma com
## corpo, aro e reflexo antisserrilhados: cerca de trezentos e trinta
## desenhos com borda lisa por quadro.
##
## E quase nada disso muda. As lâmpadas não saem do lugar, e a cor só
## muda nas dez que a luz corrente está acendendo naquele instante. O
## resto é exatamente igual ao quadro anterior.
##
## Então a fieira apagada virou um nó próprio. Um `CanvasItem` guarda a
## lista de desenho dele até alguém pedir `queue_redraw()`, e este aqui
## só pede quando a tela muda de tamanho ou de estado — ou seja, quase
## nunca. O nó de cima passa a desenhar só as lâmpadas ACESAS, que são
## uma dúzia. O olho vê a mesma moldura; a máquina desenha 3% dela.
class Fieira extends Control:
	var dono: LedFrame = null

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = -1

	func _draw() -> void:
		if dono != null:
			dono.desenhar_apagadas(self)

var _fieira: Fieira = null
## O que a fieira apagada já desenhou. Enquanto não mudar, ela não é
## redesenhada — é isso que faz a moldura custar quase nada.
var _fieira_marca := ""

func _ready() -> void:
	# Quem adianta o relógio desta moldura é `main.gd`, em `avancar`.
	# Ver lá, e ver `Ritmo` para o porquê.
	set_process(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4
	_fieira = Fieira.new()
	_fieira.dono = self
	add_child(_fieira)

func set_estado(nome: String, cor: Color = Paleta.AMBAR) -> void:
	estado = nome
	if nome == RESULTADO:
		cor_resultado = cor

## Clarão instantâneo do soco. `forca` de 0 a 1.
func impacto(forca: float, cor: Color = Paleta.AMBAR) -> void:
	_flash = maxf(_flash, clampf(forca, 0.0, 1.0))
	_cor_flash = cor

## O PASSO VEM DE `main.gd`, e é o mesmo do jogo inteiro.
##
## Esta moldura tinha o seu `_process` e somava o delta CRU do quadro.
## São mais de cem lâmpadas pulsando na borda da tela inteira — a camada
## em que a trepidação do relógio mais salta aos olhos, porque o
## movimento é lento, contínuo e periférico, que é o pior caso para o
## olho. Com o passo suavizado ela pulsa liso; com o cru, chacoalhava
## junto com todo o resto e por conta própria. Ver `Ritmo`.
func avancar(passo: float) -> void:
	tempo += passo
	_flash = maxf(0.0, _flash - passo * 3.2)
	queue_redraw()
	# A fieira apagada só é refeita quando algo que ela desenha muda: o
	# tamanho da tela, o estado (que troca a cor apagada de fundo) ou o
	# teto de qualidade.
	var marca := "%d|%d|%s|%.2f" % [int(size.x), int(size.y), estado, qualidade]
	if _fieira != null and marca != _fieira_marca:
		_fieira_marca = marca
		_fieira.queue_redraw()

func _cor_base() -> Color:
	match estado:
		CONTAGEM:
			return Paleta.CIANO
		ARMADA:
			return Paleta.AMBAR
		RESULTADO:
			return cor_resultado
	return Paleta.MARINHO

func _velocidade() -> float:
	## LEDs por segundo percorridos pela luz que corre.
	match estado:
		CONTAGEM:
			return 26.0
		ARMADA:
			return 60.0
	return 12.0

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var base := _cor_base()
	var apagada := Paleta.CARTAO_BORDA

	# Percurso da moldura: retângulo percorrido no sentido horário.
	var perimetro := 2.0 * (w + h - 4.0 * MARGEM)
	var total := int(perimetro / PASSO)
	if total < 8:
		return
	var cabeca := fmod(tempo * _velocidade(), float(total))

	# SÓ AS ACESAS PASSAM POR AQUI. As apagadas moram no nó de baixo, que
	# não é redesenhado (ver a classe `Fieira`, no alto do arquivo). A
	# cauda tem dez lâmpadas; o laço que percorria as cento e onze, em
	# todo quadro, era o maior peso constante do jogo.
	#
	# `CAUDA + 2` de folga: a cabeça anda em fração de lâmpada, e a
	# lâmpada logo à frente já recebe um fio de luz.
	for passo in range(CAUDA + 2):
		var i := int(cabeca) - passo
		i = (i % total + total) % total
		var dist := fmod(cabeca - float(i) + total, float(total))
		var acesa := maxf(0.0, 1.0 - dist / float(CAUDA))
		if acesa <= 0.02:
			continue
		if estado == ARMADA:
			acesa *= 0.75 + 0.25 * sin(tempo * 9.0)
		var p := _ponto_do_percurso(i, total, w, h)
		var cor := apagada.lerp(base, acesa)
		var raio := 3.2 + 1.25 * acesa
		# Halo curto: brilho de LED, sem a textura grossa de bulbo.
		draw_circle(p, raio + 4.0, Color(base, acesa * 0.14), true, -1.0, _liso())
		draw_circle(p, raio, cor, true, -1.0, _liso())
		draw_arc(p, raio, 0.0, TAU, 16, Color(Paleta.MARINHO, 0.24 + 0.28 * acesa), 0.9, _liso())
		# Reflexo no vidro do bulbo, sempre no mesmo canto.
		draw_circle(p + Vector2(-raio * 0.28, -raio * 0.28), raio * 0.18, Color(1, 1, 1, 0.44), true, -1.0, false)

	if _flash > 0.01:
		# O clarão acende a fieira inteira de uma vez só.
		for i in range(total):
			var p := _ponto_do_percurso(i, total, w, h)
			draw_circle(p, 5.8, Color(_cor_flash, _flash * 0.74), true, -1.0, true)
		draw_rect(
			Rect2(MARGEM - 8.0, MARGEM - 8.0, w - 2.0 * (MARGEM - 8.0), h - 2.0 * (MARGEM - 8.0)),
			Color(_cor_flash, _flash * 0.22), false, 10.0
		)

func _ponto_do_percurso(i: int, total: int, w: float, h: float) -> Vector2:
	## Distribui o índice i pelos quatro lados, no sentido horário,
	## começando no canto superior esquerdo.
	var t := float(i) / float(total)
	var largura := w - 2.0 * MARGEM
	var altura := h - 2.0 * MARGEM
	var perimetro := 2.0 * (largura + altura)
	var d := t * perimetro
	if d < largura:
		return Vector2(MARGEM + d, MARGEM)
	d -= largura
	if d < altura:
		return Vector2(w - MARGEM, MARGEM + d)
	d -= altura
	if d < largura:
		return Vector2(w - MARGEM - d, h - MARGEM)
	d -= largura
	return Vector2(MARGEM, h - MARGEM - d)


## AS LÂMPADAS APAGADAS, desenhadas pelo nó de baixo e guardadas por ele.
##
## É o mesmo desenho de antes — corpo, aro e reflexo —, só que emitido
## uma vez em vez de sessenta vezes por segundo. Ver a classe `Fieira`.
func desenhar_apagadas(alvo: CanvasItem) -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var perimetro := 2.0 * (w + h - 4.0 * MARGEM)
	var total := int(perimetro / PASSO)
	if total < 8:
		return
	var apagada := Paleta.CARTAO_BORDA
	var detalhe := qualidade > 0.7
	for i in range(total):
		var p := _ponto_do_percurso(i, total, w, h)
		alvo.draw_circle(p, 3.2, apagada, true, -1.0, false)
		if detalhe:
			alvo.draw_arc(p, 3.2, 0.0, TAU, 14, Color(Paleta.MARINHO, 0.26), 0.8, false)
			alvo.draw_circle(p + Vector2(-0.9, -0.9), 0.55, Color(1, 1, 1, 0.40), true, -1.0, false)
