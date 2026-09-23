class_name ScoreCurve
extends RefCounted

## A NOTA DE UM SOCO — E POR QUE ELA MUDOU DE FORMA.
##
## A nota sai da velocidade integrada que o firmware manda em m/s. Pico
## em g e duração continuam informativos: não são massa nem força.
##
## O QUE HAVIA ANTES, E O QUE ESTAVA ERRADO NISSO.
##
## Era uma potência só: `9999 * x^2,20`, com `x` a fração da faixa
## calibrada. Uma potência acima de 1 é uma máquina de esmagar o meio da
## escala, e o meio da escala é onde está QUASE TODO MUNDO. Com 2,20, um
## soco a 35% da faixa — um soco de verdade, dado por um adulto, aceito
## pela placa — pagava 974 pontos. Quem bateu leu "mil" e foi embora
## achando que a máquina não registrou, que é exatamente a reclamação que
## chegou. Pior: a única regulagem disponível era o próprio expoente, e
## mexer nele mudava a nota da escala INTEIRA de uma vez — não dá para
## arrumar o meio sem estragar as pontas.
##
## A CURVA AGORA TEM TRÊS ÂNCORAS, e cada uma responde a uma pergunta que
## quem regula a máquina sabe responder:
##
##   VELOCIDADE MÍNIMA (`min_speed`)  → "abaixo disto não é soco": 0.
##   SOCO DE REFERÊNCIA (`ref_speed`) → "o soco do cliente médio":
##                                      exatamente 5000, sempre.
##   VELOCIDADE MÁXIMA (`max_speed`)  → "o teto da máquina": 9999.
##
## As três valem SEMPRE, com qualquer contraste. É isso que torna a
## mecânica justa de um jeito que se pode prometer: o operador escolhe
## quanto vale um soco médio, e a curva se encarrega de passar por ali.
##
## O CONTRASTE (`contraste`) é a segunda regulagem, e ela é ORTOGONAL à
## primeira: não mexe nas três âncoras, só em quanto a nota se espalha
## ENTRE elas. Acima de 1, um soco um pouco melhor que a média se afasta
## mais depressa da média — o placar fica dramático. Abaixo de 1, as
## notas se juntam perto do meio — o placar fica manso. Nenhum dos dois
## pode fazer um soco médio deixar de pagar 5000, e é por isso que dá
## para mexer no contraste com o salão cheio sem medo.
##
## A DIFICULDADE, ENTÃO, É O `ref_speed` — e ela é honesta: subir o soco
## de referência é dizer "aqui é preciso bater mais forte para tirar
## 5000". Isso é uma frase que o dono da máquina entende e consegue
## defender na frente do cliente. "O expoente é 2,80" não é.

## A nota que o soco de referência paga. Metade da escala, e não um
## número solto: é o que faz "soco médio" e "meio do placar" serem a
## mesma ideia em vez de duas.
const PONTOS_DE_REFERENCIA := 5000

## O CONTRASTE. 1,0 é a resposta neutra depois da ancoragem.
const CONTRASTE_MIN := 0.70
const CONTRASTE_MAX := 1.80
const DEFAULT_CONTRASTE := 1.70

const DEFAULT_DEAD_ZONE := 0.0
const DEFAULT_MIN_SPEED := 0.30
const DEFAULT_MAX_SPEED := 8.00

## Onde o soco de referência cai dentro da faixa, quando ninguém disse.
## Um pouco acima do meio: a metade de baixo da faixa é ocupada por
## socos de teste, de criança e de quem está só passando, e a de cima
## pelos socos que a máquina existe para medir.
const REFERENCIA_PADRAO := 0.565
## Até onde a âncora pode andar. Encostada demais numa ponta, a curva
## vira uma parede de um lado e um chão do outro.
const REFERENCIA_MIN := 0.22
const REFERENCIA_MAX := 0.80

## Limites de regulagem oferecidos pela Central Técnica.
const MIN_SPEED_MIN := 0.20
const MIN_SPEED_MAX := 10.00
const MAX_SPEED_MIN := 0.75
const MAX_SPEED_MAX := 30.00
const DEAD_ZONE_MAX := 0.25
const CHARGE_MAX_SECONDS := 2.80

## `ref_speed = 0` quer dizer "não foi escolhido": use `REFERENCIA_PADRAO`.
## É isto que deixa toda chamada antiga continuar valendo.
const REFERENCIA_AUTOMATICA := 0.0

## O 9999 É UM PRÊMIO RARO, NÃO O RESULTADO NORMAL DE ENCOSTAR NO TETO.
## Somente um golpe que já alcançou o máximo físico entra no sorteio; a
## aleatoriedade nunca aumenta um golpe menor. Nos outros 999 casos ele
## continua sendo extraordinário, mas fica um ponto abaixo da perfeição.
const CHANCE_PERFEITA := 1000

## O SOCO DE VERDADE NUNCA DÁ O MESMO NÚMERO DUAS VEZES.
##
## A curva diz o valor "de tabela"; em cima dele entra uma variação de
## uns 6% para cada lado (dois sorteios somados: perto do centro é o mais
## comum, as pontas são raras). Acima de 8000 a subida fica mais cara: o
## que passa de 8000 é pago só em parte, por sorteio. O teto (9999 de
## tabela) fica como está, para o sorteio do perfeito continuar valendo.
const VARIACAO := 0.06
const LIMIAR_DIFICIL := 8000

static func variar(pontos: int, a: float, b: float, c: float) -> int:
	if pontos <= 0 or pontos >= GameDef.SCORE_MAX:
		return pontos
	var fator := 1.0 + (a + b - 1.0) * VARIACAO * 2.0
	var nota := float(pontos) * fator
	if nota > LIMIAR_DIFICIL:
		nota = LIMIAR_DIFICIL + (nota - LIMIAR_DIFICIL) * lerpf(0.45, 1.0, c)
	return clampi(int(round(nota)), 1, GameDef.SCORE_MAX - 1)

static func aplicar_perfeito_raro(pontos: int, sorteio: int) -> int:
	var nota := clampi(pontos, 0, GameDef.SCORE_MAX)
	if nota < GameDef.SCORE_MAX:
		return nota
	return GameDef.SCORE_MAX if posmod(sorteio, CHANCE_PERFEITA) == 0 else GameDef.SCORE_MAX - 1

static func sanitize(
	min_speed: float, max_speed: float, contraste: float, dead_zone: float,
	ref_speed := REFERENCIA_AUTOMATICA
) -> Dictionary:
	var low := clampf(min_speed, MIN_SPEED_MIN, MIN_SPEED_MAX)
	var high := clampf(max_speed, maxf(MAX_SPEED_MIN, low + 0.5), MAX_SPEED_MAX)
	var dz := clampf(dead_zone, 0.0, DEAD_ZONE_MAX)
	var span := high - low
	# A âncora vive DENTRO da faixa, e com folga das duas pontas. Um
	# `ref_speed` herdado de outra montagem — ou digitado errado — não
	# pode desmontar a curva; ele é trazido de volta para a janela útil.
	var ref := ref_speed
	if ref <= 0.0:
		ref = low + span * REFERENCIA_PADRAO
	ref = clampf(ref, low + span * REFERENCIA_MIN, low + span * REFERENCIA_MAX)
	return {
		"min_speed": low,
		"max_speed": high,
		"contraste": clampf(contraste, CONTRASTE_MIN, CONTRASTE_MAX),
		"dead_zone": dz,
		"ref_speed": ref,
	}

## A fração da faixa (já sem a zona morta) em que o soco de referência
## cai. É o `m` das contas abaixo.
static func fracao_de_referencia(cfg: Dictionary) -> float:
	var low: float = cfg["min_speed"]
	var high: float = cfg["max_speed"]
	var dz: float = cfg["dead_zone"]
	var bruta := clampf((float(cfg["ref_speed"]) - low) / maxf(high - low, 0.01), 0.0, 1.0)
	if dz > 0.0:
		bruta = (bruta - dz) / maxf(1.0 - dz, 0.01)
	return clampf(bruta, 0.08, 0.92)

static func normalized(speed: float, min_speed: float, max_speed: float, dead_zone := DEFAULT_DEAD_ZONE) -> float:
	var cfg := sanitize(min_speed, max_speed, DEFAULT_CONTRASTE, dead_zone)
	var span: float = cfg["max_speed"] - cfg["min_speed"]
	var x := clampf((maxf(speed, 0.0) - cfg["min_speed"]) / span, 0.0, 1.0)
	var dz: float = cfg["dead_zone"]
	if x <= dz:
		return 0.0
	x = (x - dz) / maxf(1.0 - dz, 0.01)
	return clampf(x, 0.0, 1.0)

## A RESPOSTA DA CURVA, SOZINHA E SEM UNIDADE.
##
## Recebe a fração da faixa (`x`), a fração em que fica o soco de
## referência (`m`) e o contraste (`k`). Devolve a fração da nota. Está
## separada porque é a única parte que dá para provar com teste, e porque
## as três garantias do cabeçalho são três linhas de conta que precisam
## ficar à vista:
##
##   1. `u = x^gama`, com `gama = ln(0,5) / ln(m)`. Isto e mais nada é o
##      que põe o soco de referência em meio placar: em `x = m`, `u` dá
##      0,5 por construção, seja `m` qual for.
##   2. `s = u^k / (u^k + (1-u)^k)`. Uma curva em S em volta de 0,5.
##      Ela não mexe nos três pontos que interessam — `s(0) = 0`,
##      `s(0,5) = 0,5`, `s(1) = 1` valem para QUALQUER `k` positivo —,
##      só no caminho entre eles.
##   3. As duas são crescentes, então a composta é crescente: um soco
##      mais forte nunca vale menos. Isso é o mínimo que uma máquina de
##      soco precisa garantir, e é testado a passo fino.
static func resposta(x: float, m: float, k: float) -> float:
	var frac := clampf(x, 0.0, 1.0)
	if frac <= 0.0:
		return 0.0
	if frac >= 1.0:
		return 1.0
	var ancora := clampf(m, 0.08, 0.92)
	var gama := log(0.5) / log(ancora)
	var u := clampf(pow(frac, gama), 0.0, 1.0)
	var contraste := clampf(k, CONTRASTE_MIN, CONTRASTE_MAX)
	var a := pow(u, contraste)
	var b := pow(1.0 - u, contraste)
	if a + b <= 0.0:
		return u
	return clampf(a / (a + b), 0.0, 1.0)

static func points_from_speed(
	speed: float,
	min_speed: float,
	max_speed: float,
	contraste := DEFAULT_CONTRASTE,
	dead_zone := DEFAULT_DEAD_ZONE,
	ref_speed := REFERENCIA_AUTOMATICA
) -> int:
	var cfg := sanitize(min_speed, max_speed, contraste, dead_zone, ref_speed)
	var x := normalized(speed, cfg["min_speed"], cfg["max_speed"], cfg["dead_zone"])
	var fracao := resposta(x, fracao_de_referencia(cfg), cfg["contraste"])
	var pontos := clampi(int(round(fracao * GameDef.SCORE_MAX)), 0, GameDef.SCORE_MAX)
	# Um golpe aprovado e acima da zona morta precisa aparecer. O
	# arredondamento pode zerar o começo da escala, e nota zero num soco
	# que a placa aceitou parece falha do saco, não dificuldade.
	if x > 0.000001 and pontos == 0:
		return 1
	# Não deixe o arredondamento entregar 9999 antes de o golpe alcançar
	# de fato o teto calibrado da máquina.
	if pontos >= GameDef.SCORE_MAX and speed < float(cfg["max_speed"]):
		return GameDef.SCORE_MAX - 1
	return pontos

static func speed_from_charge(seconds: float, min_speed: float, max_speed: float) -> float:
	var t := clampf(seconds / CHARGE_MAX_SECONDS, 0.0, 1.0)
	# A carga virtual cresce devagar no começo e acelera perto do fim.
	var virtual_strength := pow(t, 0.65)
	return lerpf(min_speed, max_speed, virtual_strength)

static func points_from_charge(
	seconds: float,
	min_speed: float,
	max_speed: float,
	contraste := DEFAULT_CONTRASTE,
	dead_zone := DEFAULT_DEAD_ZONE,
	ref_speed := REFERENCIA_AUTOMATICA
) -> int:
	return points_from_speed(
		speed_from_charge(seconds, min_speed, max_speed),
		min_speed, max_speed, contraste, dead_zone, ref_speed
	)

## O NOME DA DIFICULDADE SAI DE ONDE ESTÁ O SOCO DE REFERÊNCIA, e não do
## contraste. É a âncora que decide quanta gente chega a cada nível:
## exigir mais velocidade para pagar 5000 é, literalmente, a máquina
## ficar mais difícil. O contraste só muda o espalhamento.
static func difficulty_name(min_speed: float, max_speed: float, ref_speed: float) -> String:
	var m := _fracao_da_ancora(min_speed, max_speed, ref_speed)
	if m <= 0.38:
		return "FÁCIL"
	if m <= 0.60:
		return "NORMAL"
	if m <= 0.72:
		return "DIFÍCIL"
	return "IMPLACÁVEL"

## O próximo degrau de dificuldade, EM VELOCIDADE — para o botão da
## Central rodar entre os quatro nomes acima sem inventar valores.
static func proxima_dificuldade(min_speed: float, max_speed: float, ref_speed: float) -> float:
	var cfg := sanitize(min_speed, max_speed, DEFAULT_CONTRASTE, 0.0, ref_speed)
	var low: float = cfg["min_speed"]
	var span: float = float(cfg["max_speed"]) - low
	match difficulty_name(min_speed, max_speed, ref_speed):
		"FÁCIL":
			return low + span * 0.55
		"NORMAL":
			return low + span * 0.68
		"DIFÍCIL":
			return low + span * 0.78
	return low + span * 0.32

static func _fracao_da_ancora(min_speed: float, max_speed: float, ref_speed: float) -> float:
	var cfg := sanitize(min_speed, max_speed, DEFAULT_CONTRASTE, 0.0, ref_speed)
	var low: float = cfg["min_speed"]
	return clampf(
		(float(cfg["ref_speed"]) - low) / maxf(float(cfg["max_speed"]) - low, 0.01), 0.0, 1.0
	)

## A CURVA INTEIRA EM `amostras` PONTOS, para a Central desenhar antes de
## salvar. Quem regula precisa VER o que a mudança faz: a diferença entre
## um soco de referência de 3,0 e um de 3,6 m/s só existe no desenho.
static func amostrar(
	min_speed: float, max_speed: float, contraste: float, dead_zone: float,
	amostras := 48, ref_speed := REFERENCIA_AUTOMATICA
) -> Array:
	var cfg := sanitize(min_speed, max_speed, contraste, dead_zone, ref_speed)
	var pontos: Array = []
	for i in range(amostras + 1):
		var t := float(i) / float(amostras)
		var v: float = lerpf(0.0, cfg["max_speed"] * 1.05, t)
		pontos.append(Vector2(v, float(points_from_speed(
			v, cfg["min_speed"], cfg["max_speed"], cfg["contraste"],
			cfg["dead_zone"], cfg["ref_speed"]
		))))
	return pontos
