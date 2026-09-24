class_name Paleta
extends RefCounted

## A PALETA DA MÁQUINA, NUM LUGAR SÓ.
##
## Tema SUPER BOXING, o mesmo do gabinete: azul-noite com raios roxo,
## magenta e azul, amarelo de faixa zebrada e o vermelho das luvas.
##
## POR QUE TUDO PASSA POR AQUI. Antes, cada arquivo carregava as suas
## próprias cores em hexadecimal — trocar o tema significava caçar
## `Color("...")` em seis arquivos e esquecer metade. Agora fundo, saco,
## medidor, moldura e textos leem daqui, então o tema é uma coisa só e
## muda de uma vez.

# ---------------------------------------------------------------- fundo
## Céu do salão: claro em cima, quente perto do chão.
const CEU_TOPO := Color("0b0620")
const CEU_BASE := Color("2a0f5c")
## Piso do palco e as linhas de perspectiva.
const PISO := Color("140a30")
const PISO_LINHA := Color("7a2eff")
## A luz do refletor, quente, caindo sobre o saco.
const LUZ := Color("ffd014")
## Creme do miolo do letreiro: o fundo sobre o qual a marca é montada.
const CREME := Color("f6fbff")

# ---------------------------------------------------------------- peças
const CARTAO := Color("1d1040")
const CARTAO_BORDA := Color("6a3cff")
## Sombra padrão das peças. Azulada, não cinza: sombra cinza sobre fundo
## azul-claro parece sujeira.
const SOMBRA := Color(0.0, 0.0, 0.0, 0.52)
## Fundo de campos e trilhos vazios.
const VAZIO := Color("150a2e")

# ---------------------------------------------------------------- tinta
const TINTA := Color("f4f8ff")        ## títulos e números
const TINTA_FRACA := Color("d9d1ff")  ## rótulos e apoio
const TINTA_LEVE := Color("a197d6")   ## legendas discretas

# ---------------------------------------------------------------- marca
## Tiradas da logo da casa: o vermelho do alvo e o azul do dardo.
const VERMELHO := Color("ff2a6d")
const CIANO := Color("ffd014")
const AMBAR := Color("ffd014")
const VERDE := Color("32f2a0")
const ROXO := Color("8a3cff")
const ROSA := Color("ff26a8")
## Azul profundo do bezel do letreiro e das bordas fortes.
const MARINHO := Color("1a0b3a")
## Contorno das letras de fliperama. Quase preto, e não o marinho: o
## contorno grosso só funciona se for MUITO mais escuro que o
## preenchimento — é ele que segura a letra sobre qualquer fundo.
const CONTORNO := Color("0e0624")
## O vidro escuro do visor de LED, e o brilho do reflexo em cima dele.
const VISOR_FUNDO := Color("140a2e")
const VISOR_VIDRO := Color("6a4cd8")

## Cores de festa — confete e fogos. Escurecidas o suficiente para
## aparecerem sobre um fundo claro; branco puro sumiria.
const FESTA := [
	Color("ff26a8"), Color("ffd014"), Color("fff9ef"),
	Color("46dcff"), Color("8a3cff"), Color("ff6a2a"),
]

# ---------------------------------------------------------------- saco
## O saco é VERMELHO VIVO, na cor do alvo da marca. Num salão claro um
## saco escuro vira uma mancha marrom no meio da tela — e é justamente
## ele que o cliente tem de ver do outro lado do corredor.
const SACO_VINIL := Color("e63950")
const SACO_COURO := Color("6b3a48")
const SACO_CONTORNO := Color("53202f")

## Fundo de um cartão colorido: a cor da vez, bem diluída no branco.
static func tinta_clara(cor: Color, forca := 0.12) -> Color:
	return CARTAO.lerp(cor, forca)

## Versão da cor com contraste suficiente para virar TEXTO sobre branco.
## Amarelos e cianos puros somem no branco; este escurecimento resolve
## sem obrigar cada tela a escolher um segundo tom à mão.
static func para_texto(cor: Color) -> Color:
	var luminancia := cor.r * 0.299 + cor.g * 0.587 + cor.b * 0.114
	if luminancia < 0.55:
		return cor.lightened((0.55 - luminancia) * 0.72)
	return cor

## Escolhe a tinta sem abandonar a cor da marca. Se o tom pedido nao
## atingir contraste de leitura, usa creme ou vinho quase preto — o que
## tiver maior contraste com o fundo. Evita vermelho sobre vermelho.
static func texto_sobre(fundo: Color, preferida: Color) -> Color:
	if _contraste(fundo, preferida) >= 4.5:
		return preferida
	var clara := CREME
	var escura := CONTORNO
	return clara if _contraste(fundo, clara) >= _contraste(fundo, escura) else escura

static func _canal_linear(valor: float) -> float:
	return valor / 12.92 if valor <= 0.04045 else pow((valor + 0.055) / 1.055, 2.4)

static func _luminancia(cor: Color) -> float:
	return 0.2126 * _canal_linear(cor.r) + 0.7152 * _canal_linear(cor.g) + 0.0722 * _canal_linear(cor.b)

static func _contraste(a: Color, b: Color) -> float:
	var la := _luminancia(a)
	var lb := _luminancia(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
