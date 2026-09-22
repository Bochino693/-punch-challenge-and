class_name Traco
extends RefCounted

## BORDA LISA NUM DESENHO QUE NÃO TEM ANTISSERRILHADO.
##
## O projeto roda no renderizador "GL Compatibility", que é o que garante
## a máquina ligar em qualquer PC de gabinete — inclusive nos que não têm
## Vulkan. O preço é que o Godot ignora o MSAA 2D nesse renderizador: ele
## avisa "2D MSAA is not yet supported for GLES3" e desenha tudo com a
## borda em degrau. Com o jogo inteiro desenhado à mão, em polígonos e
## faixas diagonais, o degrau aparece em cada aresta.
##
## O conserto é por chamada, não por configuração:
##
##   * círculo e retângulo têm `antialiased` na própria função do Godot,
##     e passar `true` já resolve;
##   * `draw_colored_polygon` NÃO tem — então a borda é desenhada por
##     cima, como um contorno de um pixel na mesma cor, que é onde o
##     antisserrilhado da linha entra e come o degrau.
##
## Um pixel é o número certo: mais que isso engorda a figura, menos que
## isso não cobre a escada inteira.
const BORDA := 1.0

## CHAVE DE MEDIÇÃO. Desligada, `poligono` vira `draw_colored_polygon`
## puro — é o que permite medir quanto custa o antisserrilhado sem
## desfazer o código todo. Nunca fica falsa numa build de salão.
static var suavizar := true

## ABAIXO DESTE TAMANHO, A BORDA LISA NÃO SE VÊ — E CUSTA.
##
## O contorno antisserrilhado dobra a geometria do polígono. Numa faixa
## diagonal que cruza a tela isso é barato e o ganho é enorme. Num
## confete de oito pixels voando a mil por hora, a escada mede meio pixel
## e ninguém a enxerga nunca — mas a conta é paga em todos os quinhentos
## confetes, em todos os quadros. É aí que a festa fica pesada.
##
## Doze pixels é o ponto em que a escada começa a aparecer numa forma
## parada. Abaixo disso, o polígono vai cru.
const MENOR_QUE_SUAVIZA := 12.0

## Polígono cheio com a aresta lisa.
static func poligono(ci: CanvasItem, pontos: PackedVector2Array, cor: Color) -> void:
	ci.draw_colored_polygon(pontos, cor)
	if suavizar and _vale_suavizar(pontos):
		contorno(ci, pontos, cor)

static func _vale_suavizar(pontos: PackedVector2Array) -> bool:
	if pontos.size() < 3:
		return false
	var menor := pontos[0]
	var maior := pontos[0]
	for ponto in pontos:
		menor = menor.min(ponto)
		maior = maior.max(ponto)
	var caixa := maior - menor
	return maxf(caixa.x, caixa.y) >= MENOR_QUE_SUAVIZA

## Só o contorno — para quem já desenhou o miolo de outro jeito.
static func contorno(ci: CanvasItem, pontos: PackedVector2Array, cor: Color, espessura := BORDA) -> void:
	if pontos.size() < 3:
		return
	var fecho := pontos.duplicate()
	fecho.append(pontos[0])
	ci.draw_polyline(fecho, cor, espessura, true)


## ======================================================================
## ARCOS — a conta que ninguém fazia, paga em todo quadro.
##
## Um `draw_arc` com 96 segmentos e `antialiased = true` não é uma
## chamada: é um polígono de 96 lados COM a geometria extra do
## antisserrilhado, montada de novo a cada quadro. No instante do soco o
## jogo desenhava sete desses só no túnel de luz, mais um por onda de
## choque, mais três no farol — e o número de segmentos era 96 tanto
## para um anel de 1300 pixels quanto para um de 90, em que 96 lados
## descrevem um círculo com precisão de menos de um terço de pixel.
##
## Medido no impacto: 249 chamadas de desenho e 1554 itens por quadro,
## contra 62 e 857 na tela de espera. É essa diferença que aparece como
## "trava quando gera a pontuação".
##
## Duas contas, as duas baratas:
##
##   1. SEGMENTOS PELO RAIO. Um segmento a cada ~20 pixels de
##      circunferência é o ponto em que o olho deixa de ver o polígono.
##      Um anel grande continua com os 96 de sempre; um pequeno passa a
##      custar um terço disso, com o mesmo desenho na tela.
##
##   2. ANTISSERRILHADO PELA FOLGA. Numa máquina que está dando conta,
##      liso. Numa que não está — e o TV box é essa —, a borda em degrau
##      de um anel que vive quatro décimos de segundo é invisível ao lado
##      da animação engasgada que ela custa.
##
## `qualidade` é o mesmo número do vigia de `Desempenho`, entregue uma
## vez por quadro em `main.gd`, como já acontece com o cenário, a moldura
## e as partículas.
static var qualidade := 1.0

## Abaixo desta folga o antisserrilhado dos arcos sai de cena.
const SUAVIZA_ACIMA_DE := 0.75

## Comprimento de corda buscado, em pixels.
const CORDA := 20.0

static func segmentos(raio: float) -> int:
	var ideal := int(TAU * maxf(raio, 1.0) / CORDA)
	return clampi(ideal, 12, 96)

## Um anel inteiro, com o custo proporcional ao tamanho dele.
static func arco(
	ci: CanvasItem, centro: Vector2, raio: float, cor: Color, espessura: float
) -> void:
	ci.draw_arc(
		centro, raio, 0.0, TAU, segmentos(raio), cor, espessura,
		qualidade >= SUAVIZA_ACIMA_DE
	)

## Um pedaço de anel. O número de segmentos acompanha o ÂNGULO, e não só
## o raio: meia volta com os segmentos de uma volta inteira é o dobro do
## necessário, e foi assim que a roda de "carregando" e o medidor do
## placar estavam desenhados.
static func setor(
	ci: CanvasItem, centro: Vector2, raio: float, de: float, ate: float,
	cor: Color, espessura: float
) -> void:
	var fatia := absf(ate - de) / TAU
	var passos := maxi(6, int(segmentos(raio) * fatia))
	ci.draw_arc(centro, raio, de, ate, passos, cor, espessura, qualidade >= SUAVIZA_ACIMA_DE)
