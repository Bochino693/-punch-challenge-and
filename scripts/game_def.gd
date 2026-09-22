class_name GameDef
extends RefCounted

## Definições compartilhadas do Punch Challenge: estados, faixas de golpe
## e constantes de jogo. Sem estado — só tipos e funções puras.

enum State { IDLE, COUNTDOWN, ARMED, MEASURING, RESULT, CONFIGURATION }

## AS TRÊS FAIXAS GROSSAS, que sobreviveram aos oito níveis.
##
## Os oito níveis (`ScoreTier`) mandam no espetáculo. Estas três mandam
## no que precisa de um sinal SIMPLES: a cor da moldura de LEDs, que tem
## resolução de uma cor só, e as estatísticas, que contam "fracos, médios
## e fortes" há tempo demais para virarem oito colunas sem perder o
## histórico. Elas são DERIVADAS do nível — não existe mais um segundo
## lugar onde a classificação possa discordar de si mesma.
enum Faixa { FRACA, MEDIA, FORTE }

## O teto da escala, o mesmo do último nível. Um número só, para nunca
## haver uma tela mostrando 999 e outra 9999.
const SCORE_MAX := ScoreTier.PERFEITO
const CREDITOS_MAX := 99
const SERIAL_BAUD := 115200
## QUANTO A MÁQUINA ESPERA PELO SOCO.
##
## Eram oito segundos, e ao fim deles a rodada morria com o crédito já
## gasto: quem hesitou pagou e não jogou. Agora a espera é longa, e o
## fim dela DEVOLVE o crédito — o limite existe só para a máquina não
## passar a tarde armada se a pessoa foi embora, nunca para cobrar.
const ESPERA_DO_SOCO := 90.0
## A partir daqui a tela avisa que vai voltar, com o relógio à mostra.
const AVISO_DE_VOLTA := 15.0
## O RITMO DA JOGADA É OUTRO DO RITMO DA COMEMORAÇÃO.
##
## São dois momentos com donos diferentes. Do soco até o número na tela,
## quem manda é a ANSIEDADE de quem acabou de bater: ali cada décimo a
## mais é espera, e espera depois do esforço esfria o golpe. Da revelação
## do ranking em diante quem manda é a comemoração, e essa pode respirar
## — foi por tratar os dois com o mesmo relógio que a jogada parecia
## lenta e a premiação parecia apressada.
##
## Aqui é a parte rápida: o flash do impacto e a subida do número.
## O NÚMERO SOBE E ACABA. Não há suspense a construir aqui.
##
## Esta era a queixa de "a projeção de pontos está lenta": do soco até o
## número parado na tela eram 0,38 + 0,86 = mais de um segundo e um
## quarto, com a pessoa parada olhando um número girar. Num fliperama o
## suspense mora ANTES do golpe, não depois — depois do golpe o que se
## quer é saber quanto valeu, e rápido.
##
## Meio segundo de subida é o tempo de ler quatro dígitos correndo e
## ainda ver o último assentar. Abaixo disso o número aparece pronto e
## some a graça; acima, vira espera.
const CONTAGEM_DURACAO := 0.52
const IMPACTO_DURACAO := 0.26 ## Estado MEASURING: flash + onda de choque.
const RESULTADO_TIMEOUT := 12.0


## Cor de cada faixa, usada pela moldura de LEDs, pelo medidor e pelo
## veredito ao mesmo tempo — a tela inteira fala a mesma cor. Sai da
## paleta, e não de um hexadecimal solto aqui, para o tema mudar de uma
## vez em vez de mudar por partes.
const COR_FRACA := Color("8697b4")
const COR_MEDIA := Paleta.AMBAR
const COR_FORTE := Paleta.VERMELHO



## A faixa grossa de uma pontuação, lida do nível: os dois primeiros
## níveis são fracos, os dois seguintes médios, os quatro últimos fortes.
static func faixa_de(pontos: int) -> Faixa:
	var i := ScoreTier.indice_de(pontos)
	if i >= 4:
		return Faixa.FORTE
	if i >= 2:
		return Faixa.MEDIA
	return Faixa.FRACA

## Cor da faixa — a mesma que tinge moldura, medidor e fundo.
static func cor_da_faixa(faixa: Faixa) -> Color:
	match faixa:
		Faixa.FORTE:
			return COR_FORTE
		Faixa.MEDIA:
			return COR_MEDIA
	return COR_FRACA

## O VEREDITO COMPLETO DE UM GOLPE, num dicionário só.
##
## Continua existindo, e continua sendo o único jeito de perguntar "o que
## este soco vale", porque a tela, a moldura, o som e a estatística
## precisam concordar. O que mudou é a origem: agora vem do nível.
static func classificar(pontos: int) -> Dictionary:
	var nivel := ScoreTier.de(pontos)
	var faixa := faixa_de(pontos)
	return {
		"faixa": faixa,
		"nivel": nivel,
		"label": str(nivel["nome"]),
		"color": nivel["cor"] as Color,
		"cor_faixa": cor_da_faixa(faixa),
	}
