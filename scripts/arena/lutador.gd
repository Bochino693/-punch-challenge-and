class_name Lutador3D
extends Node3D

## O ADVERSÁRIO — AGORA DESENHADO, E NÃO MODELADO.
##
## POR QUE O CORPO PROCEDURAL SAIU. Ele foi construído aqui mesmo, em
## GDScript: anéis torneados, músculo modelado, sombreador de desenho com
## brilho por material. Tecnicamente funcionava e custava onze chamadas
## de desenho. Visualmente não chegou nunca onde precisava: a queixa
## final foi "grosso, cabelo mal definido, sem profundidade, o antebraço
## parece colado ao tórax" — e as quatro estavam certas. Geometria feita
## de elipsoides somados tem um teto de qualidade, e esse teto fica bem
## abaixo de uma ilustração.
##
## O QUE ENTROU NO LUGAR. Uma folha de nove poses desenhadas
## (`assets/personagem/sprites/lutador_folha_3x3.png`), montadas num
## `AnimatedSprite3D` DENTRO da arena 3D — e não numa camada 2D por
## cima. A diferença importa: assim o lutador continua no ringue, com a
## perspectiva real, a câmera que recua no impacto, o tremor, as
## partículas de suor e poeira, a luz ciano e magenta e o enquadramento
## do nocaute. Nada disso precisou ser reescrito.
##
## E AS NOVE POSES SÃO POSES, NÃO ANIMAÇÕES. Cada papel tem UM desenho.
## O que transforma nove desenhos parados num lutador que se mexe é o
## MOVIMENTO PROCEDURAL desta página: o recuo do corpo no impacto, a
## inclinação, o balanço da respiração, o cambaleio, o tombo e a volta.
## É a mesma técnica de um jogo de luta 2D clássico — poucos quadros,
## muita física por cima —, e é ela que faz um soco leve e um soco que
## derruba parecerem coisas diferentes mesmo quando a ilustração de
## fundo é a mesma.

const FOLHA := "res://assets/personagem/sprites/lutador_sprite_frames.tres"

const DANO_POR_GOLPE := 0.62
const DANO_MINIMO := 0.02
const TEMPO_NA_LONA := 3.35
const TEMPO_LEVANTAR := 1.25

## OS PAPÉIS QUE SE REPETEM ENQUANTO NADA ACONTECE. Todo o resto é um
## gesto com começo e fim, e repetir um gesto desses seria o tique
## nervoso que uma máquina de salão não pode ter.
const PAPEIS_CONTINUOS := ["idle", "guard"]

## OS NOVE PAPÉIS DO JOGO, E QUAL DESENHO CADA UM USA.
##
## Nove papéis e nove desenhos, mas a correspondência não é um para um —
## e é de propósito. `hit_light` e `hit_medium` partilham a mesma
## ilustração porque a diferença entre um e outro não está no DESENHO,
## está no quanto o corpo recua e em quanto tempo ele volta. Já o
## desdém usa os dois socos da folha, alternados: o adversário devolve
## um jab e um direto no ar, que é a coisa mais próxima de "nem senti"
## que se pode dizer sem texto.
const PAPEIS := {
	"idle": {"quadros": ["idle", "guarda"], "ciclo": 1.05},
	"guard": {"quadros": ["guarda", "preparado"], "ciclo": 0.72},
	"taunt_weak": {"quadros": ["jab", "direto", "jab", "guarda"], "ciclo": 0.30},
	"hit_light": {"quadros": ["impacto_corpo"]},
	"hit_medium": {"quadros": ["impacto_corpo"]},
	"hit_heavy": {"quadros": ["impacto_forte"]},
	"stagger": {"quadros": ["impacto_forte", "impacto_corpo"], "ciclo": 0.42},
	"knockout": {"quadros": ["impacto_forte", "nocaute"], "ciclo": 0.22, "uma_vez": true},
	"get_up": {"quadros": ["recuperacao"]},
}

## OS ALIASES CONTINUAM, e não por nostalgia: eles são o contrato entre
## o jogo e o desenho. Quem quiser trocar a folha por outra arte sabe
## exatamente quais nomes precisa entregar.
const ALIASES := {
	"idle": ["idle"], "guard": ["guarda"], "taunt_weak": ["jab", "direto"],
	"hit_light": ["impacto_corpo"], "hit_medium": ["impacto_corpo"],
	"hit_heavy": ["impacto_forte"], "stagger": ["impacto_forte"],
	"knockout": ["nocaute"], "get_up": ["recuperacao"],
}

## QUANTO DURA CADA REAÇÃO, e por que agora é uma tabela de novo.
##
## Quando as reações eram animações de verdade, a duração saía do
## comprimento delas — uma tabela à mão não teria como acompanhar. Com
## poses desenhadas não há comprimento nenhum a medir: a duração É a
## decisão de direção, e é aqui que ela mora. A escada entre elas é o
## que faz a nota na tela e a reação do corpo contarem a mesma história.
const DURACAO := {
	"taunt_weak": 1.20, "stagger": 1.30, "hit_heavy": 0.95,
	"hit_medium": 0.70, "hit_light": 0.46,
}

## A FORÇA DO RECUO DE CADA REAÇÃO: quanto o corpo anda para trás (m),
## quanto ele tomba (rad) e quanto ele afunda (m). É esta tabela, e não
## o desenho, que separa um golpe de 3.000 de um de 9.000.
const RECUO := {
	"taunt_weak": {"tras": 0.00, "tombo": 0.00, "lado": 0.06},
	"hit_light": {"tras": 0.10, "tombo": 0.05, "lado": 0.04},
	"hit_medium": {"tras": 0.22, "tombo": 0.10, "lado": 0.08},
	"hit_heavy": {"tras": 0.36, "tombo": 0.16, "lado": 0.12},
	"stagger": {"tras": 0.52, "tombo": 0.24, "lado": 0.22},
}

## ------------------------------------------------------------ o tamanho
##
## ESTES NÚMEROS FORAM MEDIDOS NA FOLHA, E NÃO ESTIMADOS.
##
## A versão anterior dizia "a figura ocupa cerca de 86% dos 426 px" e
## tirava daí um quadro de 2,09 m. Não ocupa: medindo o alfa da folha,
## pose por pose, a figura em pé ocupa 99,5% do quadro. Com a conta
## antiga o lutador saía com mais de 2 m de altura em vez de 1,80, e era
## esse excesso que estourava o enquadramento. A câmera foi sendo
## afastada três vezes para compensar um erro de escala.
##
## A LINHA DO CHÃO É A BORDA DE BAIXO DO QUADRO, e isto custou três
## tentativas para ser entendido.
##
## O lutador está em guarda, com um pé à frente do outro. No desenho, o
## pé DE TRÁS aparece mais ALTO — é perspectiva, o chão sobe na tela
## conforme se afasta — e o pé DA FRENTE encosta na borda de baixo da
## célula. Medindo só a metade esquerda da folha, encontrava-se o pé de
## trás, na linha 418, e era ele que estava sendo pousado no tapete.
## Resultado: a bota da FRENTE, oito pixels mais baixa, ficava enterrada
## no tapete e aparecia decepada. Foi o corte que sobreviveu a todas as
## correções anteriores, porque a régua é que estava errada.
##
## A régua certa é simples: a figura encosta no chão pelo PONTO MAIS
## BAIXO dela, que é a última linha com tinta da célula. As duas botas
## estão inteiras na arte; o que faltava era pousar a certa.
##
## `tools/medir_folha.gd` imprime estas linhas para qualquer folha, e
## `tests/test_folha_lutador.gd` reprova a build se a folha do disco
## deixar de bater com o que está declarado aqui.
const ALTURA_DA_FOLHA := 426.0
## A linha mais alta com tinta nas poses em pé (`guarda`, `idle`).
const TOPO_DA_CABECA_PX := 2.0
## A ÚLTIMA LINHA COM TINTA das poses em pé — a sola do pé DA FRENTE,
## que é o ponto mais baixo da figura e o que encosta na lona.
const SOLA_DO_PE_PX := 425.0
## Quanto o lutador mede no ringue, do topo da cabeça à sola.
const ALTURA_DA_FIGURA := 1.80

## A SOLA É A BORDA DE BAIXO DA ÚLTIMA LINHA, E NÃO A LINHA.
##
## Uma linha de textura OCUPA UM INTERVALO, não é um ponto. Num
## `AnimatedSprite3D` centrado, a linha `r` vai de `v = r` (borda de
## cima) a `v = r + 1` (borda de baixo). `SOLA_DO_PE_PX` é a última
## linha COM TINTA; o chão encosta na borda de baixo dela, que fica um
## pixel adiante.
##
## Errar isto por um pixel não some: deixa a última linha da bota
## ATRAVESSADA pelo tapete, metade acima e metade abaixo. E como o
## tapete é desenhado na frente do desenho, o que se vê é um corte reto
## no meio da bota — a "linha invisível". Um pixel da folha, quatro
## milímetros no ringue, e é o bastante.
##
## Com a sola na última linha da célula, esta conta dá exatamente a
## borda de baixo do quadro: o desenho INTEIRO fica acima do tapete e
## nada mais depende de o tapete esconder coisa nenhuma.
const SOLA_NO_QUADRO_PX := SOLA_DO_PE_PX + 1.0

## O tamanho do pixel no mundo sai da figura medida, não do quadro
## inteiro — é a única forma de o lutador medir de fato 1,80 m.
const PIXEL_NO_MUNDO := ALTURA_DA_FIGURA / (SOLA_DO_PE_PX - TOPO_DA_CABECA_PX + 1.0)
## O quadro inteiro (os 426 px) convertido para metros. Continua público
## porque a câmera e os testes precisam dele.
const ALTURA_DO_QUADRO := ALTURA_DA_FOLHA * PIXEL_NO_MUNDO

## ------------------------------------------------------- a base dos pés
##
## QUANTO O DESENHO SE ABRE NO CHÃO, medido na faixa dos pés (linhas 395
## a 425) de todas as poses: o ponto mais distante do centro da célula
## está a 165 px, na pose `direto`, que é a mais aberta. Em metros, a
## base do lutador tem 1,42 m de ponta a ponta.
##
## ISTO NÃO É DECORAÇÃO: é o número que decide quanto o corpo pode
## inclinar. Um desenho é RÍGIDO — inclinar a figura de um ângulo φ
## levanta um pé e ENTERRA O OUTRO em `meia_base × sen φ`. Com a base de
## 71 cm que esta arte tem, o balanço lateral de 0,18 rad que o cambaleio
## usava afundava um pé 12,7 cm dentro da lona, e a lona o cortava. Era
## isso que se via no movimento: o pé descendo e sumindo.
const MEIA_BASE_PX := 165.0
const MEIA_BASE_DOS_PES := PIXEL_NO_MUNDO * MEIA_BASE_PX

## A LINHA MAIS BAIXA COM TINTA DE CADA POSE, medida na folha.
##
## Nem toda pose encosta no chão. As seis de pé vão até a última linha
## da célula (425), mas `impacto_forte` para na 413, `nocaute` — que é
## um corpo DEITADO, largo e baixo — para na 375 e `recuperacao` na 392.
##
## Isto não é curiosidade: é o que permite a regra única lá embaixo —
## NENHUMA PARTE DO DESENHO PASSA ABAIXO DA LONA, em pose nenhuma, em
## instante nenhum. Sem a tabela, o tombo do nocaute afundava o corpo 34
## cm sem saber que o desenho dele já começa 21 cm acima do chão, e o
## que sobrava ia parar embaixo do tapete.
const BASE_DA_POSE := {
	"guarda": 425.0, "idle": 425.0, "preparado": 425.0,
	"jab": 425.0, "direto": 425.0, "impacto_corpo": 425.0,
	"impacto_forte": 413.0, "nocaute": 375.0, "recuperacao": 392.0,
}

## Quanto um pé pode SAIR da lona no cambaleio, em metros.
##
## Escolhe-se o levantar, e o ângulo é consequência — o contrário do que
## estava aqui, que escolhia o ângulo e descobria o afundamento depois.
## Com a sola presa na lona (ver `_com_os_pes_na_lona`), o pé de trás
## sobe o dobro do que o de frente afundaria, então é este número, e não
## o ângulo, que diz o que se vai ver.
const PE_LEVANTA_NO_CAMBALEIO := 0.10

var _figura: AnimatedSprite3D = null
var _corpo: Node3D = null
var _frames: SpriteFrames = null
var _descanso := Transform3D.IDENTITY

var _relogio := 0.0
var _papel := "idle"
var _tempo_no_papel := 0.0
var _tempo_reacao := 0.0
var _recuo := 0.0
var _forca_do_recuo := 0.0
var _lado := 1.0
var _tempo_na_lona := 0.0
var _levantando := false
var _caindo := false
var _clarao := 0.0

var queda := 0.0
var dano := 0.0
var em_guarda := false

# ====================================================================
# MONTAGEM
# ====================================================================

## Monta o lutador. `_ignorado` existe só para quem ainda chama com o
## corpo antigo no braço; a folha é encontrada sozinha.
func montar(_ignorado: Variant = null) -> void:
	_frames = load(FOLHA) as SpriteFrames
	_corpo = Node3D.new()
	_corpo.name = "Corpo"
	add_child(_corpo)
	_figura = AnimatedSprite3D.new()
	_figura.name = "Figura"
	_figura.sprite_frames = _frames
	# O DESENHO JÁ VEM ILUMINADO. Deixar as luzes da arena baterem nele
	# seria iluminar duas vezes: a sombra pintada na ilustração brigaria
	# com a sombra calculada, e o resultado é o cinza chapado que
	# aparece sempre que se acende luz em cima de arte já sombreada.
	_figura.shaded = false
	_figura.double_sided = false
	# BILHETE FIXO, E NÃO VIRADO PARA A CÂMERA. Um cartaz que gira para
	# acompanhar o olho parece um corpo que se vira sozinho — e no
	# nocaute, com a câmera descendo, o lutador caído "levantaria" para
	# continuar encarando. O passeio lateral da câmera é de quatro graus;
	# um plano parado aguenta isso sem aparecer.
	_figura.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# O RECORTE É POR LIMIAR BAIXO. Alto demais come o halo ciano e
	# magenta que a arte tem na borda — que é justamente o que recorta o
	# lutador contra o fundo escuro. Baixo demais deixa entrar o quadrado
	# quase transparente da folha.
	_figura.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_figura.alpha_scissor_threshold = 0.04
	# FILTRO LINEAR, SEM MIPMAP — porque a folha é importada SEM mipmaps
	# (`mipmaps/generate=false`). Pedir um filtro de mipmap a uma textura
	# que não tem nenhum é uma incoerência que, dependendo do driver, vai
	# de inofensiva a textura incompleta. E não se perde nada: o desenho
	# aqui é sempre AMPLIADO, nunca reduzido, e mipmap só serve para
	# redução.
	_figura.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# ------------------------------------------------------------------
	# O DESENHO NÃO É TESTADO CONTRA A PROFUNDIDADE. NADA PODE CORTÁ-LO.
	#
	# Esta é a única forma de cumprir "a imagem completa, sem cortes"
	# sem depender de o desenho estar meio pixel acima ou abaixo de um
	# plano. Três correções seguidas tentaram acertar essa distância —
	# o miolo levantado da lona, a borda do texel, a altura da sombra —
	# e a cada uma sobrava um fio de corte, porque o problema não era o
	# número: era haver um plano com poder de cortar o lutador.
	#
	# Não há nada na arena que DEVA passar à frente dele. As cordas da
	# frente não são desenhadas de propósito, os postes da frente ficam
	# fora do enquadramento, e o tapete está embaixo. Desligar o teste
	# resolve a classe inteira do problema em vez de mais um caso dela.
	#
	# E é seguro porque a regra de `_com_o_desenho_na_lona` garante o
	# outro lado: nenhuma parte do desenho fica abaixo do tapete, então
	# não há nada que "deveria" estar escondido e passaria a aparecer.
	_figura.no_depth_test = true
	_figura.pixel_size = PIXEL_NO_MUNDO
	# A BORDA DE BAIXO DA BOTA DA FRENTE ENCOSTA EM y = 0, QUE É O CHÃO.
	#
	# O sprite é centrado, então o meio do quadro cai na linha 213. Subir
	# o desenho pela distância entre essa linha e a BORDA DE BAIXO da
	# sola (ver `SOLA_NO_QUADRO_PX`) põe o ponto mais baixo da figura em
	# cima do chão — e, como esse ponto é a última linha da célula, põe o
	# DESENHO INTEIRO acima do chão.
	#
	# É o que faz a imagem aparecer completa: nenhuma parte dela fica
	# abaixo do plano do tapete, então não há nada que o tapete possa
	# cortar. O pé de trás fica alguns pixels acima da linha do chão, que
	# é onde a perspectiva do desenho o coloca — é assim que um corpo de
	# lado pisa num chão que recua.
	_figura.position = Vector3(
		0.0, PIXEL_NO_MUNDO * (SOLA_NO_QUADRO_PX - ALTURA_DA_FOLHA * 0.5), 0.0
	)
	_corpo.add_child(_figura)
	_descanso = _corpo.transform
	_tocar("idle")

## O lutador está completo quando os nove papéis acham desenho na folha.
func completo() -> bool:
	if _frames == null:
		return false
	for papel in PAPEIS:
		for nome in (PAPEIS[papel]["quadros"] as Array):
			if not _frames.has_animation(StringName(str(nome))):
				return false
	return true

func animacoes_disponiveis() -> PackedStringArray:
	var nomes := PackedStringArray()
	for papel in PAPEIS:
		nomes.append(str(papel))
	return nomes

func tem_esqueleto() -> bool:
	return false

# ====================================================================
# O QUE O JOGO PEDE
# ====================================================================

func preparar() -> void:
	dano = 0.0
	queda = 0.0
	_caindo = false
	_levantando = false
	_recuo = 0.0
	_tempo_reacao = 0.0
	_tempo_na_lona = 0.0
	_clarao = 0.0
	em_guarda = false
	if _corpo != null:
		_corpo.transform = _descanso
	_tocar("idle")

func guardar(ativo: bool) -> void:
	em_guarda = ativo
	if _caindo:
		return
	_tocar("guard" if ativo else "idle")

func bater(forca: float, derruba := false, pontos := -1) -> Dictionary:
	var f := clampf(forca, 0.0, 1.0)
	_recuo = 1.0
	_forca_do_recuo = f
	# Alternar o lado mantém variedade sem depender de aleatoriedade: duas
	# máquinas com o mesmo golpe exibem a mesma reação.
	_lado *= -1.0
	_clarao = 1.0
	var antes := dano
	if f > DANO_MINIMO:
		dano = clampf(dano + f * DANO_POR_GOLPE, 0.0, 1.0)
	var nocaute := not _caindo and (derruba or (dano >= 1.0 and antes < 1.0))
	var papel := ""
	var desdenhou := false
	if nocaute:
		papel = "knockout"
		_caindo = true
		_levantando = false
		_tempo_na_lona = 0.0
		_tempo_reacao = TEMPO_NA_LONA + TEMPO_LEVANTAR
		_tocar("knockout")
	elif not _caindo:
		# A nota é a linguagem do jogador. Abaixo de 6.000 o adversário
		# entende que o golpe foi fraco e desdenha, mesmo que a
		# calibração física tenha registrado algum movimento. Na lona ele
		# nunca faz isso: um nocaute não pode virar deboche.
		papel = reacao_para_pontos(pontos, f)
		desdenhou = papel == "taunt_weak" and pontos >= 0 and pontos < 6000
		_tempo_reacao = float(DURACAO.get(papel, 0.8))
		_tocar(papel)
	return {"nocaute": nocaute, "dano": dano, "reacao": papel, "desdenhou": desdenhou}

static func reacao_para_pontos(pontos: int, forca: float) -> String:
	if pontos >= 0 and pontos < 6000:
		return "taunt_weak"
	var reacao := reacao_para_forca(forca)
	# Depois do corte competitivo, no mínimo reconhece o golpe. Isso evita
	# que uma calibração conservadora contradiga os pontos na tela.
	if pontos >= 6000 and reacao == "taunt_weak":
		return "hit_light"
	return reacao

static func reacao_para_forca(forca: float) -> String:
	var f := clampf(forca, 0.0, 1.0)
	if f >= 0.82:
		return "stagger"
	if f >= 0.62:
		return "hit_heavy"
	if f >= 0.38:
		return "hit_medium"
	if f >= 0.18:
		return "hit_light"
	return "taunt_weak"

## O clarão do soco, empurrado pela arena. Ele acende a ilustração
## inteira por um instante — é o mesmo gesto que o resto da tela faz, e
## sem ele o corpo continuaria calmo enquanto tudo em volta explode.
func clarao(valor: float) -> void:
	_clarao = maxf(_clarao, clampf(valor, 0.0, 1.0))

func atualizar(delta: float) -> void:
	if _figura == null:
		return
	_relogio += delta
	_tempo_no_papel += delta
	_recuo = maxf(0.0, _recuo - delta * 2.1)
	_clarao = maxf(0.0, _clarao - delta * 3.4)
	_tempo_reacao = maxf(0.0, _tempo_reacao - delta)

	if _caindo:
		_tempo_na_lona += delta
		queda = minf(1.0, queda + delta * 2.8)
		if _tempo_na_lona >= TEMPO_NA_LONA and not _levantando:
			_levantando = true
			_tocar("get_up")
		if _levantando:
			# A CÂMERA SOBE NO MESMO COMPASSO EM QUE ELE LEVANTA. Com o
			# tempo chutado, ela chegava em pé antes ou depois dele.
			queda = maxf(0.0, 1.0 - (_tempo_na_lona - TEMPO_NA_LONA) / TEMPO_LEVANTAR)
		if _tempo_na_lona >= TEMPO_NA_LONA + TEMPO_LEVANTAR:
			_caindo = false
			_levantando = false
			queda = 0.0
			dano = minf(dano, 0.72)
			_tocar("guard" if em_guarda else "idle")
	elif _tempo_reacao <= 0.0 and not (_papel in PAPEIS_CONTINUOS):
		_tocar("guard" if em_guarda else "idle")

	_avancar_o_quadro()
	_mover_o_corpo()
	_pintar()

# ====================================================================
# O MOVIMENTO, QUE É O QUE TRANSFORMA NOVE DESENHOS NUM LUTADOR
# ====================================================================

func _tocar(papel: String) -> void:
	if not PAPEIS.has(papel):
		papel = "idle"
	if _papel == papel:
		return
	_papel = papel
	_tempo_no_papel = 0.0
	_mostrar(0)

## QUAL DESENHO MOSTRAR AGORA.
##
## Papéis contínuos (respiração, guarda) trocam de quadro em ciclo, e é
## essa troca — dois desenhos ligeiramente diferentes alternando devagar
## — que faz o adversário parecer vivo parado no lugar. Gestos com
## começo e fim andam UMA vez pela lista e param no último quadro, que é
## onde a pose termina.
func _avancar_o_quadro() -> void:
	var receita: Dictionary = PAPEIS[_papel]
	var lista: Array = receita["quadros"]
	if lista.size() <= 1:
		_mostrar(0)
		return
	var ciclo := float(receita.get("ciclo", 0.5))
	var passo := int(_tempo_no_papel / maxf(ciclo, 0.01))
	if bool(receita.get("uma_vez", false)) or not (_papel in PAPEIS_CONTINUOS):
		_mostrar(mini(passo, lista.size() - 1))
	else:
		_mostrar(passo % lista.size())

func _mostrar(indice: int) -> void:
	var lista: Array = PAPEIS[_papel]["quadros"]
	var nome := StringName(str(lista[clampi(indice, 0, lista.size() - 1)]))
	if _figura.animation != nome and _frames != null and _frames.has_animation(nome):
		_figura.animation = nome

## O CORPO INTEIRO SE MEXE, e é daqui que vem a sensação de peso.
##
## Três coisas somadas, todas em cima da pose parada:
##
##   a RESPIRAÇÃO, um balanço de um centímetro e meio que nunca para —
##   sem ela o desenho denuncia que é um desenho no primeiro segundo;
##   o RECUO do golpe, que anda para trás, tomba e desliza para o lado
##   conforme a tabela `RECUO`, e volta com uma curva que sai depressa e
##   assenta devagar, que é como um corpo que levou um soco se recompõe;
##   o TOMBO, que desce o corpo até a lona e o inclina, e é a única
##   coisa aqui que não volta sozinha — ela espera o `get_up`.
func _mover_o_corpo() -> void:
	var t := _descanso
	# A RESPIRAÇÃO SÓ SOBE, e essa é a correção menos visível e mais
	# constante desta página.
	#
	# Ela era um seno em torno de zero: METADE DE CADA CICLO puxava o
	# corpo dois centímetros PARA BAIXO da lona, e a lona — que fica na
	# frente do desenho — comia a sola durante essa metade. O pé
	# "piscava" contra a borda do tapete o tempo todo, parado, sem
	# ninguém bater. `(1 − cos)/2` tem o mesmo período e a mesma
	# amplitude, mas vai de 0 a 1: o corpo sobe e volta ao repouso, que é
	# exatamente onde a sola encosta no chão.
	var ar := (1.0 - cos(_relogio * 2.1)) * 0.007 + (1.0 - cos(_relogio * 0.7)) * 0.003
	t.origin.y += ar
	t.origin.x += sin(_relogio * 0.43) * 0.012

	# recuo do golpe
	var receita: Dictionary = RECUO.get(_papel, {})
	if not receita.is_empty() and _recuo > 0.001:
		var impacto := ease(_recuo, 0.35)
		t.origin.z -= float(receita["tras"]) * impacto * (0.55 + _forca_do_recuo * 0.65)
		t.origin.x += _lado * float(receita["lado"]) * impacto
		t.basis = t.basis.rotated(Vector3.RIGHT, -float(receita["tombo"]) * impacto)
		# O cambaleio balança de lado enquanto volta: é o que separa
		# "levou um soco" de "perdeu a base".
		if _papel == "stagger":
			t.origin.x += sin(_tempo_no_papel * 11.0) * 0.06 * impacto
			t.basis = t.basis.rotated(
				Vector3.FORWARD, _lado * giro_do_cambaleio() * impacto
			)

	# O TOMBO — e ele é MENOS do que parece necessário.
	#
	# Com um corpo modelado, derrubar exigia girar o corpo inteiro até a
	# horizontal. Com uma ilustração, o desenho do nocaute JÁ É um corpo
	# deitado: girá-lo de novo o deitaria duas vezes, e o que aparece é
	# um cartaz tombando de lado. O que falta ao desenho é só a QUEDA —
	# o corpo descendo até a lona —, e é só isso que esta conta faz.
	#
	# `ease(…, 0.55)` sai depressa e assenta: um corpo que cai ganha
	# velocidade e para de uma vez quando encontra o tapete.
	if queda > 0.001:
		var q := ease(clampf(queda, 0.0, 1.0), 0.55)
		t.origin.y -= 0.34 * q
		# Um repique curtíssimo no fim da descida: o corpo bate, sobe um
		# centímetro e assenta. É o detalhe que separa "caiu" de
		# "desapareceu para baixo".
		t.origin.y += sin(clampf((queda - 0.82) / 0.18, 0.0, 1.0) * PI) * 0.035

	# E A ÚLTIMA PALAVRA É SEMPRE ESTA, depois de tudo — respiração,
	# recuo, inclinação e tombo.
	t = _com_o_desenho_na_lona(t)
	_corpo.transform = t

## O ÂNGULO DO BALANÇO LATERAL DO CAMBALEIO.
##
## Sai do quanto se quer ver o pé levantar, e não o contrário. Com a
## sola presa na lona, inclinar de φ levanta o pé de trás em
## `2 × meia_base × sen φ`; invertendo, o ângulo é
## `asin(levantada / (2 × meia_base))`. Com a arte atual dá 4°, contra
## os 10° que estavam escritos à mão e enterravam o outro pé 13 cm.
static func giro_do_cambaleio() -> float:
	return asin(clampf(PE_LEVANTA_NO_CAMBALEIO / (2.0 * MEIA_BASE_DOS_PES), 0.0, 1.0))

## A ALTURA, NO CORPO, DA LINHA MAIS BAIXA COM TINTA DA POSE ATUAL.
##
## Zero para as poses de pé (elas chegam à última linha da célula) e
## positivo para as outras — o desenho do nocaute, por exemplo, começa
## 21 cm acima do chão, porque é um corpo deitado no meio do quadro.
func _fundo_do_desenho() -> float:
	var pose := String(_figura.animation) if _figura != null else "idle"
	var base := float(BASE_DA_POSE.get(pose, SOLA_DO_PE_PX))
	return PIXEL_NO_MUNDO * (SOLA_DO_PE_PX - base)

## A REGRA ÚNICA: NENHUMA PARTE DO DESENHO PASSA ABAIXO DA LONA.
##
## Por que uma trava e não números menores. Cada ajuste conserta o caso
## do dia e não impede o próximo de reabrir o mesmo buraco — e o buraco
## não é óbvio, porque não aparece como corpo enterrado: aparece como
## corpo CORTADO. Foi assim que a respiração afundava a sola metade do
## tempo, que o cambaleio enterrava um pé 13 cm e que o tombo do nocaute
## mandava 12 cm de desenho para debaixo do tapete, tudo sem ninguém
## conseguir apontar o quê.
##
## A trava mede os dois cantos da base da POSE ATUAL — não de uma base
## fixa — depois de toda a conta de movimento, e se o mais baixo passou
## do chão sobe o corpo exatamente o que faltava. Três consequências
## boas de graça:
##
##   o giro do cambaleio passa a pivotar no pé de baixo, que é o que um
##   corpo que perde a base faz;
##   a respiração vira um balanço que só sobe;
##   e o tombo do nocaute desce até o desenho ENCOSTAR na lona e para
##   ali, em vez de continuar até um número escrito à mão.
##
## É também o que torna seguro desligar o teste de profundidade do
## desenho: não há nada abaixo do tapete que devesse estar escondido.
func _com_o_desenho_na_lona(t: Transform3D) -> Transform3D:
	var fundo := _fundo_do_desenho()
	var esquerdo := t * Vector3(-MEIA_BASE_DOS_PES, fundo, 0.0)
	var direito := t * Vector3(MEIA_BASE_DOS_PES, fundo, 0.0)
	var mais_baixo := minf(esquerdo.y, direito.y)
	if mais_baixo < 0.0:
		t.origin.y -= mais_baixo
	return t

## A ALTURA DO PONTO MAIS BAIXO DO DESENHO. Nunca pode ser negativa —
## é o contrato que o teste confere, em qualquer pose e em qualquer
## instante.
func pe_mais_baixo() -> float:
	if _corpo == null:
		return 0.0
	var t := _corpo.transform
	var fundo := _fundo_do_desenho()
	return minf(
		(t * Vector3(-MEIA_BASE_DOS_PES, fundo, 0.0)).y,
		(t * Vector3(MEIA_BASE_DOS_PES, fundo, 0.0)).y
	)

## A COR DA ILUSTRAÇÃO responde a duas coisas: o clarão do soco, que
## acende tudo por um instante, e o dano acumulado, que puxa devagar
## para o vermelho. A segunda é quase imperceptível num golpe e evidente
## no quinto, que é exatamente o que ela precisa ser.
func _pintar() -> void:
	var castigo := clampf(dano, 0.0, 1.0)
	var cor := Color(1.0, 1.0 - castigo * 0.16, 1.0 - castigo * 0.22)
	var luz := clampf(_clarao, 0.0, 1.0)
	_figura.modulate = cor.lerp(Color(2.4, 2.2, 2.2), luz * 0.55)

## QUANTO O CORPO DESCEU EM DIREÇÃO À LONA, de 0 (em pé) a 1 (no chão).
##
## E NÃO "a altura da cabeça", que é o que estava aqui antes e era uma
## ficção. Num corpo modelado a cabeça tem uma posição no espaço e dá
## para medi-la; num DESENHO ela não tem — o plano continua em pé e o
## que muda é a ilustração pintada nele. Inventar uma coordenada para um
## osso que não existe é o tipo de medida que passa no teste e não
## corresponde a nada na tela.
##
## O que é real, e o que o jogo de fato promete, são duas coisas: o
## desenho exibido passa a ser o do nocaute, e o corpo desce até o
## tapete. É isso que esta função devolve.
func fundura_do_tombo() -> float:
	if _corpo == null:
		return 0.0
	# NORMALIZADA PELO QUANTO O DESENHO DO NOCAUTE PODE DESCER, e não
	# pelos 34 cm que o tombo PEDE. O desenho do nocaute é um corpo
	# deitado que começa 21 cm acima do chão; ele desce esses 21 cm e
	# encosta. Dividir pelo pedido dava 62% para um corpo que já estava
	# no tapete.
	var pode := PIXEL_NO_MUNDO * (SOLA_DO_PE_PX - float(BASE_DA_POSE["nocaute"]))
	return clampf(-_corpo.position.y / maxf(pode, 0.001), 0.0, 1.5)

## ONDE O CORPO ESTÁ AGORA em relação ao lugar de descanso.
##
## A arena precisa disto para a SOMBRA DE CONTATO: ela tem de andar com
## a respiração e com o recuo do golpe, senão o corpo desliza por cima
## de uma mancha parada e a sombra denuncia que é um adesivo. Quem
## pergunta é a arena; o lutador é quem sabe.
func deslocamento() -> Vector3:
	return _corpo.position if _corpo != null else Vector3.ZERO

## Qual desenho está na tela agora — o contrato que os testes conferem.
func desenho_atual() -> String:
	return String(_figura.animation) if _figura != null else ""
