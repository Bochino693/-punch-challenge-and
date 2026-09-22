class_name Calibracao
extends RefCounted

## A CONTA DO ASSISTENTE DE CALIBRAÇÃO.
##
## Só matemática: recebe as amostras colhidas na Central e devolve os
## parâmetros sugeridos. Fica separada da tela porque é a única parte que
## dá para provar com teste — uma sugestão errada aqui desregula a
## máquina inteira, e descobrir isso com o salão cheio é caro.
##
## POR QUE PERCENTIS E NÃO MÍNIMO E MÁXIMO. Em cinco socos, um escorrega
## no saco e outro pega de raspão: usar o extremo faz a calibração inteira
## depender do pior e do melhor golpe do dia. O percentil descarta o
## acidente sem precisar que alguém decida, na hora, qual amostra jogar
## fora.
##
## O QUE ESTA VERSÃO CORRIGE, E POR QUE ERA GRAVE.
##
## A sugestão antiga devolvia um campo `amin` em GRAVIDADES — herança do
## firmware do acelerômetro, onde "sensibilidade" era mesmo um limiar de
## g. O jogo gravava esse número e o mandava à placa como o QUARTO campo
## do CONFIG, que no firmware óptico é o PULSO MÍNIMO EM MILISSEGUNDOS.
## Duas unidades diferentes no mesmo campo, e ninguém avisado.
##
## O estrago não é sutil. Pulso mínimo é um teto de VELOCIDADE ao
## contrário: 5 ms com uma palheta de 20 mm manda a placa recusar tudo
## acima de 4 m/s. Ou seja, quanto mais forte o soco, maior a chance de a
## máquina responder `CURTO` e não pontuar nada — e o número vinha de uma
## medição de ruído, então bastava um soco cair no passo de REPOUSO para
## a máquina se estrangular sozinha e ficar assim, gravada em disco,
## sobrevivendo à reinstalação do jogo.
##
## Agora não sai daqui número em g nenhum. O pulso mínimo é DERIVADO da
## geometria (`ArduinoProtocol.pulso_minimo_ms`): largura da palheta e
## teto calibrado entram, milissegundos saem, e o limite passa a bater
## exatamente com o outro limite que o firmware já aplica sozinho.

## Quantos golpes de cada tipo o assistente pede.
const AMOSTRAS := 5

## Percentis usados. O piso vem da parte de baixo dos golpes fracos; o
## teto, da parte de cima dos fortes.
const PERCENTIL_PISO := 0.20
const PERCENTIL_TETO := 0.80

## Folga aplicada depois dos percentis.
##
## O piso desce um pouco mais: quem bate fraco tem de ver ALGUM ponto,
## senão acha que a máquina não registrou e vai embora achando que
## quebrou.
const FOLGA_PISO := 0.85

## O TETO SOBE BASTANTE MAIS DO QUE SUBIA — 22% em vez de 8%.
##
## Com a curva ancorada (ver `ScoreCurve`), a nota deixou de esmagar o
## meio da escala: um soco a 90% da faixa agora paga nove mil e poucos,
## e não sete mil e pouco. Isso é o conserto que se queria, mas devolve o
## problema pela outra ponta — com apenas 8% de folga, o próprio técnico
## que calibrou tiraria 9999 no primeiro soco forte da noite, e um teto
## que o primeiro cliente encosta deixa de ser teto.
##
## Com 22%, o golpe forte típico da calibração cai perto de NOCAUTE:
## impressionante, comemorado, e ainda com o topo da escala por
## conquistar. É o ponto em que a máquina fica justa nas duas pontas ao
## mesmo tempo.
const FOLGA_TETO := 1.22

## ONDE FICA O SOCO DE REFERÊNCIA, entre o golpe fraco típico e o forte
## típico. A curva paga exatamente 5000 nele.
##
## 0,62 e não 0,50: quem calibra dá o "golpe fraco" de propósito mais
## fraco do que qualquer cliente daria, porque o passo pede um toque de
## teste. A média real do salão fica acima do meio entre as duas
## demonstrações, e ancorar no meio geométrico tornaria a máquina
## generosa demais com quem mal encostou.
const REFERENCIA_ENTRE := 0.62

## O valor num percentil de uma lista, por interpolação linear.
static func percentil(valores: Array, p: float) -> float:
	if valores.is_empty():
		return 0.0
	var ordenados := valores.duplicate()
	ordenados.sort()
	if ordenados.size() == 1:
		return float(ordenados[0])
	var pos := clampf(p, 0.0, 1.0) * float(ordenados.size() - 1)
	var i := int(floor(pos))
	var j := mini(i + 1, ordenados.size() - 1)
	return lerpf(float(ordenados[i]), float(ordenados[j]), pos - float(i))

## A SUGESTÃO COMPLETA.
##
## `fracos` e `fortes` são velocidades em m/s; `ruido` é o maior nível de
## sinal visto com o saco PARADO (no sensor óptico ele é a leitura de A0,
## de 0 a 1 — NÃO é uma aceleração, e não entra em conta nenhuma: vai
## junto só para a tela poder mostrar o que foi medido). `largura_m` é a
## largura da palheta, e é ela que transforma o teto de velocidade no
## pulso mínimo que a placa precisa receber.
##
## Devolve os parâmetros e o motivo de cada um, porque quem calibra
## precisa poder discordar com fundamento.
static func sugerir(
	fracos: Array, fortes: Array, ruido: float, largura_m := 0.020
) -> Dictionary:
	var piso := percentil(fracos, PERCENTIL_PISO) * FOLGA_PISO
	var teto := percentil(fortes, PERCENTIL_TETO) * FOLGA_TETO

	# O teto tem de ficar acima do piso com folga de verdade. Se os dois
	# grupos saíram parecidos — porque quem calibrou bateu igual nas duas
	# rodadas — a escala inteira colapsaria numa faixa de nada.
	if teto < piso + 0.5:
		teto = piso + 0.5

	# O SOCO DE REFERÊNCIA sai das duas demonstrações, e não de uma
	# fração da faixa: a faixa já tem as folgas dentro dela, e ancorar
	# numa fração dela seria ancorar na folga.
	var referencia := lerpf(
		percentil(fracos, 0.5), percentil(fortes, 0.5), REFERENCIA_ENTRE
	)

	var cfg := ScoreCurve.sanitize(
		piso, teto, ScoreCurve.DEFAULT_CONTRASTE, ScoreCurve.DEFAULT_DEAD_ZONE, referencia
	)
	var pulso := ArduinoProtocol.pulso_minimo_ms(largura_m, float(cfg["max_speed"]))
	var janela := ArduinoProtocol.janela_medivel(largura_m, pulso)
	return {
		"vmin": cfg["min_speed"],
		"vmax": cfg["max_speed"],
		"vref": cfg["ref_speed"],
		"pulso_ms": pulso,
		"ruido": ruido,
		"fracos": fracos.size(),
		"fortes": fortes.size(),
		"mede_ate": janela.y,
		"porque_vmin": "percentil %d dos golpes fracos, com folga de %d%%" % [
			int(PERCENTIL_PISO * 100.0), int((1.0 - FOLGA_PISO) * 100.0)
		],
		"porque_vmax": "percentil %d dos golpes fortes, com folga de %d%%" % [
			int(PERCENTIL_TETO * 100.0), int((FOLGA_TETO - 1.0) * 100.0)
		],
		"porque_vref": "entre o fraco e o forte típicos — aqui o placar paga %d" % (
			ScoreCurve.PONTOS_DE_REFERENCIA
		),
		"porque_pulso": "palheta de %d mm medindo até %.1f m/s" % [
			int(round(largura_m * 1000.0)), janela.y
		],
	}

## Se há amostras suficientes para uma sugestão honesta.
static func pronta(fracos: Array, fortes: Array) -> bool:
	return fracos.size() >= AMOSTRAS and fortes.size() >= AMOSTRAS
