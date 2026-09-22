class_name Ritmo
extends RefCounted

## O PASSO DO JOGO — E POR QUE ELE NÃO É MAIS O TEMPO DO QUADRO.
##
## A QUEIXA. "O movimento do personagem e do fundo não está natural."
## Isso não é a mesma coisa que "está lento", e é por isso que medir os
## quadros por segundo não resolvia: a máquina entregava sessenta quadros
## na média e o movimento continuava estranho.
##
## O QUE ACONTECE DE VERDADE. O relógio que o sistema devolve a cada
## quadro não é limpo. Mesmo numa máquina folgada ele chega assim:
##
##     16,7  16,7  18,2  15,1  16,7  17,9  15,5  16,7 …
##
## A soma está certa — o jogo não atrasa —, mas cada quadro ANDA UMA
## DISTÂNCIA DIFERENTE. Um objeto que atravessa a tela a velocidade
## constante pisa 16,7, depois 18,2, depois 15,1: no papel é um erro de
## um milissegundo e meio; no olho é trepidação, e é exatamente a palavra
## "não natural". Pior no fundo, onde há coisa se movendo devagar e em
## linha reta — que é o pior caso possível para esse erro.
##
## E QUANDO O VSYNC ENTRA, FICA PIOR. Com o vsync ligado, uma máquina que
## não fecha o quadro a tempo não passa a 55 quadros: passa a alternar
## 60, 30, 60, 30. O tempo do quadro pula entre 16,7 e 33,3 ms, o dobro,
## e é aí que o movimento vira solavanco de verdade. É o modo de falhar
## mais comum em PC fraco e é ele que a máquina do salão encontra.
##
## O QUE ESTE MÓDULO FAZ, em três passos e nessa ordem:
##
##   1. DESCARTA O QUE NÃO É UM QUADRO. Um quadro de meio segundo — a
##      primeira fonte sendo rasterizada, o sistema operacional
##      engasgando, a janela voltando do minimizado — não pode virar meio
##      segundo de jogo de uma vez, com a contagem saltando números e a
##      brasa se teletransportando. E o gêmeo esquecido dele, o quadro de
##      duração quase zero, não pode entrar na média e travar o relógio.
##      Nos dois casos o passo entregue é o último bom, e o resto é
##      jogado fora: o jogo não anda o que não foi desenhado.
##
##   2. ENCAIXA NO VSYNC. Se o quadro caiu a menos de 1 ms de um múltiplo
##      exato do intervalo de tela (16,67 / 33,33 / 50 / 66,67 ms a 60 Hz),
##      ele É esse múltiplo, e o ruído de medição some. Isto é o que
##      transforma a sequência lá de cima em 16,67 repetido.
##
##   3. SUAVIZA COM DÍVIDA LIMITADA. O que não encaixou entra numa média
##      curta. Média sozinha atrasaria o relógio do jogo para sempre, e
##      atraso é o defeito que a versão anterior tentava consertar — daí
##      a DÍVIDA: a diferença entre o tempo real e o tempo entregue é
##      guardada e devolvida aos poucos, um pedaço por quadro. O jogo
##      anda liso E chega na hora. É a diferença entre suavizar e mentir.
##
## O QUE ELE NÃO FAZ. Não mede desempenho e não corta efeito: quem faz
## isso é o `Desempenho`, e ele recebe o delta CRU, porque um vigia que
## olha para o tempo já suavizado não enxerga o engasgo que existe para
## combater. Os dois olham o mesmo quadro por ângulos diferentes, de
## propósito.

## Acima disto o quadro é um soluço, não um ritmo. Um quarto de segundo
## por quadro é 4 fps: nenhuma tela do jogo custa isso nem no pior
## aparelho, então quando aparece é sempre outra coisa.
const TETO_DO_SOLUCO := 0.25

## E ABAIXO DISTO TAMBÉM NÃO É UM QUADRO.
##
## O soluço tem um gêmeo que é fácil esquecer: o quadro de duração quase
## zero. Ele aparece quando o motor entrega dois avisos no mesmo instante,
## no primeiro quadro depois de carregar uma cena, ou quando o relógio do
## sistema dá um passo para trás. Um milissegundo é mil quadros por
## segundo — nenhuma tela existe.
##
## Se ele entra na média, estraga os dois lados de uma vez: puxa o passo
## para baixo naquele quadro E fica guardado na janela, contaminando os
## seguintes. Foi assim que um quadro de um centésimo de milissegundo
## deixou o relógio do jogo travado no piso do `clampf` — o jogo continua
## desenhando e nada mais se move, que é o pior defeito possível porque
## não parece defeito: parece a máquina ter travado.
const PISO_DO_QUADRO := 0.001

## O passo entregue nunca passa disto. Mesmo num aparelho que roda a 8
## quadros por segundo o jogo avança em fatias que ainda dá para desenhar.
const PASSO_MAXIMO := 0.10

## Quantos quadros entram na média. Seis é curto o bastante para
## acompanhar uma mudança real de carga em um décimo de segundo, e longo
## o bastante para apagar o chiado de medição.
const JANELA := 6

## A que distância de um múltiplo do vsync o quadro ainda conta como
## sendo aquele múltiplo. Um milissegundo: maior que o ruído típico do
## relógio, menor que a diferença entre dois múltiplos vizinhos.
const TOLERANCIA_DO_ENCAIXE := 0.0010

## Quanto da dívida é devolvido por quadro, em fração.
##
## Aqui há uma troca, e ela é o coração do módulo: devolver rápido demais
## faz a própria devolução virar a trepidação que se estava tirando;
## devolver devagar demais deixa o jogo andar atrasado por tempo demais.
## Um sétimo zera uma dívida de um quadro em cerca de treze quadros — um
## quinto de segundo —, o que é rápido para o relógio e lento para o
## olho, que é exatamente o que se quer.
const DEVOLUCAO := 0.14
## A dívida nunca passa de um quadro inteiro. Acima disso não é mais
## atraso a recuperar: é uma queda de desempenho, e essa o jogo aceita
## andando mais devagar, não correndo atrás.
const DIVIDA_MAXIMA := 0.020

var _tempos: Array[float] = []
var _soma := 0.0
var _ultimo_bom := 1.0 / 60.0
var _divida := 0.0
## O intervalo de um quadro de tela, em segundos. `_medir_tela` o
## descobre; 60 Hz é só o palpite inicial.
var _vsync := 1.0 / 60.0

## Quantos quadros do relógio da tela couberam no último passo. Serve
## para diagnóstico na Central: um número que fica pulando entre 1 e 2 é
## a assinatura exata do 60/30/60/30.
var quadros_de_tela := 1.0

func _init() -> void:
	medir_tela()

## O RELÓGIO DA TELA. Vem do sistema; quando ele não sabe responder — e
## num TV Box ele às vezes não sabe —, 60 Hz é o palpite que erra menos.
func medir_tela() -> void:
	var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	if hz > 20.0 and hz < 400.0:
		_vsync = 1.0 / hz
	else:
		_vsync = 1.0 / 60.0

## O PASSO QUE O JOGO DEVE ANDAR NESTE QUADRO.
func passo(delta: float) -> float:
	# 1. O QUE NÃO É UM QUADRO. Nos dois extremos, a resposta é a mesma:
	#    entregar o último passo bom e NÃO guardar nada. Entregar o
	#    último bom é o que impede o jogo de pular um pedaço inteiro (ou
	#    de congelar); não acumular o resto na dívida é o que impede esse
	#    pedaço de voltar depois, aos pedaços. E não entrar na janela é o
	#    que impede um quadro absurdo de contaminar os próximos seis.
	if delta < PISO_DO_QUADRO or delta > TETO_DO_SOLUCO:
		return _ultimo_bom

	# 2. O ENCAIXE NO VSYNC.
	var encaixado := _encaixar(delta)

	# 3. A MÉDIA CURTA.
	_tempos.append(encaixado)
	_soma += encaixado
	if _tempos.size() > JANELA:
		_soma -= _tempos[0]
		_tempos.remove_at(0)
	var media := _soma / float(_tempos.size())

	# A DÍVIDA. O que o relógio real andou a mais (ou a menos) do que o
	# jogo andou fica guardado e volta em fatias.
	_divida = clampf(_divida + (delta - media), -DIVIDA_MAXIMA, DIVIDA_MAXIMA)
	var acerto := _divida * DEVOLUCAO
	_divida -= acerto

	var resultado := clampf(media + acerto, 0.0001, PASSO_MAXIMO)
	quadros_de_tela = delta / maxf(_vsync, 0.0001)
	_ultimo_bom = resultado
	return resultado

## Zera a memória. Chamado quando o jogo sabe que o próximo quadro não
## tem relação com os anteriores — voltar de uma tela que ficou parada,
## por exemplo. Sem isto a média carregaria quadros de outra era.
func recomecar() -> void:
	_tempos.clear()
	_soma = 0.0
	_divida = 0.0

## O múltiplo do relógio de tela mais próximo, quando há um perto o
## bastante. Fora da tolerância, o quadro fica como veio: inventar um
## encaixe onde não há seria justamente introduzir o erro que este
## módulo existe para tirar.
func _encaixar(delta: float) -> float:
	for n in [1, 2, 3, 4]:
		var alvo := _vsync * float(n)
		if absf(delta - alvo) <= TOLERANCIA_DO_ENCAIXE:
			return alvo
	return delta
