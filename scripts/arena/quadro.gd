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
## `vida` é o que sobrou (1 = inteiro); `fantasma` é a vida de um instante
## atrás, que desce devagar e deixa à mostra, em branco, o pedaço que o
## soco acabou de arrancar. É esse rastro que faz o golpe "doer" na tela.
static func vida(alvo: CanvasItem, fonte: Font, vida: float, fantasma: float, tempo: float, rotulo: String) -> void:
	var r := VIDA
	var v := clampf(vida, 0.0, 1.0)
	var f := clampf(maxf(fantasma, v), 0.0, 1.0)
	# caixa: sombra, trilho escuro, fio de ouro
	alvo.draw_rect(r.grow(8.0), Color(0, 0, 0, 0.45))
	alvo.draw_rect(r.grow(4.0), ESCURO)
	alvo.draw_rect(r, Color("2a0b14"))
	# o rastro do golpe
	if f > v:
		alvo.draw_rect(Rect2(r.position.x + r.size.x * v, r.position.y, r.size.x * (f - v), r.size.y), Color(1, 1, 1, 0.85))
	# a vida: verde → âmbar → vermelho; pisca quando está por um fio
	var cor := Paleta.VERDE.lerp(Paleta.AMBAR, clampf((1.0 - v) / 0.5, 0.0, 1.0))
	cor = cor.lerp(Paleta.VERMELHO, clampf((0.5 - v) / 0.35, 0.0, 1.0))
	if v < 0.25:
		cor = cor.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(tempo * 12.0)))
	var cheio := Rect2(r.position, Vector2(r.size.x * v, r.size.y))
	alvo.draw_rect(cheio, cor)
	# brilho de vidro na metade de cima
	alvo.draw_rect(Rect2(cheio.position, Vector2(cheio.size.x, r.size.y * 0.38)), Color(1, 1, 1, 0.20))
	# divisões a cada 10%
	for i in range(1, 10):
		var x := r.position.x + r.size.x * float(i) / 10.0
		alvo.draw_line(Vector2(x, r.position.y + 6.0), Vector2(x, r.end.y - 6.0), Color(0, 0, 0, 0.35), 2.0)
	alvo.draw_rect(r.grow(4.0), OURO, false, 3.0)
	# o rótulo em cima da barra, à esquerda, e a porcentagem à direita
	if fonte != null:
		var base := r.position.y - 14.0
		alvo.draw_string_outline(fonte, Vector2(r.position.x, base), rotulo, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.7, 30, 8, ESCURO)
		alvo.draw_string(fonte, Vector2(r.position.x, base), rotulo, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.7, 30, Color.WHITE)
		var pct := "%d%%" % int(round(v * 100.0))
		alvo.draw_string_outline(fonte, Vector2(r.position.x, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 30, 8, ESCURO)
		alvo.draw_string(fonte, Vector2(r.position.x, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 30, cor)

## A cor que a coluna está mostrando. O texto do medidor usa a mesma,
## senão o número e a barra parecem falar de coisas diferentes.
static func cor_do_dano(dano: float) -> Color:
	return Paleta.AMBAR.lerp(Paleta.VERMELHO, clampf((clampf(dano, 0.0, 1.0) - 0.35) / 0.55, 0.0, 1.0))
