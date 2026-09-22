class_name PunchFX
extends RefCounted

## Partículas e ondas da tela — brasas, raios, faíscas, estilhaços e anéis.
##
## POR QUE FICA FORA DE `main.gd`. A tela desenha tudo à mão, num `_draw`
## só, e o resultado de um soco acende três coisas ao mesmo tempo: o que
## voa, o que treme e o que escreve. Misturar as três num arquivo faz
## qualquer ajuste de festa mexer no código que conta ponto — e ponto de
## arcade é dinheiro. Aqui mora só o que voa.
##
## ------------------------------------------------------------------
## POR QUE O CONFETE DESCIA TRAVADO — E O QUE MUDOU
##
## Duas causas, e as duas eram POR PARTÍCULA. Com novecentas no ar, tudo
## o que custa "um pouquinho" por partícula custa novecentas vezes.
##
## 1. CADA PARTÍCULA ERA UM `Dictionary`. Ler `p.posicao` não é ler um
##    campo: é uma busca em tabela de espalhamento, com a chave em texto.
##    São umas dez por partícula por quadro para mover, mais outras
##    tantas para desenhar — mais de um milhão de buscas por segundo na
##    hora da festa, que é exatamente a hora em que a tela já está mais
##    cheia. E cada `Dictionary` é um objeto contado por referência:
##    nascer e morrer novecentos deles por segundo dá trabalho ao coletor,
##    e trabalho do coletor aparece como um quadro que demora o dobro dos
##    vizinhos — o solavanco.
##
##    Agora são ARRAYS EMPACOTADOS, um por atributo (`PackedVector2Array`
##    de posições, `PackedFloat32Array` de vidas…). A partícula `i` é o
##    índice `i` de cada array. Não há objeto por partícula, não há chave
##    em texto, não há lixo para recolher: mover novecentas vira percorrer
##    um punhado de blocos de memória contígua.
##
## 2. CADA PARTÍCULA ERA UMA CHAMADA DE DESENHO. Novecentos `draw_line`
##    viram novecentos comandos que o motor ordena e manda para a placa de
##    vídeo um a um. É esse o custo que estoura numa GPU integrada, e é
##    por isso que o travamento aparecia na comemoração e não no resto do
##    jogo.
##
##    Agora TODO O CONFETE É UM DESENHO SÓ. As fitas viram triângulos num
##    `canvas_item_add_triangle_array`: um comando, com todos os vértices
##    e todas as cores dentro. O mesmo para brasas, faíscas e estilhaços.
##    A festa inteira passou de umas novecentas chamadas para três.
##
## O teto de partículas (`LIMITE`) continua existindo, mas agora é folga e
## não muleta: a conta cabe com sobra.

## Teto de partículas vivas. Passando disso, as mais antigas saem.
const LIMITE := 900

## Os tipos, como número e não como texto.
##
## Comparar textos por partícula, por quadro, para escolher o desenho é o
## mesmo custo escondido do `Dictionary` — e aqui o número ainda serve
## para AGRUPAR: as partículas são desenhadas por tipo, e é o agrupamento
## que permite um comando só para cada grupo.
enum Tipo { CONFETE, BRASA, RAIO, FAISCA, ESTILHACO, POEIRA }

## O VIGIA DO RITMO, ligado por quem cria o efeito.
##
## Cada função que solta partícula pergunta a ele quantas realmente
## soltar. Num PC que está dando conta, todas; num que não está, menos —
## e a queda acontece onde ninguém repara, em vez de aparecer como
## animação aos trancos, que é onde todo mundo repara.
var vigia: Desempenho = null

func _quantas(pedido: int) -> int:
	var ajustado := pedido if vigia == null else vigia.quantas(pedido)
	# Se o pool já está cheio, criar centenas apenas para expulsar outras
	# centenas no mesmo quadro é trabalho invisível e causa o engasgo no
	# auge do efeito. Só nasce o que realmente cabe.
	return mini(ajustado, maxi(0, LIMITE - _n))

# ------------------------------------------------------- as partículas
#
# UM ARRAY POR ATRIBUTO, e a partícula `i` é o índice `i` de todos eles.
# É mais trabalhoso de escrever e é a diferença entre a festa rodar lisa
# e a festa engasgar; ver o cabeçalho.
var _posicao := PackedVector2Array()
var _velocidade := PackedVector2Array()
var _cor := PackedColorArray()
var _vida := PackedFloat32Array()
var _vida_total := PackedFloat32Array()
var _tamanho := PackedFloat32Array()
var _giro := PackedFloat32Array()
var _giro_velocidade := PackedFloat32Array()
var _gravidade := PackedFloat32Array()
var _arrasto := PackedFloat32Array()
var _tipo := PackedInt32Array()
var _n := 0

var _ondas: Array = []

# Buffers de desenho, reaproveitados entre quadros. Recriá-los a cada
# quadro devolveria pela porta dos fundos o lixo que os arrays
# empacotados vieram eliminar.
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()
## AS COORDENADAS DE TEXTURA DO LOTE.
##
## POR QUE O CONFETE PARECIA ENRUGADO. Cada partícula era um
## quadrilátero de COR CHAPADA, sem textura: quatro quinas vivas e um
## miolo de cor sólida. Num monitor de perto isso passa; numa TV de
## cinquenta polegadas, onde cada pixel do jogo vira três ou quatro da
## tela, o que se vê é um retalho de papel com serrilha — e é exatamente
## a palavra que descreve o defeito.
##
## Com uma textura de borda macia e quatro UVs por partícula, o MESMO
## quadrilátero passa a ter contorno que se dissolve. Não custa vértice
## nenhum a mais, não custa chamada de desenho nenhuma a mais: custa um
## `PackedVector2Array` do mesmo tamanho do de posições e uma amarração
## de textura por lote. É a diferença entre confete recortado a tesoura
## e confete de verdade.
var _uv := PackedVector2Array()

## A TEXTURA DE BORDA MACIA, calculada uma vez no arranque.
##
## Não vem de arquivo: são 32 × 32 pixels calculados aqui, o que evita
## um PNG a mais no pacote e um `load` no meio da festa. O perfil é um
## PLANALTO com rampa nas bordas — cheio no miolo, zero na borda —, e
## não uma bola. A diferença importa porque o mesmo quadrilátero serve
## para coisas muito diferentes: numa fita longa e estreita, um perfil
## de bola apagaria o meio; o planalto deixa o corpo inteiro aceso e só
## dissolve as quinas.
static var _pincel: ImageTexture = null

static func _pincel_macio() -> ImageTexture:
	if _pincel != null:
		return _pincel
	const LADO := 32
	const RAMPA := 0.22
	var img := Image.create_empty(LADO, LADO, false, Image.FORMAT_RGBA8)
	for y in range(LADO):
		var v := (float(y) + 0.5) / float(LADO)
		for x in range(LADO):
			var u := (float(x) + 0.5) / float(LADO)
			var fu := clampf((0.5 - absf(u - 0.5)) / RAMPA, 0.0, 1.0)
			var fv := clampf((0.5 - absf(v - 0.5)) / RAMPA, 0.0, 1.0)
			var a := fu * fv
			# Suavização de Hermite: tira o vinco que uma rampa reta
			# deixa no ponto em que ela encontra o planalto.
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_pincel = ImageTexture.create_from_image(img)
	return _pincel


func limpar() -> void:
	_n = 0
	_ondas.clear()


func vivo() -> bool:
	return _n > 0 or not _ondas.is_empty()


## Quantas partículas estão no ar. A Central mostra este número: quando a
## festa pesa, é ele que diz se o problema é quantidade ou outra coisa.
func quantidade() -> int:
	return _n


## A MORTE DE UMA PARTÍCULA É UMA TROCA COM A ÚLTIMA.
##
## Remover do meio de um array empurra tudo o que vem depois — com
## centenas morrendo por segundo, isso é copiar a lista inteira várias
## vezes por quadro. Trocando com a última e encurtando em um, a remoção
## custa o mesmo para qualquer posição. A ordem se embaralha, e para
## partículas isso não significa nada.
func _matar(i: int) -> void:
	var ultimo := _n - 1
	if i != ultimo:
		_posicao[i] = _posicao[ultimo]
		_velocidade[i] = _velocidade[ultimo]
		_cor[i] = _cor[ultimo]
		_vida[i] = _vida[ultimo]
		_vida_total[i] = _vida_total[ultimo]
		_tamanho[i] = _tamanho[ultimo]
		_giro[i] = _giro[ultimo]
		_giro_velocidade[i] = _giro_velocidade[ultimo]
		_gravidade[i] = _gravidade[ultimo]
		_arrasto[i] = _arrasto[ultimo]
		_tipo[i] = _tipo[ultimo]
	_n = ultimo


func atualizar(delta: float) -> void:
	var i := 0
	while i < _n:
		var vida := _vida[i] - delta
		if vida <= 0.0:
			_matar(i)
			continue
		_vida[i] = vida
		var vel := _velocidade[i]
		vel.y += _gravidade[i] * delta
		vel *= 1.0 - _arrasto[i] * delta
		_velocidade[i] = vel
		_posicao[i] += vel * delta
		_giro[i] += _giro_velocidade[i] * delta
		i += 1
	for k in range(_ondas.size() - 1, -1, -1):
		var o: Dictionary = _ondas[k]
		o.tempo += delta
		if o.tempo >= o.duracao:
			_ondas.remove_at(k)


# ----------------------------------------------------------- o desenho
#
# TUDO EM TRIÂNGULOS, E TODOS OS TRIÂNGULOS DE UM TIPO NUM COMANDO SÓ.
#
# `canvas_item_add_triangle_array` recebe vértices, cores e índices de uma
# vez. Um quadrilátero são dois triângulos; uma linha grossa é um
# quadrilátero. Então confete, brasa, faísca e estilhaço — que antes eram
# um `draw_line` ou um `draw_circle` cada — cabem todos na mesma lista, e
# a lista vai inteira numa chamada.

func desenhar(tela: CanvasItem) -> void:
	for o in _ondas:
		var t: float = o.tempo / o.duracao
		var raio: float = lerpf(o.raio_inicial, o.raio_final, ease(t, 0.35))
		var cor: Color = o.cor
		cor.a *= 1.0 - t
		Traco.arco(tela, o.centro, raio, cor, o.espessura * (1.0 - t * 0.7))
	if _n == 0:
		return
	var item := tela.get_canvas_item()
	_desenhar_fitas(item)
	_desenhar_riscos(item)
	_desenhar_formas(item, tela)


## Início do lote: os buffers voltam a ficar vazios sem devolver a
## memória ao sistema, para o quadro seguinte reaproveitá-la.
func _abrir_lote() -> void:
	_v.clear()
	_c.clear()
	_idx.clear()
	_uv.clear()


## Um quadrilátero, em dois triângulos, com a mesma cor nos quatro cantos.
func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, cor: Color) -> void:
	var base := _v.size()
	_v.push_back(a)
	_v.push_back(b)
	_v.push_back(c)
	_v.push_back(d)
	# Os quatro cantos da textura, na MESMA ordem dos quatro vértices.
	# Em `_risco`, U corre ao longo da fita e V atravessa a largura —
	# então a mesma textura dissolve as pontas de uma faísca e as quinas
	# de um quadradinho de poeira, sem código separado para cada um.
	_uv.push_back(Vector2(0.0, 0.0))
	_uv.push_back(Vector2(1.0, 0.0))
	_uv.push_back(Vector2(1.0, 1.0))
	_uv.push_back(Vector2(0.0, 1.0))
	for _k in range(4):
		_c.push_back(cor)
	_idx.push_back(base)
	_idx.push_back(base + 1)
	_idx.push_back(base + 2)
	_idx.push_back(base)
	_idx.push_back(base + 2)
	_idx.push_back(base + 3)


## Uma linha grossa vira um quadrilátero — é assim que o motor desenha
## `draw_line` por dentro, só que aqui todas vão juntas.
func _risco(de: Vector2, ate: Vector2, largura: float, cor: Color) -> void:
	var direcao := ate - de
	var comprimento := direcao.length()
	if comprimento < 0.0001:
		return
	var lado := Vector2(-direcao.y, direcao.x) / comprimento * (largura * 0.5)
	_quad(de + lado, ate + lado, ate - lado, de - lado, cor)


func _fechar_lote(item: RID) -> void:
	if _idx.is_empty():
		return
	# A TEXTURA ENTRA AQUI, no mesmo comando. Continua sendo UM desenho
	# por lote: o que muda é que agora ele tem contorno macio em vez de
	# quina viva.
	RenderingServer.canvas_item_add_triangle_array(
		item, _idx, _v, _c, _uv, PackedInt32Array(), PackedFloat32Array(),
		_pincel_macio().get_rid()
	)


func _cor_viva(i: int) -> Color:
	var cor := _cor[i]
	cor.a *= clampf(_vida[i] / maxf(_vida_total[i], 0.0001), 0.0, 1.0)
	return cor


## O CONFETE. Uma fita é um retângulo estreito girando; a largura muda com
## o giro para dar a impressão de papel virando de lado.
func _desenhar_fitas(item: RID) -> void:
	_abrir_lote()
	for i in range(_n):
		if _tipo[i] != Tipo.CONFETE:
			continue
		var giro := _giro[i]
		var direcao := Vector2.from_angle(giro * 0.35)
		var metade := _tamanho[i] * 1.65
		var largura: float = maxf(1.2, _tamanho[i] * (0.20 + 0.80 * absf(cos(giro))))
		_risco(_posicao[i] - direcao * metade, _posicao[i] + direcao * metade, largura, _cor_viva(i))
	_fechar_lote(item)


## BRASA, FAÍSCA E POEIRA: tudo o que é um risco na direção do voo.
##
## A brasa ganhava três desenhos (rastro frio, corpo quente e uma bola
## branca na cabeça) e é a partícula mais numerosa do impacto. Aqui os
## três continuam existindo — são três quadriláteros —, mas somem dentro
## do mesmo comando das outras.
func _desenhar_riscos(item: RID) -> void:
	_abrir_lote()
	for i in range(_n):
		var tipo := _tipo[i]
		if tipo != Tipo.BRASA and tipo != Tipo.FAISCA and tipo != Tipo.POEIRA:
			continue
		var cor := _cor_viva(i)
		var pos := _posicao[i]
		var vel := _velocidade[i]
		var tam := _tamanho[i]
		if tipo == Tipo.POEIRA:
			# Poeira é um borrãozinho: um quadrado girado 45° custa dois
			# triângulos e lê como pontinho redondo em movimento.
			_quad(
				pos + Vector2(0, -tam), pos + Vector2(tam, 0),
				pos + Vector2(0, tam), pos + Vector2(-tam, 0), cor
			)
			continue
		var comprimento := vel.length()
		if comprimento < 0.0001:
			continue
		var unidade := vel / comprimento
		if tipo == Tipo.FAISCA:
			_risco(pos - unidade * tam * 3.5, pos, maxf(1.5, tam * 0.6), cor)
			continue
		# BRASA: rastro frio longo, corpo quente curto e a cabeça branca.
		var rastro: float = clampf(comprimento * 0.045, 10.0, 90.0)
		var frio := cor
		frio.a *= 0.25
		_risco(pos - unidade * rastro, pos, tam * 0.7, frio)
		_risco(pos - unidade * rastro * 0.35, pos, tam, cor)
		var r2 := tam * 0.7
		_quad(
			pos + Vector2(-r2, -r2), pos + Vector2(r2, -r2),
			pos + Vector2(r2, r2), pos + Vector2(-r2, r2),
			Color(1, 1, 1, cor.a * 0.85)
		)
	_fechar_lote(item)


## ESTILHAÇO em lote; o RAIO, que é côncavo, continua por fora.
func _desenhar_formas(item: RID, tela: CanvasItem) -> void:
	_abrir_lote()
	for i in range(_n):
		if _tipo[i] != Tipo.ESTILHACO:
			continue
		var pos := _posicao[i]
		var tam := _tamanho[i]
		var g := _giro[i]
		var base := _v.size()
		_v.push_back(pos + Vector2(0, -tam).rotated(g))
		_v.push_back(pos + Vector2(tam, tam * 0.6).rotated(g))
		_v.push_back(pos + Vector2(-tam * 0.8, tam).rotated(g))
		# O ESTILHAÇO É UM TRIÂNGULO, e não um quadrilátero — mas o lote
		# é um só e todo vértice precisa da sua coordenada de textura,
		# senão os arrays saem de tamanhos diferentes e o comando é
		# recusado inteiro. Os três cantos pegam o miolo do pincel, que é
		# opaco: o estilhaço continua sólido, como tem de ser.
		_uv.push_back(Vector2(0.5, 0.5))
		_uv.push_back(Vector2(0.5, 0.5))
		_uv.push_back(Vector2(0.5, 0.5))
		var cor := _cor_viva(i)
		for _k in range(3):
			_c.push_back(cor)
		_idx.push_back(base)
		_idx.push_back(base + 1)
		_idx.push_back(base + 2)
	_fechar_lote(item)
	# O raio tem seis pontas e é côncavo: triangular à mão daria mais
	# código do que vale por umas poucas dezenas deles. `Traco.poligono`
	# continua servindo, e são os únicos que ainda custam um desenho cada.
	for i in range(_n):
		if _tipo[i] != Tipo.RAIO:
			continue
		Traco.poligono(
			tela, _forma_de_raio(_posicao[i], _tamanho[i], _giro[i]), _cor_viva(i)
		)


## O contorno de um raio de seis pontas, na escala e no giro pedidos.
static func _forma_de_raio(centro: Vector2, tamanho: float, giro: float) -> PackedVector2Array:
	const MOLDE := [
		Vector2(0.10, -1.00), Vector2(-0.55, 0.10), Vector2(-0.10, 0.10),
		Vector2(-0.20, 1.00), Vector2(0.55, -0.15), Vector2(0.08, -0.15),
	]
	var pontos := PackedVector2Array()
	for ponto in MOLDE:
		pontos.append(centro + (ponto as Vector2).rotated(giro) * tamanho)
	return pontos


# ------------------------------------------------------- o nascimento
func _nascer(
	tipo: Tipo, posicao: Vector2, velocidade: Vector2, cor: Color, vida: float,
	tamanho: float, gravidade: float, arrasto: float,
	giro := 0.0, giro_velocidade := 0.0
) -> void:
	if _n >= LIMITE:
		# Cheio: uma cede o lugar. Com a troca-com-a-última do `_matar`, a
		# posição 0 não é exatamente a mais antiga — e não precisa ser. O
		# que importa é o teto ser respeitado sem custo.
		_matar(0)
	var i := _n
	_n += 1
	if _posicao.size() <= i:
		# Os arrays crescem até o teto e param. Depois disso o espaço é
		# sempre reaproveitado: nenhuma alocação no meio da festa.
		_posicao.resize(i + 1)
		_velocidade.resize(i + 1)
		_cor.resize(i + 1)
		_vida.resize(i + 1)
		_vida_total.resize(i + 1)
		_tamanho.resize(i + 1)
		_giro.resize(i + 1)
		_giro_velocidade.resize(i + 1)
		_gravidade.resize(i + 1)
		_arrasto.resize(i + 1)
		_tipo.resize(i + 1)
	_posicao[i] = posicao
	_velocidade[i] = velocidade
	_cor[i] = cor
	_vida[i] = vida
	_vida_total[i] = vida
	_tamanho[i] = tamanho
	_gravidade[i] = gravidade
	_arrasto[i] = arrasto
	_giro[i] = giro
	_giro_velocidade[i] = giro_velocidade
	_tipo[i] = tipo


func onda(centro: Vector2, raio_inicial: float, raio_final: float, cor: Color, espessura: float = 8.0, duracao: float = 0.7) -> void:
	_ondas.append({
		"centro": centro,
		"raio_inicial": raio_inicial,
		"raio_final": raio_final,
		"cor": cor,
		"espessura": espessura,
		"duracao": maxf(0.05, duracao),
		"tempo": 0.0,
	})


func confete(centro: Vector2, quantidade: int, cores: Array, forca: float = 900.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(-PI, 0.0)
		_nascer(
			Tipo.CONFETE,
			centro + Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0)),
			Vector2(cos(angulo), sin(angulo)) * randf_range(forca * 0.35, forca),
			cores[randi() % cores.size()],
			randf_range(1.6, 3.1),
			randf_range(5.0, 11.0),
			randf_range(760.0, 1150.0),
			0.9,
			randf_range(0.0, TAU),
			randf_range(-9.0, 9.0)
		)


## Chuva distribuída pela tela, usada na premiação. Nasce em várias alturas
## para a festa já aparecer cheia sem despejar todas as partículas no mesmo
## quadro visual. A quantidade passa pelo vigia de desempenho normalmente.
func chuva_de_confete(largura: float, quantidade: int, cores: Array, intensidade := 1.0) -> void:
	var escala := clampf(intensidade, 0.35, 1.4)
	for i in range(_quantas(quantidade)):
		_nascer(
			Tipo.CONFETE,
			Vector2(randf_range(25.0, largura - 25.0), randf_range(-520.0, -20.0)),
			Vector2(randf_range(-120.0, 120.0), randf_range(260.0, 520.0) * escala),
			cores[randi() % cores.size()],
			randf_range(2.2, 3.8),
			randf_range(5.0, 10.0),
			randf_range(620.0, 980.0),
			0.42,
			randf_range(0.0, TAU),
			randf_range(-8.0, 8.0)
		)


## A CHUVA DE BRASAS, no lugar da chuva de confete.
##
## Cai mais rápido e mais reta do que o confete caía: confete plana no ar,
## e planar é o gesto de uma festa de aniversário. Brasa despenca.
func chuva_de_brasas(largura: float, quantidade: int, cores: Array) -> void:
	for i in range(_quantas(quantidade)):
		_nascer(
			Tipo.BRASA,
			Vector2(randf_range(0.0, largura), randf_range(-300.0, -20.0)),
			Vector2(randf_range(-40.0, 40.0), randf_range(520.0, 980.0)),
			cores[randi() % cores.size()],
			randf_range(1.6, 2.8),
			randf_range(3.0, 6.5),
			randf_range(420.0, 720.0),
			0.25
		)


## A EXPLOSÃO DO GOLPE: brasas para todo lado e alguns raios girando.
##
## Sai do ponto do impacto, e não do alto da tela, porque quem manda na
## comemoração é o soco — a origem tem de ser o lugar onde ele aterrissou.
func explosao(centro: Vector2, quantidade: int, cores: Array, forca: float = 1100.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		var direcao := Vector2(cos(angulo), sin(angulo))
		# Achatada na vertical: uma explosão redonda em tela alta some
		# pelas laterais antes de a pessoa ver.
		direcao.y *= 0.75
		_nascer(
			Tipo.BRASA,
			centro + direcao * randf_range(0.0, 70.0),
			direcao * randf_range(forca * 0.30, forca),
			cores[randi() % cores.size()],
			randf_range(0.9, 1.9),
			randf_range(3.0, 7.0),
			randf_range(520.0, 900.0),
			1.1
		)


## Raios saindo do ponto do soco, girando enquanto voam.
func raios(centro: Vector2, quantidade: int, cor: Color, forca: float = 780.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		_nascer(
			Tipo.RAIO,
			centro,
			Vector2(cos(angulo), sin(angulo) * 0.8) * randf_range(forca * 0.4, forca),
			cor,
			randf_range(0.8, 1.6),
			randf_range(16.0, 34.0),
			randf_range(420.0, 760.0),
			1.3,
			randf_range(0.0, TAU),
			randf_range(-7.0, 7.0)
		)


func faiscas(centro: Vector2, quantidade: int, cor: Color, forca: float = 1000.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		var tom := cor
		tom.a = randf_range(0.65, 1.0)
		_nascer(
			Tipo.FAISCA,
			centro,
			Vector2(cos(angulo), sin(angulo)) * randf_range(forca * 0.25, forca),
			tom,
			randf_range(0.45, 1.05),
			randf_range(2.0, 4.5),
			randf_range(240.0, 620.0),
			2.2
		)


func estilhacos(centro: Vector2, quantidade: int, cor: Color) -> void:
	## O que cai quando o soco foi fraco: pedaço escuro, pesado, sem brilho.
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(-PI * 0.85, -PI * 0.15)
		_nascer(
			Tipo.ESTILHACO,
			centro + Vector2(randf_range(-120.0, 120.0), randf_range(-40.0, 40.0)),
			Vector2(cos(angulo), sin(angulo)) * randf_range(140.0, 420.0),
			cor,
			randf_range(1.1, 2.0),
			randf_range(6.0, 15.0),
			randf_range(900.0, 1400.0),
			0.4,
			randf_range(0.0, TAU),
			randf_range(-5.0, 5.0)
		)


func poeira(centro: Vector2, quantidade: int, cor: Color, alcance: float = 420.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		var direcao := Vector2(cos(angulo), sin(angulo))
		_nascer(
			Tipo.POEIRA,
			centro + direcao * randf_range(0.0, 60.0),
			direcao * randf_range(alcance * 0.2, alcance),
			cor,
			randf_range(0.8, 1.8),
			randf_range(2.0, 6.0),
			-randf_range(20.0, 90.0),
			1.6
		)


func fogos(centro: Vector2, cores: Array) -> void:
	var cor: Color = cores[randi() % cores.size()]
	onda(centro, 6.0, randf_range(120.0, 210.0), Color(cor.r, cor.g, cor.b, 0.55), 5.0, 0.55)
	faiscas(centro, 46, cor, 780.0)
