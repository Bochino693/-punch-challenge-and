class_name AutoEscala
extends RefCounted

## A MÁQUINA APRENDE A FAIXA DO PRÓPRIO GABINETE.
##
## O PROBLEMA, EM UM NÚMERO SÓ. A faixa de fábrica vai de 0,30 a 5,20 m/s
## porque foi assim que a bancada mediu. O gabinete montado não mede
## assim: dependendo de onde a palheta foi parafusada, de quanto o braço
## cede e de qual é a largura real da fenda, o mesmo soco que na bancada
## dava 4 m/s aqui dá 1,2. E a escala não sabe disso.
##
## O resultado é a reclamação que chegou: "não consigo passar de mil". Com
## teto em 5,20 e a montagem entregando 1,2 no máximo, a máquina inteira
## vive no primeiro quinto da régua:
##
##     0,6 m/s →  246      1,0 m/s →  782      1,2 m/s → 1105
##
## Ninguém está batendo fraco. A régua é que está errada — e não havia
## como quem opera descobrir isso, porque a tela não mostra velocidade
## nenhuma, só a nota baixa.
##
## O MESMO GABINETE COM A FAIXA APRENDIDA (0,35 a 1,45, médio em 0,95):
##
##     0,6 m/s → 1525      1,0 m/s → 5550      1,2 m/s → 7739
##
## Mesmo sensor, mesmo soco, mesma curva. Só a régua mudou.
##
## ------------------------------------------------------------------
## COMO ELA APRENDE
##
## Guardando a velocidade de cada soco ACEITO e tirando percentis:
##
##     mínimo     ← percentil 5, com folga para baixo
##     referência ← percentil 70 (um soco claramente acima da média)
##     máximo     ← percentil 97, com folga para cima
##
## O percentil 70 virar a referência é o ponto inteiro: a curva paga 5000
## exatos ali, então só os 30% mais fortes do salão tendem a passar de
## meio placar. A máquina aprende o gabinete sem transformar a mediana em
## pontuação alta — dificuldade maior e automática.
##
## ------------------------------------------------------------------
## AS QUATRO TRAVAS, porque aprender sozinho é perigoso
##
## 1. SÓ COM AMOSTRA SUFICIENTE. Abaixo de `MINIMO_PARA_VALER` socos ela
##    não mexe em nada. Um gabinete recém-ligado usa o que está
##    configurado, e não uma média de três golpes.
##
## 2. PASSO LIMITADO. Cada atualização anda no máximo `PASSO_MAXIMO` da
##    distância até o alvo. Sem isso, uma criança batendo dez vezes
##    seguidas puxaria a régua para baixo e o adulto seguinte tiraria
##    9999 — e a tabela de recordes do dia viraria lixo. Com o passo
##    limitado, a régua leva dezenas de socos para andar de verdade, que
##    é o tempo em que uma mudança REAL de montagem se confirma.
##
## 3. JANELA LONGA. `JANELA` socos, e os mais antigos saem. Longa o
##    bastante para uma fila de amigos batendo fraco não mandar na noite,
##    curta o bastante para a máquina acompanhar quando o saco é trocado.
##
## 4. NUNCA ENCOSTA NAS PONTAS. O resultado passa por
##    `ScoreCurve.sanitize` como qualquer outro ajuste, e a separação
##    mínima entre piso e teto é garantida ali.
##
## ------------------------------------------------------------------
## E ELA PODE SER DESLIGADA. Quem já calibrou à mão e quer aquilo e mais
## nada desliga na Central, e a régua congela onde está. O automático é o
## padrão porque é o que faz a máquina funcionar sem ninguém, mas não é
## uma imposição.

## Quantos socos a memória guarda.
const JANELA := 240

## Abaixo disto ela não opina. Doze socos são seis rodadas — o bastante
## para uma tendência existir, pouco o bastante para a máquina se ajeitar
## ainda na primeira meia hora de uso.
const MINIMO_PARA_VALER := 12

## Quanto da distância até o alvo cada atualização percorre.
const PASSO_MAXIMO := 0.12

## Os percentis de cada âncora.
const P_MINIMO := 0.05
## O SOCO DE REFERÊNCIA (o que paga 5000) é o do percentil 42: um soco
## comum, bem dado, chega lá. No percentil 70 sete em cada dez socos
## ficavam abaixo de 5000 e a máquina parecia "sempre fraca".
const P_REFERENCIA := 0.42
const P_MAXIMO := 0.97

## Folgas depois do percentil. O piso desce (quem bate fraco precisa ver
## algum ponto) e o teto sobe (9999 tem de continuar sendo conquistado, e
## não entregue ao melhor soco já medido).
## O piso também vai para a placa como limite de descarte: com folga
## pequena, soco mais leve nem era aceito ("o sensor quase não aciona").
const FOLGA_PISO := 0.55
const FOLGA_TETO := 1.12

## A memória, em m/s, do mais antigo para o mais novo.
var socos: PackedFloat32Array = PackedFloat32Array()
var ligada := true

## Um soco aceito entra na memória. Só isso — a régua não muda aqui, para
## que um soco nunca altere a régua que ele mesmo está usando.
func registrar(velocidade: float) -> void:
	if velocidade <= 0.0:
		return
	socos.append(velocidade)
	if socos.size() > JANELA:
		socos = socos.slice(socos.size() - JANELA)

func quantos() -> int:
	return socos.size()

func pronta() -> bool:
	return ligada and socos.size() >= MINIMO_PARA_VALER

## O percentil de uma lista já ordenada, por interpolação linear.
static func percentil(ordenados: PackedFloat32Array, p: float) -> float:
	if ordenados.is_empty():
		return 0.0
	if ordenados.size() == 1:
		return ordenados[0]
	var pos := clampf(p, 0.0, 1.0) * float(ordenados.size() - 1)
	var i := int(floor(pos))
	var j := mini(i + 1, ordenados.size() - 1)
	return lerpf(ordenados[i], ordenados[j], pos - float(i))

## A RÉGUA QUE A MEMÓRIA PEDE, sem nenhum limite de passo aplicado.
## Separada para a Central poder MOSTRAR o alvo ao lado do valor em uso —
## quem opera precisa ver para onde a máquina está indo, não só onde está.
func alvo() -> Dictionary:
	if socos.size() < MINIMO_PARA_VALER:
		return {}
	var ordenados := socos.duplicate()
	ordenados.sort()
	var piso := percentil(ordenados, P_MINIMO) * FOLGA_PISO
	var teto := percentil(ordenados, P_MAXIMO) * FOLGA_TETO
	var meio := percentil(ordenados, P_REFERENCIA)
	# O teto tem de ficar acima do piso com folga real. Numa máquina em
	# que todo mundo bate igual, os três percentis saem colados e a
	# escala inteira colapsaria numa faixa de nada.
	if teto < piso + 0.5:
		teto = piso + 0.5
	return {"vmin": piso, "vref": meio, "vmax": teto}

## UM PASSO EM DIREÇÃO AO ALVO, a partir da régua em uso.
##
## Devolve vazio quando não há o que fazer — sem amostra, desligada, ou
## já em cima do alvo. Quem chama aplica o que voltar e salva.
func passo(vmin_atual: float, vref_atual: float, vmax_atual: float) -> Dictionary:
	if not pronta():
		return {}
	var destino := alvo()
	if destino.is_empty():
		return {}
	var novo_min := lerpf(vmin_atual, float(destino["vmin"]), PASSO_MAXIMO)
	var novo_ref := lerpf(vref_atual, float(destino["vref"]), PASSO_MAXIMO)
	var novo_max := lerpf(vmax_atual, float(destino["vmax"]), PASSO_MAXIMO)
	# Mudança pequena demais não vale uma gravação em disco: numa máquina
	# já ajustada isto roda a cada rodada, a noite inteira.
	if (
		absf(novo_min - vmin_atual) < 0.01
		and absf(novo_ref - vref_atual) < 0.01
		and absf(novo_max - vmax_atual) < 0.01
	):
		return {}
	return {"vmin": novo_min, "vref": novo_ref, "vmax": novo_max}

## PARA O DISCO E DE VOLTA. Guardar os socos — e não só a régua — é o que
## permite a máquina continuar de onde parou depois de desligar à noite,
## em vez de reaprender tudo toda manhã.
func para_salvar() -> Dictionary:
	return {"ligada": ligada, "socos": Array(socos)}

func carregar(dados: Variant) -> void:
	if not (dados is Dictionary):
		return
	var d: Dictionary = dados
	ligada = bool(d.get("ligada", true))
	socos = PackedFloat32Array()
	for v in d.get("socos", []):
		var f := float(v)
		# Lixo no arquivo não entra: uma velocidade absurda gravada por
		# uma versão anterior deslocaria a régua inteira sem explicação.
		if f > 0.0 and f < 60.0:
			socos.append(f)
	if socos.size() > JANELA:
		socos = socos.slice(socos.size() - JANELA)

func esquecer() -> void:
	socos = PackedFloat32Array()
