extends RefCounted
## Cenografia e abertura. Não controla créditos, câmera ou pontuação.
## A IDENTIDADE SUPER BOXING, a mesma do gabinete. Tudo em IMAGEM pronta
## (tools/gerar_tema.py): letreiro desenhado pela fonte, numa TV Box, é
## rasterizado na hora em cada tamanho novo — e foi assim que as letras
## já engasgaram e saíram serrilhadas antes.
const LOGO = preload("res://assets/tema/logo.png")
const FIGHT = preload("res://assets/tema/fight.png")
const NEVER = preload("res://assets/tema/never_give_up.png")
const ATE_O_FIM = preload("res://assets/tema/ate_o_fim.png")
const FUNDO = preload("res://assets/tema/fundo.jpg")
const Icones = preload("res://scripts/icones.gd")
## O SELO DA LAZER & SPORT: o logotipo inteiro numa tela quadrada.
##
## Recortar só o alvo saía com a base cortada — no logotipo original a
## parte de baixo do círculo fica escondida atrás da placa do nome, e sem
## a placa o corte aparece. Redesenhar essa base seria inventar a marca do
## cliente. Com o logotipo completo dentro de um quadrado, o selo fica
## quadrado e pequeno como se pediu, e continua sendo a marca de verdade.
const SELO_LAZER = preload("res://assets/branding/selo_lazer.png")
const RED := Color("ff26a8")
const GOLD := Color("ffd014")
const WHITE := Color("fff9ef")
const FLOOR := Color("0b0620")
const PANEL := Color("1d1040")
const AZUL := Color("46dcff")
## A ENTRADA É UM FILME CURTO, NÃO UM LOGOTIPO APARECENDO.
##
## Cada tempo abaixo é o INÍCIO de um trecho. Eles estão aqui em cima,
## juntos e nomeados, porque a entrada é a única parte do jogo em que
## imagem, som e tremor precisam cair no mesmo quadro: com os números
## espalhados pelo código, acertar isso vira tentativa e erro.
const T_SELO := 0.00     ## o selo da casa, quadrado, apresenta a máquina
const T_VARRER := 0.95   ## dois facões de luz cruzam o escuro
const T_VOO := 1.10      ## a luva entra voando, deixando rastro
const T_SOCO := 1.90     ## o impacto: clarão, ondas e tremor
const T_EMBLEMA := 1.95  ## o emblema nasce do ponto do soco
const T_TITULO := 2.60   ## PUNCH desce batendo
const T_SUBTITULO := 2.90
const T_ASSINATURA := 3.35
const T_BRILHO := 3.50    ## a luz que varre o letreiro no trecho parado
const T_MORPH := 4.45    ## a cena vira, sem corte, a tela de abertura
const MORPH_SECONDS := 0.80 ## movimento completo, sem rasterizar novos corpos
const INTRO_SECONDS := T_MORPH + MORPH_SECONDS

## O selo fica quadrado e PEQUENO: 300 px de lado no meio de uma tela de
## 1080, na altura do olhar. Um selo grande no início rouba o lugar do
## emblema do jogo, que é quem tem de ficar; este só apresenta a casa e
## sai, como o selo da fabricante antes da vinheta.
const SELO_LADO := 360.0
const SELO_CENTRO := Vector2(540.0, 780.0)

## O ponto onde a luva bate e de onde tudo nasce.
const SOCO := Vector2(540.0, 760.0)

## Onde o emblema e o letreiro TERMINAM: exatamente onde a tela de
## abertura os desenha. É essa coincidência que faz a entrada virar
## abertura sem piscada — sem ela o corte aparece.
const POUSO_EMBLEMA := Vector2(540.0, 560.0)
const POUSO_EMBLEMA_TAM := 440.0
const POUSO_PUNCH := 910.0
const POUSO_PUNCH_TAM := 144
const POUSO_CHALLENGE := 1010.0
const POUSO_CHALLENGE_TAM := 80

## O SOM DA ENTRADA, na mesma tabela dos tempos.
##
## Devolvido a quem chama para tocar; a entrada não conhece o
## AudioBank, e não deve conhecer — quem sabe silenciar a máquina é o
## jogo, não a cenografia.
const TRILHA := [
	{"t": T_SELO, "cue": "credit", "db": -12.0},
	{"t": T_VARRER, "cue": "menu", "db": -10.0},
	{"t": T_VOO, "cue": "charge", "db": -14.0},
	{"t": T_SOCO, "cue": "hit", "db": -2.0},
	{"t": T_EMBLEMA + 0.45, "cue": "record", "db": -8.0},
	{"t": T_TITULO, "cue": "start", "db": -6.0},
	{"t": T_SUBTITULO, "cue": "tick", "db": -12.0},
	{"t": T_ASSINATURA, "cue": "credit", "db": -14.0},
	{"t": T_BRILHO, "cue": "menu", "db": -18.0},
	{"t": T_MORPH, "cue": "go", "db": -9.0},
]

## As deixas sonoras cruzadas entre dois instantes. Percorrer a tabela
## por intervalo, e não por "passou de", é o que garante que nenhuma
## deixa se perca num quadro longo nem toque duas vezes num curto.
static func intro_cues(de: float, ate: float) -> Array:
	var saida := []
	for marca in TRILHA:
		var t: float = marca["t"]
		if t > de and t <= ate:
			saida.append(marca)
	return saida

## Aceleração com passada do ponto: o emblema chega, passa um pouco e
## volta. Sem esse excesso ele parece colar na tela em vez de assentar.
static func _passar_do_ponto(t: float, forca := 1.9) -> float:
	var p := t - 1.0
	return p * p * ((forca + 1.0) * p + forca) + 1.0

static func _janela(tempo: float, inicio: float, duracao: float) -> float:
	return clampf((tempo - inicio) / duracao, 0.0, 1.0)

## QUANTO DO ENFEITE DO FUNDO SE DESENHA.
##
## O cenário é a camada que o jogo paga em TODA tela, o tempo inteiro —
## medido, ele era mais de um terço do quadro. Quando a máquina não está
## dando conta, cortar aqui rende mais do que cortar em qualquer outro
## lugar, e é onde ninguém repara: as fagulhas do rodapé e os riscos das
## laterais são atmosfera, não informação.
static var enfeite := 1.0

static func _quantos(cheio: int) -> int:
	return maxi(1, int(round(float(cheio) * enfeite)))

## O CENÁRIO EM DUAS CAMADAS, E POR QUE ISSO IMPORTA NUM PC FRACO.
##
## Isto aqui era UMA função, chamada de um `_draw` que rodava sessenta
## vezes por segundo, em TODA tela do jogo. E a maior parte do que ela
## desenha não se mexe: o chão, os quatro planos vermelhos, as duas
## barras de néon e as duas linhas douradas do horizonte são os mesmos
## pixels, quadro após quadro, do início do expediente até o fim.
##
## Repintar um retângulo de tela cheia mais quatro polígonos grandes mais
## oito barras de 1270 px de altura é trabalho de verdade — em 1080×1920
## é da ordem de milhões de pixels por quadro, e este é o FUNDO: ele paga
## essa conta por baixo de tudo o que o jogo desenha em cima. Num PC
## folgado sobra tempo e ninguém nota. Num PC fraco é exatamente o tanto
## que falta para o quadro fechar dentro do vsync — e quando ele não
## fecha, o movimento vira o solavanco de 60/30 descrito em `Ritmo`.
##
## Separadas, a parte parada vai para um nó próprio que desenha UMA VEZ:
## o Godot guarda a lista de desenho dele e a reaproveita sem executar
## nada de novo. O que continua rodando todo quadro é só o que de fato se
## move — as lâmpadas piscando e as fagulhas subindo —, que é uma fração
## do custo.
static func background(canvas: CanvasItem, time: float) -> void:
	background_estatico(canvas)
	background_animado(canvas, time)

## A PARTE QUE NÃO SE MEXE. Desenhada uma vez por tamanho de tela.
static func background_estatico(canvas: CanvasItem) -> void:
	# A ARTE DO GABINETE: raios roxo, magenta e azul sobre azul-noite,
	# numa imagem só. Um desenho de textura custa menos que os planos e
	# as barras de néon que havia aqui.
	canvas.draw_texture_rect(FUNDO, Rect2(0, 0, 1080, 1920), false)

## A PARTE QUE SE MEXE — e só ela. São vinte e duas fagulhas subindo e
## vinte e quatro lâmpadas piscando: linhas finas e curtas, um custo que
## cabe em qualquer aparelho, agora que não vêm mais acompanhadas de uma
## tela inteira repintada por baixo.
static func background_animado(canvas: CanvasItem, time: float) -> void:
	for side in [0.0, 1.0]:
		var x := lerpf(28.0, 1052.0, side)
		for i in range(_quantos(12)):
			var y := 455.0 + i * 86.0
			var light := 0.25 + 0.75 * pow(0.5 + 0.5 * sin(time * 3.2 - i * 0.65), 3.0)
			canvas.draw_line(Vector2(x - 9, y), Vector2(x + 9, y - 7), Color(RED if i % 2 else AZUL, light * 0.8), 5.0, true)
	for i in range(_quantos(22)):
		var speed := 26.0 + float(i % 4) * 16.0
		var y := fposmod(float(i) * 97.0 - time * speed, 1860.0)
		var x := 65.0 + fposmod(float(i) * 157.0, 950.0)
		canvas.draw_line(Vector2(x, y), Vector2(x + 3, y - 10), Color(AZUL if i % 3 else RED, 0.16), 2.0, true)

## O LOGO SUPER BOXING. `size` é o "tamanho de emblema" de sempre (o
## escudo antigo era quadrado); o logo é mais largo que alto, então a
## largura sai do tamanho e a altura da proporção da imagem.
static func emblem(canvas: CanvasItem, center: Vector2, size: float, alpha := 1.0) -> void:
	var largura := size * 2.1
	var altura := largura * float(LOGO.get_height()) / float(LOGO.get_width())
	Logos.desenhar(canvas, "superboxing", center, altura, alpha)

## Uma imagem da marca centrada, na largura pedida.
static func imagem(canvas: CanvasItem, textura: Texture2D, centro: Vector2, largura: float, cor := Color.WHITE) -> void:
	var altura := largura * float(textura.get_height()) / float(textura.get_width())
	# A logo do jogo sai da versão do tamanho certo (sem pixel quebrado).
	if textura == LOGO:
		Logos.desenhar(canvas, "superboxing", centro, altura, cor.a)
		return
	canvas.draw_texture_rect(textura, Rect2(centro - Vector2(largura, altura) * 0.5, Vector2(largura, altura)), false, cor)

## "FIGHT!" e "NEVER GIVE UP!" no lugar do nome, como no gabinete.
const FIGHT_CENTRO := Vector2(540.0, 890.0)
const FIGHT_LARGURA := 640.0
const NEVER_CENTRO := Vector2(540.0, 1040.0)
const NEVER_LARGURA := 600.0

static func titulo(canvas: CanvasItem, alpha: float, tempo: float) -> void:
	if alpha <= 0.01:
		return
	var bate := 1.0 + 0.025 * maxf(0.0, sin(tempo * 3.4))
	imagem(canvas, FIGHT, FIGHT_CENTRO, FIGHT_LARGURA * bate, Color(1, 1, 1, alpha))
	imagem(canvas, NEVER, NEVER_CENTRO, NEVER_LARGURA, Color(1, 1, 1, alpha))

## A ENTRADA, TRECHO A TRECHO.
##
## Desenhada por cima da cenografia, que já está no lugar: a entrada
## começa apagando essa cenografia com um véu escuro e a devolve à medida
## que os trechos avançam. É a mesma varredura que uma máquina chinesa faz
## com fita de LED — só que aqui em pixels.
static func intro(canvas: Control, time: float) -> void:
	_intro_veu(canvas, time)
	_intro_selo(canvas, time)
	_intro_varredura(canvas, time)
	_intro_voo(canvas, time)
	_intro_impacto(canvas, time)
	var morph := _janela(time, T_MORPH, MORPH_SECONDS)
	_intro_emblema(canvas, time, morph)
	_intro_letreiro(canvas, time, morph)
	_intro_assinatura(canvas, time, morph)
	_intro_brilho(canvas, time, morph)

## O VÉU. Começa fechado e abre no soco: é ele que dá ao clarão do
## impacto alguma coisa de escuro para rasgar. Num fundo já claro o
## flash não teria contra o que brilhar.
static func _intro_veu(canvas: Control, time: float) -> void:
	var fechado := 0.92
	if time >= T_SOCO:
		fechado = lerpf(0.92, 0.0, _janela(time, T_SOCO, 0.85))
	if fechado <= 0.01:
		return
	canvas.draw_rect(Rect2(0, 0, 1080, 1920), Color(FLOOR, fechado))

## Dois facões de luz cruzam a tela antes de qualquer coisa aparecer.
## É o equivalente visual do "atenção" que vem antes do anúncio.
static func _intro_varredura(canvas: Control, time: float) -> void:
	var t := _janela(time, T_VARRER, 0.62)
	if t >= 1.0:
		return
	var forca := sin(t * PI)
	for lado in [-1.0, 1.0]:
		var x := lerpf(540.0 + lado * 1700.0, 540.0, ease(t, 0.35))
		var faixa := PackedVector2Array([
			Vector2(x - 190.0, 0.0), Vector2(x + 190.0, 0.0),
			Vector2(x + 420.0, 1920.0), Vector2(x + 40.0, 1920.0),
		])
		Traco.poligono(canvas, faixa, Color(GOLD, 0.34 * forca))
		canvas.draw_line(Vector2(x, 0.0), Vector2(x + 230.0, 1920.0), Color(WHITE, 0.95 * forca), 7.0, true)
	# A linha do horizonte que abre junto: sem ela os dois facões passam
	# por um retângulo preto e a máquina parece que ainda não ligou.
	var abertura := ease(t, 0.3)
	var meia := 1080.0 * abertura
	canvas.draw_line(
		Vector2(540.0 - meia, 960.0), Vector2(540.0 + meia, 960.0),
		Color(WHITE, forca * 0.8), lerpf(2.0, 26.0, 1.0 - t), true
	)

## O SOCO VEM DE LADO, E VEM PARA CIMA DE QUEM OLHA.
##
## A primeira versão fazia a luva subir da diagonal de baixo, chapada,
## do mesmo tamanho o caminho inteiro e DESACELERANDO no fim. Isso é o
## movimento de quem estende o braço para pegar alguma coisa, não o de
## quem bate: soco nenhum freia antes de acertar.
##
## Três coisas mudam aqui, e são elas que fazem o golpe parecer golpe:
##
##   LADO.        Entra pela direita, na altura do olhar, e não do chão.
##                É de onde um soco chega quando quem bate está de pé na
##                frente da máquina — o mesmo eixo do soco de verdade.
##   PERSPECTIVA. Longe é pequeno; perto é enorme. O raio quase não muda
##                na primeira metade do caminho e multiplica por nove na
##                última — é assim que uma coisa vindo NA DIREÇÃO da
##                câmera cresce, e é o que vende a profundidade numa tela
##                que não tem profundidade nenhuma.
##   ACELERAÇÃO.  `pow(t, 2.4)`: sai devagar e chega estourando. A curva
##                antiga (`ease(t, 0.32)`) fazia o contrário.
##
## E o antebraço. Uma luva sozinha voando é um objeto flutuando; o braço
## atrás dela, saindo da borda da tela, é o que diz que tem alguém ali.
const VOO_PARTIDA := Vector2(1180.0, 500.0)
const VOO_DURACAO := T_SOCO - T_VOO

## Onde a luva está, e de que tamanho, numa fração do voo.
static func _voo_em(avanco: float) -> Dictionary:
	var reta := VOO_PARTIDA.lerp(SOCO, avanco)
	# Uma barriga na trajetória: o punho descreve um arco, como o braço
	# que gira no ombro. Em linha reta o voo lê como um slide de
	# apresentação atravessando a tela.
	var desvio := Vector2(0.0, -1.0) * sin(avanco * PI) * 120.0
	return {
		"centro": reta + desvio,
		"raio": lerpf(64.0, 440.0, pow(avanco, 1.45)),
	}

static func _intro_voo(canvas: Control, time: float) -> void:
	if time < T_VOO or time >= T_SOCO + 0.10:
		return
	var t := _janela(time, T_VOO, VOO_DURACAO)
	var avanco := pow(t, 1.9)
	var agora: Dictionary = _voo_em(avanco)
	var centro: Vector2 = agora["centro"]
	var raio: float = agora["raio"]
	# A direção do golpe sai da própria trajetória, e não de uma constante:
	# com a barriga do arco, a direção no começo e no fim não são a mesma.
	var antes: Dictionary = _voo_em(maxf(avanco - 0.02, 0.0))
	var direcao: Vector2 = (centro - antes["centro"]).normalized()
	if direcao.length_squared() < 0.5:
		direcao = (SOCO - VOO_PARTIDA).normalized()

	_voo_vento(canvas, centro, raio, direcao, t)
	# O RASTRO, do mais antigo para o mais novo: cada fantasma é a luva
	# como ela era alguns centésimos atrás, com o tamanho daquele momento.
	# Fantasmas do mesmo tamanho do punho atual pareciam uma fileira de
	# bolas, e não uma coisa só que passou.
	for i in range(6, 0, -1):
		var atras := maxf(avanco - float(i) * 0.048, 0.0)
		if atras <= 0.0:
			continue
		var passado: Dictionary = _voo_em(atras)
		var forca := (1.0 - float(i) / 7.0) * 0.42
		_punho(canvas, passado["centro"], passado["raio"], direcao, Color(RED, forca), true)
	_punho(canvas, centro, raio, direcao, Color(1, 1, 1, 1), false)
	_voo_riscos(canvas, centro, raio, direcao, t)

## O CONE DE VENTO: o ar empurrado à frente do golpe, aberto para trás.
## É o que preenche o vazio entre a borda da tela e o punho enquanto ele
## ainda está pequeno e longe.
static func _voo_vento(canvas: Control, centro: Vector2, raio: float, direcao: Vector2, t: float) -> void:
	var perp := Vector2(-direcao.y, direcao.x)
	var fundo := centro - direcao * (raio * 2.0 + 1500.0)
	var forca := 0.10 + 0.16 * t
	Traco.poligono(canvas, PackedVector2Array([
		centro + perp * raio * 0.95,
		centro - perp * raio * 0.95,
		fundo - perp * raio * 2.4,
		fundo + perp * raio * 2.4,
	]), Color(RED, forca * 0.35))
	Traco.poligono(canvas, PackedVector2Array([
		centro + perp * raio * 0.45,
		centro - perp * raio * 0.45,
		fundo - perp * raio * 1.1,
		fundo + perp * raio * 1.1,
	]), Color(GOLD, forca * 0.30))

## Riscas de velocidade CONVERGINDO no punho. Elas nascem longe, atrás
## dele, e apontam para onde ele está: é o olho do público sendo puxado
## para o ponto do impacto antes do impacto acontecer.
static func _voo_riscos(canvas: Control, centro: Vector2, raio: float, direcao: Vector2, t: float) -> void:
	var perp := Vector2(-direcao.y, direcao.x)
	for i in range(18):
		var lado := perp * randf_range(-1.0, 1.0) * (raio * 1.9 + 260.0)
		var origem := centro - direcao * randf_range(raio * 1.2, raio * 3.4 + 900.0) + lado
		var comprimento := randf_range(120.0, 320.0) * (0.5 + t)
		var cor := GOLD if i % 3 else WHITE
		canvas.draw_line(
			origem, origem + direcao * comprimento,
			Color(cor, 0.16 + 0.22 * t), lerpf(2.0, 6.0, t), true
		)

## O PUNHO, montado na direção do voo.
##
## Não é a luva do ícone: aquela é um PERFIL, desenhada para caber num
## botão e ser reconhecida de lado. Aqui a luva vem DE FRENTE, na cara de
## quem olha, e o que se vê de um soco assim é a fileira dos nós dos
## dedos ocupando a borda de ataque, o polegar dobrado de um lado e o
## cano do punho sumindo para trás. É outra figura, e por isso mora aqui
## e não em `Icones`.
##
## A ORDEM DO DESENHO É O DESENHO. Três passadas:
##
##   1. a silhueta inteira em tinta escura — mão, quatro nós, polegar e
##      cano, todos um pouco maiores do que serão;
##   2. as mesmas formas em couro, encolhidas o bastante para a passada
##      escura sobrar como contorno em volta de tudo;
##   3. os brilhos, só onde a luz bateria.
##
## Foi isso que salvou a figura: com os nós desenhados por cima de um
## disco liso, eles viravam uma lagarta atravessando uma bola. Fazendo os
## nós participarem da SILHUETA, a borda de ataque fica recortada — e é
## essa borda recortada que o olho lê como punho fechado.
const NOS := 4

## Onde fica cada nó do dedo, e o polegar, em relação ao centro.
static func _nos_do_punho(centro: Vector2, r: float, direcao: Vector2, perp: Vector2) -> Array:
	var lugares := []
	for i in range(NOS):
		var passo := (-0.54 + float(i) * 0.36) * r
		# Os nós das pontas ficam um pouco atrás: a mão é redonda, não
		# uma régua, e alinhá-los todos achatava a frente do punho.
		var recuo := 0.62 - pow(absf(passo / r) * 1.5, 2.0) * 0.30
		lugares.append(centro + direcao * r * recuo + perp * passo)
	return lugares

static func _punho(canvas: Control, centro: Vector2, raio: float, direcao: Vector2, tinta: Color, vulto: bool) -> void:
	var r := raio
	var perp := Vector2(-direcao.y, direcao.x)
	var a := tinta.a
	if a <= 0.01:
		return
	var couro := Color("e01430", a)
	var sombra := Color("5c0714", a)
	var luz := Color("ff7183", a)
	var polegar := centro - perp * r * 0.74 + direcao * r * 0.06
	var cano := centro - direcao * r * 0.66
	var lugares := _nos_do_punho(centro, r, direcao, perp)

	# ANTEBRAÇO. Afina para trás porque em perspectiva ele está mais longe
	# da câmera que a mão. Sem ele a luva é um objeto flutuando.
	var fundo := centro - direcao * (r * 4.2)
	Traco.poligono(canvas, PackedVector2Array([
		centro + perp * r * 0.62,
		centro - perp * r * 0.62,
		fundo - perp * r * 0.26,
		fundo + perp * r * 0.26,
	]), sombra if not vulto else Color(RED, a))

	if vulto:
		# Fantasma do rastro: uma mancha só, do tamanho daquele instante.
		# Um fantasma com nó de dedo e brilho vira sujeira, não rastro.
		canvas.draw_circle(centro, r * 0.96, Color(RED, a), true, -1.0, true)
		return

	# 1) A SILHUETA, em tinta escura e um degrau maior que a figura.
	canvas.draw_circle(cano, r * 0.80, sombra, true, -1.0, true)
	canvas.draw_circle(centro, r * 1.00, sombra, true, -1.0, true)
	canvas.draw_circle(polegar, r * 0.38, sombra, true, -1.0, true)
	for lugar in lugares:
		canvas.draw_circle(lugar, r * 0.36, sombra, true, -1.0, true)

	# 2) O COURO, encolhido — o que sobra da passada escura é o contorno.
	canvas.draw_circle(cano, r * 0.72, Color("a80f24", a), true, -1.0, true)
	canvas.draw_circle(centro, r * 0.92, couro, true, -1.0, true)
	canvas.draw_circle(polegar, r * 0.30, Color("c8122b", a), true, -1.0, true)
	for lugar in lugares:
		canvas.draw_circle(lugar, r * 0.28, Color("f0243e", a), true, -1.0, true)

	# 3) A LUZ. Um clarão no alto da mão — a lâmpada do galpão está em
	# cima — e um fio de luz na quina que chega primeiro.
	canvas.draw_circle(centro + perp * r * 0.30 - direcao * r * 0.22, r * 0.30, Color(luz, a * 0.55), true, -1.0, true)
	for lugar in lugares:
		canvas.draw_circle(lugar + perp * r * 0.06 - direcao * r * 0.02, r * 0.15, Color(luz, a * 0.9), true, -1.0, true)
	var ang := direcao.angle()
	canvas.draw_arc(centro, r * 0.99, ang - 0.55, ang + 0.55, 22, Color(WHITE, a * 0.45), r * 0.05, true)

## O SOCO. Clarão, três ondas e um leque de riscas saindo do ponto.
static func _intro_impacto(canvas: Control, time: float) -> void:
	if time < T_SOCO:
		return
	# Curto de propósito: o clarão do jogo (`_draw_clarao`) já lava a tela
	# de âmbar por cima deste. Os dois no volume cheio deixavam a tela
	# amarela por meio segundo, o que não é um flash, é um apagão claro.
	var t := _janela(time, T_SOCO, 0.30)
	if t < 1.0:
		canvas.draw_rect(Rect2(0, 0, 1080, 1920), Color(WHITE, pow(1.0 - t, 2.0) * 0.55))
	for i in range(3):
		var onda := _janela(time, T_SOCO + float(i) * 0.09, 0.62)
		if onda <= 0.0 or onda >= 1.0:
			continue
		var raio := lerpf(40.0, 780.0 + float(i) * 130.0, ease(onda, 0.35))
		var cor: Color = [WHITE, GOLD, RED][i]
		Traco.arco(canvas, SOCO, raio, Color(cor, (1.0 - onda) * 0.75), 10.0 - float(i) * 2.0)
	var leque := _janela(time, T_SOCO, 0.7)
	if leque < 1.0:
		for i in range(26):
			var direcao := Vector2.from_angle(float(i) * TAU / 26.0 + 0.12)
			var perto := 180.0 + leque * 620.0
			canvas.draw_line(
				SOCO + direcao * perto, SOCO + direcao * (perto + lerpf(230.0, 40.0, leque)),
				Color(GOLD, (1.0 - leque) * 0.9), lerpf(9.0, 2.0, leque), true
			)

## O EMBLEMA NASCE DO PONTO DO SOCO e, no fim, caminha até o lugar exato
## em que a tela de abertura o desenha.
static func _intro_emblema(canvas: Control, time: float, morph: float) -> void:
	if time < T_EMBLEMA:
		return
	var abre := _janela(time, T_EMBLEMA, 0.50)
	var escala := _passar_do_ponto(abre) if abre < 1.0 else 1.0
	var tamanho := lerpf(620.0 * escala, POUSO_EMBLEMA_TAM, smoothstep(0.0, 1.0, morph))
	var centro := SOCO.lerp(POUSO_EMBLEMA, smoothstep(0.0, 1.0, morph))
	# Anel de luz que gira em volta enquanto o emblema assenta; some no
	# morph para não sobrar na abertura, que não tem esse anel.
	var anel := (1.0 - morph) * clampf(abre * 1.4, 0.0, 1.0)
	if anel > 0.01:
		var raio := tamanho * 0.62
		for i in range(24):
			var ang := float(i) * TAU / 24.0 + time * 1.6
			var brilho := 0.35 + 0.65 * pow(0.5 + 0.5 * sin(ang * 3.0 - time * 5.0), 2.0)
			canvas.draw_line(
				centro + Vector2.from_angle(ang) * raio,
				centro + Vector2.from_angle(ang) * (raio + 26.0),
				Color(GOLD, anel * brilho * 0.8), 5.0, true
			)
	# Opacidade cheia quase de imediato: o emblema NASCE do clarão, não
	# aparece esmaecendo. Quem cresce é o tamanho, não a tinta — um
	# emblema meio transparente sobre o escuro sai cinza, e cinza é a
	# única cor que esta marca não tem.
	emblem(canvas, centro, tamanho, _janela(time, T_EMBLEMA, 0.12))

## PUNCH desce batendo, CHALLENGE entra deslizando. Os dois nascem com a
## separação de cor de um monitor mal ajustado, que se fecha conforme
## assentam — é o susto que faz o letreiro parecer que CHEGOU.
static func _intro_letreiro(canvas: Control, time: float, morph: float) -> void:
	if time < T_TITULO:
		return
	# FIGHT! desce batendo; NEVER GIVE UP! entra deslizando. Nascem com a
	# separação de cor de um monitor mal ajustado, que fecha ao assentar.
	var desce := _janela(time, T_TITULO, 0.42)
	var fight_y := lerpf(980.0, 1260.0, _passar_do_ponto(desce, 1.4)) if desce < 1.0 else 1260.0
	fight_y = lerpf(fight_y, FIGHT_CENTRO.y, smoothstep(0.0, 1.0, morph))
	var fight_l := lerpf(700.0, FIGHT_LARGURA, smoothstep(0.0, 1.0, morph))
	var separa := (1.0 - desce) * 26.0
	if separa > 0.5:
		imagem(canvas, FIGHT, Vector2(540.0 - separa, fight_y), fight_l, Color(RED, 0.55))
		imagem(canvas, FIGHT, Vector2(540.0 + separa, fight_y), fight_l, Color(AZUL, 0.55))
	imagem(canvas, FIGHT, Vector2(540.0, fight_y), fight_l, Color(1, 1, 1, clampf(desce * 2.0, 0.0, 1.0)))

	if time < T_SUBTITULO:
		return
	var desliza := _janela(time, T_SUBTITULO, 0.45)
	var sub_y := lerpf(1400.0, NEVER_CENTRO.y, smoothstep(0.0, 1.0, morph))
	var entra := lerpf(420.0, 0.0, ease(desliza, 0.28))
	imagem(canvas, NEVER, Vector2(540.0 + entra, sub_y), NEVER_LARGURA, Color(1, 1, 1, desliza))
	if desliza < 1.0 and morph <= 0.0:
		var meia := 470.0 * ease(desliza, 0.3)
		canvas.draw_line(
			Vector2(540.0 - meia, sub_y + 70.0), Vector2(540.0 + meia, sub_y + 70.0),
			Color(GOLD, 1.0 - desliza * 0.75), 6.0, true
		)

## A ASSINATURA DA CASA e o recorde. Entram por último porque são a
## informação, e informação depois do espetáculo é informação que fica.
static func _intro_assinatura(canvas: Control, time: float, morph: float) -> void:
	if time < T_ASSINATURA:
		return
	var t := _janela(time, T_ASSINATURA, 0.5)
	# A assinatura APAGA na virada em vez de viajar até o topo. Subindo,
	# ela cruzava por cima de PUNCH e de CHALLENGE no meio do caminho — e
	# a abertura já desenha a sua própria, no lugar certo, logo em
	# seguida.
	var saida := 1.0 - ease(morph, 0.5)
	# A MARCA DESENHADA, e não a frase. O mesmo logotipo do selo da
	# entrada, agora pequeno, assinando o cartaz.
	canvas._marca_da_casa(1478.0, 104.0, t * saida)
	canvas._texto(
		"QUAL É A SUA FORÇA?", 1622.0, 32,
		Color(WHITE, t * saida * (0.82 + 0.18 * sin(time * 5.0)))
	)

## O TRECHO PARADO NÃO PODE FICAR PARADO.
##
## Entre o subtítulo assentar e a virada para a abertura há cerca de um
## segundo em que nada mais entra — e um segundo de imagem congelada, num
## fliperama, é a máquina parecendo travada. Uma luz varre o letreiro e o
## emblema dá uma batida, como um letreiro de metal pegando o refletor.
static func _intro_brilho(canvas: Control, time: float, morph: float) -> void:
	var t := _janela(time, T_BRILHO, 0.85)
	if t <= 0.0 or morph > 0.0:
		return
	# A FAIXA RETANGULAR SAIU DAQUI.
	#
	# Eram três quadriláteros atravessando a tela na altura do letreiro.
	# Como o quadrilátero não sabe onde a letra está, a luz aparecia
	# também no vazio entre as letras e em volta delas. O reflexo da
	# abertura agora é recortado pelo shader próprio do Letreiro.
	# MAS TIRAR A FAIXA DEIXOU UM BURACO, e ele apareceu como "a abertura
	# trava no fim".
	#
	# Este trecho é o segundo em que o letreiro já assentou e a virada
	# para a tela de abertura ainda não começou. Era a faixa que enchia
	# esse segundo; sem ela sobrou uma imagem parada, e imagem parada num
	# fliperama não lê como pausa — lê como máquina travada. O conserto
	# não é devolver o retângulo: é pôr aqui o que estava faltando desde
	# sempre, que é a cena RESPIRANDO enquanto espera.
	var batida := _janela(time, T_BRILHO + 0.15, 0.75)
	if batida > 0.0 and batida < 1.0:
		var raio_batida := lerpf(300.0, 640.0, ease(batida, 0.35))
		canvas.draw_arc(
			Vector2(540.0, 760.0), raio_batida,
			0.0, TAU, Traco.segmentos(raio_batida), Color(GOLD, (1.0 - batida) * 0.5), 5.0, true
		)
	# Brasas subindo do rodapé: movimento lento e contínuo, que é o que
	# uma cena parada precisa para continuar viva sem roubar a atenção
	# do letreiro.
	for i in range(14):
		var fase := fposmod(time * 0.24 + float(i) * 0.137, 1.0)
		var x := 90.0 + fposmod(float(i) * 271.0, 900.0)
		var y := lerpf(1780.0, 1180.0, fase)
		var brilho := sin(fase * PI) * 0.55
		canvas.draw_circle(
			Vector2(x + sin(time * 1.7 + float(i)) * 22.0, y),
			lerpf(5.0, 2.0, fase), Color(GOLD, brilho * t), true, -1.0, false
		)
	# E um pulso de luz atrás do emblema, no compasso de uma respiração.
	# Sem ele o miolo da tela fica absolutamente imóvel por um segundo
	# inteiro, que é justamente o que se sente como travamento.
	var pulso := 0.5 + 0.5 * sin(time * 3.1)
	canvas.draw_circle(
		Vector2(540.0, 760.0), 250.0 + pulso * 26.0,
		Color(RED, 0.05 * t), true, -1.0, true
	)

## O SELO DA CASA, QUADRADO, ABRINDO A ENTRADA.
##
## A máquina abria com o logotipo comprido da Lazer & Sport numa tela de
## fundo azul-marinho — nem a forma nem a cor tinham parentesco com o
## jogo que vinha logo depois, e a troca para o emblema do Punch parecia
## defeito. Agora quem apresenta é o SÍMBOLO sozinho, recortado quadrado,
## pequeno, dentro de uma placa no mesmo vermelho e no mesmo ouro do
## resto — e o brilho que passa por cima é o mesmo que varre o letreiro
## mais adiante. Continua sendo a marca da casa; deixou de ser um
## estranho na porta.
static func _intro_selo(canvas: Control, time: float) -> void:
	# A TINTA CHEGA ANTES DA FORMA: o selo fica opaco em pouco mais de um
	# quinto de segundo, e só a escala continua assentando. Uma marca
	# entrando semitransparente sai desbotada, e desbotado é o contrário
	# do que um selo de fabricante precisa parecer.
	var entra := _janela(time, T_SELO, 0.22)
	var forma := _janela(time, T_SELO, 0.45)
	# E SAI ANTES de os facões de luz entrarem: sobrepostos, a linha do
	# horizonte cruzava o selo e parecia uma barra solta na tela.
	var sai := _janela(time, T_VARRER - 0.22, 0.20)
	var alpha := entra * (1.0 - sai)
	if alpha <= 0.01:
		return
	var lado := SELO_LADO * lerpf(0.86, 1.0, _passar_do_ponto(forma, 1.6) if forma < 1.0 else 1.0)
	var placa := Rect2(SELO_CENTRO - Vector2.ONE * lado * 0.5, Vector2.ONE * lado)
	var raio := lado * 0.19

	# Halo por trás: separa a placa do preto sem precisar de sombra.
	for i in range(5):
		canvas.draw_circle(SELO_CENTRO, lado * (0.62 + float(i) * 0.10), Color(GOLD, 0.030 * alpha), true, -1.0, true)

	_placa_redonda(canvas, placa, raio, Color(Color("2a0a12"), alpha))
	_contorno_redondo(canvas, placa, raio, Color(GOLD, alpha), 4.0)
	# Bisel: um fio claro em cima e um escuro embaixo, que é o que faz
	# uma placa lisa parecer uma peça e não um retângulo pintado.
	canvas.draw_line(
		placa.position + Vector2(raio, 5.0), placa.position + Vector2(placa.size.x - raio, 5.0),
		Color(WHITE, alpha * 0.22), 3.0, true
	)

	var dentro := lado * 0.86
	canvas.draw_texture_rect(
		SELO_LAZER, Rect2(SELO_CENTRO - Vector2.ONE * dentro * 0.5, Vector2.ONE * dentro),
		false, Color(1, 1, 1, alpha)
	)

	# O BRILHO QUE ATRAVESSA. Uma faixa inclinada recortada na placa —
	# recortada de verdade, e não só desenhada por cima: sem o recorte ela
	# vazaria pelos cantos e a placa deixaria de parecer sólida.
	var brilho := _janela(time, T_SELO + 0.26, 0.45)
	if brilho > 0.0 and brilho < 1.0:
		var x := lerpf(placa.position.x - lado * 0.6, placa.end.x + lado * 0.6, ease(brilho, 0.5))
		for camada in range(2):
			var meia := 16.0 + float(camada) * 30.0
			var faixa := PackedVector2Array([
				Vector2(x - meia + lado * 0.22, placa.position.y),
				Vector2(x + meia + lado * 0.22, placa.position.y),
				Vector2(x + meia - lado * 0.22, placa.end.y),
				Vector2(x - meia - lado * 0.22, placa.end.y),
			])
			var recortada := _recortar_no_retangulo(faixa, placa.grow(-4.0))
			if recortada.size() >= 3:
				Traco.poligono(canvas, recortada, Color(WHITE, (0.30 - float(camada) * 0.16) * alpha))

	# O SÍMBOLO EM CIMA, O NOME EMBAIXO. É a ordem da marca: quem vê de
	# longe reconhece o alvo antes de conseguir ler qualquer coisa, e o
	# nome confirma. Invertido, o cartaz vira uma linha de texto com um
	# desenho pendurado.
	canvas._texto("LAZER & SPORT GAMES", SELO_CENTRO.y + lado * 0.78, 30, Color(GOLD, alpha))
	canvas._texto("APRESENTA", SELO_CENTRO.y + lado * 0.78 + 44.0, 20, Color(WHITE, alpha * 0.70))

static func _placa_redonda(canvas: CanvasItem, rect: Rect2, raio: float, cor: Color) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(raio, 0.0), rect.size - Vector2(raio * 2.0, 0.0)), cor)
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, raio), Vector2(rect.size.x, rect.size.y - raio * 2.0)), cor)
	for canto in _cantos(rect, raio):
		canvas.draw_circle(canto, raio, cor, true, -1.0, true)

static func _contorno_redondo(canvas: CanvasItem, rect: Rect2, raio: float, cor: Color, largura: float) -> void:
	canvas.draw_line(rect.position + Vector2(raio, 0.0), Vector2(rect.end.x - raio, rect.position.y), cor, largura, true)
	canvas.draw_line(Vector2(rect.position.x, rect.position.y + raio), Vector2(rect.position.x, rect.end.y - raio), cor, largura, true)
	canvas.draw_line(Vector2(rect.end.x, rect.position.y + raio), Vector2(rect.end.x, rect.end.y - raio), cor, largura, true)
	canvas.draw_line(Vector2(rect.position.x + raio, rect.end.y), Vector2(rect.end.x - raio, rect.end.y), cor, largura, true)
	var quartos := [PI, -PI * 0.5, 0.0, PI * 0.5]
	var i := 0
	for canto in _cantos(rect, raio):
		canvas.draw_arc(canto, raio, quartos[i], quartos[i] + PI * 0.5, 16, cor, largura, true)
		i += 1

static func _cantos(rect: Rect2, raio: float) -> Array:
	return [
		rect.position + Vector2(raio, raio),
		Vector2(rect.end.x - raio, rect.position.y + raio),
		rect.end - Vector2(raio, raio),
		Vector2(rect.position.x + raio, rect.end.y - raio),
	]

## Sutherland–Hodgman contra as quatro bordas de um retângulo.
##
## Existe porque o desenho imediato do Godot não tem recorte: sem isto, a
## única saída seria clarear a faixa até ela sumir, e um brilho que não se
## vê não é brilho.
static func _recortar_no_retangulo(poligono: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var atual := poligono
	var bordas := [
		["x", 1.0, rect.position.x],   ## dentro é x >= esquerda
		["x", -1.0, rect.end.x],       ## dentro é x <= direita
		["y", 1.0, rect.position.y],
		["y", -1.0, rect.end.y],
	]
	for borda in bordas:
		if atual.is_empty():
			return atual
		var eixo: String = borda[0]
		var sinal: float = borda[1]
		var limite: float = borda[2]
		var saida := PackedVector2Array()
		var anterior: Vector2 = atual[atual.size() - 1]
		for ponto in atual:
			var d_ponto := (ponto.x if eixo == "x" else ponto.y) * sinal - limite * sinal
			var d_ant := (anterior.x if eixo == "x" else anterior.y) * sinal - limite * sinal
			if d_ponto >= 0.0:
				if d_ant < 0.0:
					saida.append(anterior.lerp(ponto, d_ant / (d_ant - d_ponto)))
				saida.append(ponto)
			elif d_ant >= 0.0:
				saida.append(anterior.lerp(ponto, d_ant / (d_ant - d_ponto)))
			anterior = ponto
		atual = saida
	return atual
