class_name ArenaQuadro
extends RefCounted

## A ARENA PENDURADA NA PAREDE, COMO UM QUADRO.
##
## Foi assim que o pedido veio, e a palavra é exata: o mundo 3D não
## invade a tela toda nem fica flutuando solto no meio dela — ele mora
## dentro de uma MOLDURA, no lugar que o fundo do jogo já reservava para
## si, e o resto da interface (placar, cartões, frases) continua em volta
## como sempre esteve.
##
## POR QUE A MOLDURA IMPORTA TANTO. Uma imagem 3D colada crua num fundo
## 2D desenhado à mão lê como erro de montagem: dois desenhos diferentes
## brigando. Com moldura, a diferença vira INTENÇÃO — é uma janela, e
## janelas mostram outro lugar mesmo. É o mesmo truque de um telão no
## fundo do palco.
##
## AS BARRAS LATERAIS FICARAM, E MUDARAM DE ASSUNTO. Elas já existiam na
## versão original, medindo a pontuação do soco; aqui medem o DANO do
## adversário, que é a mesma leitura de longe (coluna cheia contra coluna
## pela metade) contando uma história melhor: a rodada tem dois socos, e
## agora os dois se somam em cima de alguém.
##
## As medidas são constantes públicas porque três lugares dependem delas
## — o desenho, o `SubViewport` (que precisa da proporção certa para a
## imagem não esticar) e os testes.

## A moldura inteira, borda incluída. O QUADRO OCUPA A LARGURA TODA: o
## lutador e o ringue são o espetáculo, e as colunas laterais de dano
## saíram para dar lugar a eles (a vida agora é a barra de cima).
const MOLDURA := Rect2(28.0, 290.0, 1024.0, 1040.0)
## O buraco da moldura: é aqui que a imagem da arena é desenhada.
const TELA := Rect2(50.0, 312.0, 980.0, 996.0)
## A BARRA DE VIDA do adversário, acima do quadro, como num jogo de luta.
const VIDA := Rect2(60.0, 196.0, 960.0, 54.0)
## As duas colunas de dano, uma de cada lado da moldura.
const BARRA_E := Rect2(80.0, 508.0, 48.0, 770.0)
const BARRA_D := Rect2(952.0, 508.0, 48.0, 770.0)
## A plaqueta do placar, montada a cavaleiro na borda de baixo.
const PLACA := Rect2(268.0, 1244.0, 544.0, 170.0)
## Quantos degraus tem cada coluna.
const DEGRAUS := 20

const ESCURO := Color("1a0710")
const MADEIRA := Color("3d1220")
const OURO := Color("ffdc27")
const OURO_ESC := Color("8a6a10")

## O fundo do buraco, desenhado ANTES da imagem: sem câmera 3D (o GLB
## faltando, a janela desligada) o quadro continua sendo um quadro escuro
## e não um retângulo transparente com o cenário aparecendo no meio.
static func fundo(alvo: CanvasItem) -> void:
	alvo.draw_rect(TELA, ESCURO)

## A imagem do mundo 3D. `textura` é a do `SubViewport`.
static func imagem(alvo: CanvasItem, textura: Texture2D, alpha := 1.0) -> void:
	if textura == null:
		return
	alvo.draw_texture_rect(textura, TELA, false, Color(1, 1, 1, alpha))

## A MOLDURA. Quatro barras e não um retângulo vazado, porque um
## retângulo com contorno grosso pinta o miolo inteiro por baixo da
## imagem — desperdício de preenchimento numa máquina que já é o gargalo.
##
## `pulso` (0 a 1) acende o ouro: é o golpe fazendo a moldura tremer
## junto, como um telão que estremece com o baque.
static func moldura(alvo: CanvasItem, cor: Color, pulso := 0.0) -> void:
	var m := MOLDURA
	var t := TELA
	var brilho := clampf(pulso, 0.0, 1.0)
	var madeira := MADEIRA.lerp(cor, brilho * 0.55)
	# as quatro barras da moldura
	alvo.draw_rect(Rect2(m.position.x, m.position.y, m.size.x, t.position.y - m.position.y), madeira)
	alvo.draw_rect(Rect2(m.position.x, t.end.y, m.size.x, m.end.y - t.end.y), madeira)
	alvo.draw_rect(Rect2(m.position.x, t.position.y, t.position.x - m.position.x, t.size.y), madeira)
	alvo.draw_rect(Rect2(t.end.x, t.position.y, m.end.x - t.end.x, t.size.y), madeira)
	# o fio de ouro por fora e o rebaixo por dentro: são os dois que dão
	# espessura à moldura. Sem o de dentro ela parece um adesivo.
	alvo.draw_rect(m, Color(OURO, 0.85 + brilho * 0.15), false, 5.0)
	alvo.draw_rect(m.grow(-12.0), Color(OURO_ESC, 0.55 + brilho * 0.45), false, 2.0)
	alvo.draw_rect(t.grow(5.0), ESCURO, false, 10.0)
	alvo.draw_rect(t.grow(1.0), Color(OURO, 0.55 + brilho * 0.45), false, 3.0)
	# os quatro rebites: é o detalhe que diz "objeto pendurado" e não
	# "retângulo desenhado".
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var p := Vector2(lerpf(m.position.x + 18.0, m.end.x - 18.0, sx),
				lerpf(m.position.y + 23.0, m.end.y - 20.0, sy))
			alvo.draw_circle(p, 7.0, Color(OURO, 0.9))
			alvo.draw_circle(p, 3.0, ESCURO)

## AS DUAS COLUNAS DE DANO.
##
## Enchem de baixo para cima e mudam de cor no caminho — âmbar enquanto
## ele aguenta, vermelho quando está por um fio. A cor é o que faz a
## coluna ser lida sem contar degrau: o olho vê "ficou vermelho" antes de
## conseguir avaliar altura nenhuma.
##
## `pisca` faz o degrau da vez piscar, e só ele: uma coluna inteira
## piscando é alarme, e alarme é o que a tela NÃO quer dizer aqui — ela
## quer dizer progresso.
static func barras(alvo: CanvasItem, dano: float, tempo: float) -> void:
	var d := clampf(dano, 0.0, 1.0)
	var cor := Paleta.AMBAR.lerp(Paleta.VERMELHO, clampf((d - 0.35) / 0.55, 0.0, 1.0))
	var pisca := 0.55 + 0.45 * sin(tempo * 7.0)
	for rect: Rect2 in [BARRA_E, BARRA_D]:
		alvo.draw_rect(rect.grow(4.0), Color(ESCURO, 0.75))
		var passo := rect.size.y / float(DEGRAUS)
		for i in range(DEGRAUS):
			var fatia := float(i) / float(DEGRAUS)
			var caixa := Rect2(
				rect.position.x, rect.end.y - float(i + 1) * passo + 5.0,
				rect.size.x, passo - 10.0
			)
			if fatia + 1.0 / float(DEGRAUS) <= d:
				alvo.draw_rect(caixa, cor)
				alvo.draw_rect(caixa.grow(3.0), Color(cor, 0.16))
			elif fatia < d:
				# o degrau em que o dano parou: é ele que pisca
				alvo.draw_rect(caixa, Color(cor, pisca))
			else:
				alvo.draw_rect(caixa, Color("3a141d"))

## A BARRA DE VIDA — a leitura de jogo de luta, de longe.
##
## Barra INCLINADA, como nos jogos de luta: um paralelogramo com degradê
## feito por cor de vértice (quatro pontos, custo nenhum para a GPU),
## brilho de vidro na metade de cima e o rastro do golpe atrás.
##
## `vida` é o que sobrou (1 = inteiro); `fantasma` é a vida de um instante
## atrás, que desce devagar e deixa à mostra o pedaço que o soco acabou de
## arrancar. É esse rastro que faz o golpe "doer" na tela.
const INCLINA := 26.0

static func _faixa(alvo: CanvasItem, x0: float, x1: float, y0: float, y1: float, c0: Color, c1: Color) -> void:
	if x1 - x0 < 1.0:
		return
	var h := y1 - y0
	var d := INCLINA * h / VIDA.size.y
	alvo.draw_polygon(
		PackedVector2Array([Vector2(x0 + d, y0), Vector2(x1 + d, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([c0, c1, c1, c0])
	)

static func vida(alvo: CanvasItem, fonte: Font, vida: float, fantasma: float, tempo: float, rotulo: String) -> void:
	var r := VIDA
	var v := clampf(vida, 0.0, 1.0)
	var f := clampf(maxf(fantasma, v), 0.0, 1.0)
	var x0 := r.position.x
	var larg := r.size.x - INCLINA
	var y0 := r.position.y
	var y1 := r.end.y
	# moldura: sombra, aro de ouro e trilho escuro
	_faixa(alvo, x0 - 10.0, x0 + larg + 10.0, y0 - 7.0, y1 + 7.0, Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55))
	_faixa(alvo, x0 - 6.0, x0 + larg + 6.0, y0 - 4.0, y1 + 4.0, OURO_ESC, OURO)
	_faixa(alvo, x0, x0 + larg, y0, y1, Color("12040a"), Color("2a0b14"))
	# o rastro do golpe: vermelho vivo que clareia para o branco
	if f > v:
		_faixa(alvo, x0 + larg * v, x0 + larg * f, y0, y1, Color("ff3b3b"), Color(1, 1, 1, 0.9))
	# a vida: degradê do tom escuro para o claro da mesma cor
	var cor := Paleta.VERDE.lerp(Paleta.AMBAR, clampf((1.0 - v) / 0.5, 0.0, 1.0))
	cor = cor.lerp(Paleta.VERMELHO, clampf((0.5 - v) / 0.35, 0.0, 1.0))
	if v < 0.25:
		cor = cor.lerp(Color.WHITE, 0.30 * (0.5 + 0.5 * sin(tempo * 12.0)))
	_faixa(alvo, x0, x0 + larg * v, y0, y1, cor.darkened(0.35), cor.lightened(0.15))
	# vidro: faixa clara na metade de cima e um reflexo correndo
	_faixa(alvo, x0, x0 + larg * v, y0, y0 + r.size.y * 0.42, Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.10))
	var brilho := fmod(tempo * 0.45, 1.6) - 0.3
	if brilho > 0.0 and brilho < v:
		var bx := x0 + larg * brilho
		_faixa(alvo, bx, minf(bx + 70.0, x0 + larg * v), y0, y1, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35))
	if fonte != null:
		var base := y0 - 16.0
		alvo.draw_string_outline(fonte, Vector2(x0, base), rotulo, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.7, 30, 8, ESCURO)
		alvo.draw_string(fonte, Vector2(x0, base), rotulo, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.7, 30, Color.WHITE)
		var pct := "%d%%" % int(round(v * 100.0))
		alvo.draw_string_outline(fonte, Vector2(x0, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 34, 8, ESCURO)
		alvo.draw_string(fonte, Vector2(x0, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 34, cor.lightened(0.2))

## A cor que a coluna está mostrando. O texto do medidor usa a mesma,
## senão o número e a barra parecem falar de coisas diferentes.
static func cor_do_dano(dano: float) -> Color:
	return Paleta.AMBAR.lerp(Paleta.VERMELHO, clampf((clampf(dano, 0.0, 1.0) - 0.35) / 0.55, 0.0, 1.0))
