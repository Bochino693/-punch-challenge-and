class_name Desempenho
extends RefCounted

## O VIGIA DO RITMO — e o que ele faz quando o ritmo cai.
##
## POR QUE ISTO EXISTE. "A animação está travada" é a queixa mais difícil
## de consertar de todas, porque quem programa não vê: aqui a tela roda
## lisa, e o gabinete do cliente tem outro vídeo, outra resolução, outra
## TV. Sem número, o conserto vira palpite — e palpite em desempenho
## costuma otimizar a parte que não custava nada.
##
## Este módulo faz duas coisas, e a segunda depende da primeira:
##
##   1. MEDE. Guarda o tempo dos últimos quadros e responde quantos
##      quadros por segundo a máquina está de fato entregando. É esse
##      número que aparece na Central e é ele que se manda para quem for
##      consertar, em vez de "está travado".
##
##   2. AJUSTA. Se a máquina não está dando conta, o jogo GASTA MENOS —
##      sozinho, sem ninguém configurar nada. Confete, brasa e estilhaço
##      são a parte cara e a parte que ninguém conta: cortar metade das
##      partículas num PC fraco é invisível, e a animação lisa que se
##      ganha com isso é o contrário de invisível.
##
## O ajuste é LENTO de propósito, nos dois sentidos. Um vigia que reage a
## cada quadro faz a quantidade de confete piscar, e piscar chama mais
## atenção do que a queda que ele estava tentando esconder.

## Quantos quadros entram na média. Um terço de segundo a 60 fps: curto
## o bastante para perceber uma queda, longo o bastante para não reagir
## a um soluço isolado do sistema operacional.
const JANELA := 20

## Abaixo disto a máquina está sofrendo; acima, sobra folga.
const ALVO_BAIXO := 50.0
const ALVO_ALTO := 58.0

## Quanto a qualidade anda por segundo, para baixo e para cima. Descer
## mais rápido do que subir é de propósito: alívio tem de chegar logo,
## e a volta pode esperar até ter certeza de que a folga é real.
const QUEDA := 0.9
const SUBIDA := 0.25

## O piso: nem no pior PC o jogo fica sem efeito nenhum. Um fliperama
## sem confete não é um fliperama lento, é um fliperama quebrado.
const PISO := 0.35
## Um quadro acima disto já é percebido como travamento. A redução normal
## é suave; esta freada curta reage ao pico antes da próxima explosão.
const QUADRO_CRITICO_MS := 28.0
const FREIO_CRITICO := 0.12

var _tempos: Array[float] = []
var _soma := 0.0
## 1.0 = tudo; 0.35 = o mínimo que ainda parece festa.
var qualidade := 1.0

func medir(delta: float) -> void:
	# Quadros absurdos não entram na conta: o primeiro quadro depois de
	# carregar uma cena, ou depois de a janela voltar do minimizado, mede
	# meio segundo e derrubaria a qualidade por um evento que não é o
	# desempenho do jogo.
	if delta <= 0.0 or delta > 0.5:
		return
	if delta * 1000.0 >= QUADRO_CRITICO_MS:
		qualidade = maxf(PISO, qualidade - FREIO_CRITICO)
	_tempos.append(delta)
	_soma += delta
	if _tempos.size() > JANELA:
		_soma -= _tempos[0]
		_tempos.remove_at(0)
	if _tempos.size() < JANELA:
		return
	# O QUE O OLHO VÊ É O PIOR QUADRO, E NÃO A MÉDIA.
	#
	# A média escondia exatamente o defeito que este vigia existe para
	# combater. Uma tela que roda 57 quadros por segundo e engasga num
	# deles tem média de 57 — "está ótimo" —, e o engasgo é o único
	# quadro que a pessoa na frente da máquina percebe. Pior: o engasgo
	# do jogo é PERIÓDICO e sempre no mesmo lugar, o instante do soco.
	# Com a média, a qualidade subia de volta ao máximo durante a tela de
	# atração, calma, e desabava de novo no impacto seguinte — uma vez
	# por rodada, a noite inteira.
	#
	# Medindo pelo PIOR quadro da janela, a qualidade só volta a subir
	# quando um terço de segundo inteiro passa sem nenhum tranco. É
	# histerese de graça, e é o que faz o ajuste parar de oscilar.
	var pior := pior_ms()
	if pior > 1000.0 / ALVO_BAIXO:
		qualidade = maxf(PISO, qualidade - QUEDA * delta)
	elif pior < 1000.0 / ALVO_ALTO:
		qualidade = minf(1.0, qualidade + SUBIDA * delta)
	aplicar_teto()

## Quadros por segundo medidos, ou 0 enquanto não há amostra suficiente.
func fps() -> float:
	if _tempos.is_empty() or _soma <= 0.0:
		return 0.0
	return float(_tempos.size()) / _soma

## Milissegundos do quadro mais lento da janela. É este número que
## denuncia engasgo: a média pode estar em 60 e o pior quadro em 40 ms,
## e é o pior quadro que o olho vê.
func pior_ms() -> float:
	var pior := 0.0
	for t in _tempos:
		pior = maxf(pior, t)
	return pior * 1000.0

## Quantas partículas pedir, dado quantas o efeito gostaria de soltar.
func quantas(cheio: int) -> int:
	return maxi(1, int(round(float(cheio) * qualidade)))

## O TETO POSTO À MÃO, na Central.
##
## O vigia automático acerta na maioria das máquinas, e erra em duas
## situações: num PC que oscila (e aí ele fica subindo e descendo a
## qualidade o tempo todo) e num PC bom em que o operador prefere menos
## efeito por gosto. O teto resolve as duas — e AUTO, que é o padrão,
## deixa tudo como está.
##
## Ele é um TETO, não um valor fixo: com o teto em MÉDIO, uma máquina que
## não dá conta continua caindo abaixo dele sozinha. Nenhum ajuste da
## Central pode obrigar a máquina a gastar mais do que ela aguenta.
const TETOS := {"AUTO": 1.0, "ALTO": 1.0, "MEDIO": 0.65, "BAIXO": 0.40}
var teto := "AUTO"

func aplicar_teto() -> void:
	qualidade = minf(qualidade, float(TETOS.get(teto, 1.0)))

## O próximo teto da roda, para o botão da Central.
func proximo_teto() -> String:
	var nomes := ["AUTO", "ALTO", "MEDIO", "BAIXO"]
	return str(nomes[(nomes.find(teto) + 1) % nomes.size()])
