class_name ArenaFrases
extends RefCounted

## O QUE A MÁQUINA GRITA QUANDO O SOCO ACERTA.
##
## Um jogo de console antigo nunca diz só "8300 pontos": ele diz "ELE NÃO
## VIU ESSE!". A frase é o que transforma um número numa cena, e é de
## graça — não custa um triângulo e é o que a fila lembra depois.
##
## POR QUE UMA TABELA POR NÍVEL E NÃO UMA LISTA SÓ. Frase sorteada de um
## monte único diria "APAGOU AS LUZES!" para um tapa de 400 pontos, e
## nada destrói mais rápido a graça da coisa do que o elogio que não
## combina com o que a pessoa fez. Cada nível de `ScoreTier` tem o seu
## grupo, e o grupo inteiro é do mesmo tamanho de golpe.
##
## POR QUE VÁRIAS POR NÍVEL. Quem joga duas vezes seguidas ouve as duas.
## Uma frase por nível vira um rótulo; quatro viram um narrador.
##
## A ESCOLHA NÃO É ALEATÓRIA A CADA QUADRO. `de_golpe` recebe uma
## semente — na prática o número de socos já dados — porque o `_draw`
## roda sessenta vezes por segundo e uma frase sorteada ali piscaria
## trocando de texto. Mesma semente, mesma frase, o tempo todo em que ela
## estiver na tela.

const GOLPES := {
	"LEVE": [
		"ELE NEM PISCOU!",
		"ISSO FOI UM CUMPRIMENTO",
		"AINDA ESTÁ AQUECENDO?",
		"A GUARDA NEM ABRIU",
	],
	"BOM": [
		"AGORA SIM!",
		"ELE SENTIU ESSE!",
		"BOA PEGADA, CAMPEÃO",
		"O GINÁSIO ACORDOU",
	],
	"FORTE": [
		"A GUARDA ABRIU!",
		"ELE CAMBALEOU!",
		"QUE ESTRONDO!",
		"ISSO VAI DOER AMANHÃ",
	],
	"EXPLOSIVO": [
		"O PROTETOR VOOU!",
		"ISSO FOI UM TIRO!",
		"A PLATEIA LEVANTOU!",
		"ELE VIU ESTRELAS!",
	],
	"NOCAUTE": [
		"DIRETO NO QUEIXO!",
		"APAGOU AS LUZES!",
		"ELE NÃO VIU ESSE!",
		"BOA NOITE, LUTADOR",
	],
	"PESO": [
		"ISSO NÃO FOI SOCO, FOI TROVÃO",
		"A LONA PEDIU ARREGO!",
		"O RINGUE INTEIRO OUVIU",
		"PESO-PESADO DE VERDADE!",
	],
	"LENDARIO": [
		"ISSO VAI PARA O MURAL!",
		"NINGUÉM ACREDITOU NO QUE VIU",
		"LENDA DA CASA!",
		"A ARENA NUNCA MAIS SERÁ A MESMA",
	],
	"PERFEITO": [
		"PERFEIÇÃO ABSOLUTA!",
		"A MÁQUINA PEDIU DESCULPAS",
		"NÃO EXISTE NADA DEPOIS DISSO",
		"O SOCO PERFEITO ACONTECEU AQUI",
	],
}

## O que a arena diz enquanto o punho não vem. Provocação, não instrução:
## a instrução já está escrita logo acima, em letra grande.
const ESPERA := [
	"ELE ESTÁ TE ESPERANDO…",
	"MIRE NO QUEIXO",
	"MOSTRE O QUE VOCÊ TEM",
	"A ARENA É SUA",
	"SEM MEDO. ELE AGUENTA",
]

## Quando o lutador vai à lona, a frase é uma só e é grande: é o momento
## do jogo, não mais um comentário.
const NOCAUTE := [
	"NOCAUTE!",
	"ELE FOI À LONA!",
	"CONTA ATÉ DEZ!",
]

## O estado do adversário, lido do medidor de dano. É o texto das barras
## laterais — sem ele, duas colunas coloridas não dizem o que medem.
const DANOS := [
	{"ate": 0.001, "texto": "INTEIRO"},
	{"ate": 0.25,  "texto": "MARCADO"},
	{"ate": 0.55,  "texto": "ABALADO"},
	{"ate": 0.85,  "texto": "CAMBALEANDO"},
	{"ate": 1.01,  "texto": "POR UM FIO"},
]

static func _sortear(lista: Array, semente: int) -> String:
	if lista.is_empty():
		return ""
	return str(lista[absi(semente) % lista.size()])

static func de_golpe(id_do_nivel: String, semente: int) -> String:
	return _sortear(GOLPES.get(id_do_nivel, GOLPES["BOM"]), semente)

static func de_espera(semente: int) -> String:
	return _sortear(ESPERA, semente)

static func de_nocaute(semente: int) -> String:
	return _sortear(NOCAUTE, semente)

static func de_dano(dano: float) -> String:
	for faixa in DANOS:
		if dano <= float(faixa["ate"]):
			return str(faixa["texto"])
	return str(DANOS[DANOS.size() - 1]["texto"])


## QUANDO QUEM BATEU PERDEU: o lutador tira onda e a frase acompanha.
const DERROTA := [
	"ELE ESTÁ RINDO DE VOCÊ!",
	"A TORCIDA VAIOU • REVANCHE?",
	"FOI SÓ ISSO? ELE QUER MAIS",
	"ELE DANÇOU NA SUA FRENTE",
	"VAIA GERAL • BATA MAIS FORTE",
]

static func de_derrota(semente: int) -> String:
	return str(DERROTA[posmod(semente, DERROTA.size())])
