class_name ImpactDirector
extends RefCounted

## QUEM MONTA O ESPETÁCULO DO SOCO.
##
## Recebe o nível (`ScoreTier`) e produz o que aquele nível pede:
## partículas, ondas, tremor, clarão, hit-stop, zoom e os desenhos
## próprios de cada faixa. `main.gd` continua mandando nos ESTADOS da
## máquina; o que acontece na tela quando o soco entra mora aqui.
##
## POR QUE SEPARADO. Oito níveis com apresentação própria são oito
## receitas, e receita misturada com máquina de estados é como dois
## níveis acabam com a mesma animação — ninguém percebe a repetição no
## meio de mil linhas de fluxo. Aqui elas ficam lado a lado.

const Icones = preload("res://scripts/icones.gd")

## Duração do estrelão de pancada.
const PANCADA_DURACAO := 0.40
const PANCADA_PONTAS := 14

# ======================================================================
# O QUE VOA
# ======================================================================
## Dispara tudo o que o nível pede no instante do golpe. Devolve o que
## `main.gd` precisa aplicar em si mesmo (tremor, clarão, hit-stop e
## zoom), porque essas quatro coisas são estado do jogo e não partícula.
static func golpe(fx: PunchFX, alvo: Vector2, nivel: Dictionary, cores: Array) -> Dictionary:
	var cor: Color = nivel["cor"]

	for i in range(int(nivel["ondas"])):
		var atraso := float(i) * 0.09
		var raio: float = float(nivel["onda_raio"]) * (1.0 + float(i) * 0.22)
		var tinta: Color = [Paleta.CREME, cor, Paleta.AMBAR][i % 3]
		fx.onda(alvo, 40.0 + float(i) * 70.0, raio, Color(tinta, 0.66 - float(i) * 0.10),
			18.0 - float(i) * 3.0, 0.55 + atraso + float(i) * 0.22)

	if int(nivel["faiscas"]) > 0:
		fx.faiscas(alvo, int(nivel["faiscas"]), cor, 700.0 + float(nivel["tremor"]) * 26.0)
	if int(nivel["brasas"]) > 0:
		fx.explosao(alvo, int(nivel["brasas"]), cores, 900.0 + float(nivel["tremor"]) * 22.0)
	if int(nivel["raios"]) > 0:
		fx.raios(alvo, int(nivel["raios"]), Paleta.AMBAR, 700.0 + float(nivel["tremor"]) * 12.0)
	if int(nivel["chuva"]) > 0:
		fx.chuva_de_brasas(1080.0, int(nivel["chuva"]), cores)
	if int(nivel["estilhacos"]) > 0:
		fx.estilhacos(alvo, int(nivel["estilhacos"]), Color("6b7b98"))
	if int(nivel["poeira"]) > 0:
		fx.poeira(alvo + Vector2(0.0, 220.0), int(nivel["poeira"]), Color(0.45, 0.50, 0.62, 0.45), 300.0)

	return {
		"tremor": float(nivel["tremor"]),
		"clarao": float(nivel["clarao"]),
		"hitstop": float(nivel["hitstop"]),
		"zoom": float(nivel["zoom"]),
	}

## A COMEMORAÇÃO QUE CONTINUA, enquanto o veredito está na tela.
##
## Só os níveis com `festa_intervalo` acima de zero comemoram: um impacto
## leve que ficasse soltando brasa por cinco segundos diria à pessoa que
## ela mandou bem, e ela não mandou.
## OS LUGARES DE ONDE UM FOGO DE ARTIFÍCIO ESTOURA.
##
## Eram sorteados: `randf_range(180, 900) x randf_range(300, 1100)`, um
## ponto qualquer da tela a cada estouro. Sorteio é o contrário de
## composição — um deles caía em cima do placar, o seguinte na borda, o
## terceiro no meio do nome do nível, e o conjunto lia como defeito e não
## como festa. Um show de fogos tem RITMO E LUGAR: os tiros se alternam,
## sobem, e explodem numa faixa de céu, sempre acima do que se está
## lendo.
##
## Sete pontos fixos, percorridos em ordem trocada de propósito — nunca
## dois seguidos do mesmo lado, e nenhum deles em cima do placar, que
## fica no meio da tela.
const CEU := [
	Vector2(210.0, 430.0),
	Vector2(870.0, 330.0),
	Vector2(410.0, 250.0),
	Vector2(930.0, 560.0),
	Vector2(150.0, 300.0),
	Vector2(680.0, 400.0),
	Vector2(540.0, 210.0),
]
static var _proximo_ponto := 0

static func festa(fx: PunchFX, alvo: Vector2, nivel: Dictionary, cores: Array) -> void:
	var cor: Color = nivel["cor"]
	var ponto: Vector2 = CEU[_proximo_ponto % CEU.size()]
	_proximo_ponto += 1
	# Um empurrãozinho aleatório em volta do ponto fixo: composto não é
	# mecânico, e dois estouros exatamente no mesmo pixel denunciam a
	# tabela.
	ponto += Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0))

	# O ESTOURO, EM TRÊS CAMADAS E MAIS DEVAGAR.
	#
	# A onda antiga vivia meio segundo e as fagulhas saíam a 780 px/s:
	# nesse ritmo o fogo nasce e morre antes de o olho chegar nele, e o
	# que se vê é um piscar. Um fogo de artifício ABRE, fica um instante
	# no ar e cai — quase dois segundos, do estouro à última fagulha.
	fx.onda(ponto, 6.0, randf_range(200.0, 330.0), Color(Paleta.CREME, 0.55), 7.0, 0.85)
	fx.onda(ponto, 4.0, randf_range(150.0, 260.0), Color(cor, 0.45), 5.0, 1.05)
	fx.explosao(ponto, 14 + int(nivel["raios"]), cores, 430.0)
	fx.faiscas(ponto, 10, Paleta.AMBAR, 300.0)
	if bool(nivel["palco"]):
		fx.chuva_de_brasas(1080.0, 3, cores)

# ======================================================================
# O QUE SE DESENHA
# ======================================================================
## O desenho do impacto, por nível. `t` vai de 0 a 1 ao longo de
## `PANCADA_DURACAO`; `forca` é a posição do golpe dentro da escala.
static func desenhar(canvas: CanvasItem, nivel: Dictionary, t: float, alvo: Vector2, forca: float) -> void:
	var some := pow(1.0 - t, 1.6)
	var cor: Color = nivel["cor"]

	if bool(nivel["tunel"]):
		_tunel_de_luz(canvas, alvo, t, cor)
	_riscos_convergindo(canvas, alvo, t, some)
	_estrelao(canvas, alvo, t, some, forca, cor)
	if bool(nivel["rachaduras"]):
		_rachaduras(canvas, alvo, t, some)
	if bool(nivel["palco"]):
		_palco_reage(canvas, alvo, t, some)

## O TÚNEL: anéis fugindo para o fundo, dando profundidade ao golpe.
## Só nos níveis altos — num soco médio ele roubaria a leitura do número.
static func _tunel_de_luz(canvas: CanvasItem, centro: Vector2, t: float, cor: Color) -> void:
	for i in range(7):
		var fase := fmod(t * 1.6 + float(i) / 7.0, 1.0)
		var raio := lerpf(1300.0, 90.0, fase)
		var tinta: Color = cor if i % 2 == 0 else Paleta.AMBAR
		Traco.arco(canvas, centro, raio, Color(tinta, fase * (1.0 - t) * 0.55), 14.0)

static func _riscos_convergindo(canvas: CanvasItem, centro: Vector2, t: float, some: float) -> void:
	for i in range(20):
		var ang := float(i) * TAU / 20.0 + 0.17
		var de := 420.0 + (1.0 - t) * 420.0
		var ate := de - lerpf(220.0, 40.0, t)
		canvas.draw_line(
			centro + Vector2.from_angle(ang) * de, centro + Vector2.from_angle(ang) * ate,
			Color(Paleta.AMBAR, some * 0.55), lerpf(8.0, 2.0, t), true
		)

## O ESTRELÃO DE HISTÓRIA EM QUADRINHOS. As pontas vêm de um molde fixo:
## um estrelão que se sorteia a cada quadro é ruído, não impacto.
static func _estrelao(
	canvas: CanvasItem, centro: Vector2, t: float, some: float, forca: float, cor: Color
) -> void:
	var escala := lerpf(0.35, 1.0, ease(t, 0.28)) * (0.75 + forca * 0.55)
	var fora := PackedVector2Array()
	var dentro := PackedVector2Array()
	for i in range(PANCADA_PONTAS * 2):
		var ang := float(i) * TAU / float(PANCADA_PONTAS * 2) - PI * 0.5
		var longo := i % 2 == 0
		var variacao := 0.82 + 0.18 * sin(float(i) * 2.7)
		var raio := (330.0 if longo else 170.0) * variacao * escala
		fora.append(centro + Vector2.from_angle(ang) * raio)
		dentro.append(centro + Vector2.from_angle(ang) * raio * 0.72)
	Traco.poligono(canvas, fora, Color(Paleta.VERMELHO, some * 0.85))
	Traco.poligono(canvas, dentro, Color(cor, some * 0.95))
	canvas.draw_polyline(fora + PackedVector2Array([fora[0]]), Color(Paleta.CREME, some), 5.0, true)

static func _rachaduras(canvas: CanvasItem, centro: Vector2, t: float, some: float) -> void:
	for i in range(3):
		var ang := float(i) * TAU / 3.0 + 0.6
		var ponta := centro
		var caminho := PackedVector2Array([centro])
		for k in range(3):
			ponta += Vector2.from_angle(ang + sin(float(k) * 2.1 + float(i)) * 0.45) * 130.0
			caminho.append(ponta)
		canvas.draw_polyline(caminho, Color(Paleta.CREME, some * 0.8), lerpf(9.0, 2.0, t), true)

## O PALCO INTEIRO REAGE: raios dourados saindo das quatro bordas para
## dentro. Reservado ao lendário e ao perfeito, que são o motivo de a
## fila existir.
static func _palco_reage(canvas: CanvasItem, centro: Vector2, t: float, some: float) -> void:
	for i in range(14):
		var lado := i % 4
		var passo := (float(i) / 14.0 + t * 0.4)
		var origem := Vector2.ZERO
		match lado:
			0: origem = Vector2(fposmod(passo, 1.0) * 1080.0, -40.0)
			1: origem = Vector2(1120.0, fposmod(passo, 1.0) * 1920.0)
			2: origem = Vector2(fposmod(passo, 1.0) * 1080.0, 1960.0)
			_: origem = Vector2(-40.0, fposmod(passo, 1.0) * 1920.0)
		var direcao := (centro - origem).normalized()
		canvas.draw_line(
			origem, origem + direcao * lerpf(240.0, 900.0, t),
			Color(Paleta.AMBAR, some * 0.45), lerpf(10.0, 3.0, t), true
		)
