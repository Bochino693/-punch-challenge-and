class_name Paleta
extends RefCounted

## A PALETA DA MÁQUINA, NUM LUGAR SÓ.
##
## Tema de arena: fundo escuro e peças azul-marinho fazem os números,
## fotografias e LEDs neon saltarem mesmo em um salão iluminado.
##
## POR QUE TUDO PASSA POR AQUI. Antes, cada arquivo carregava as suas
## próprias cores em hexadecimal — trocar o tema significava caçar
## `Color("...")` em seis arquivos e esquecer metade. Agora fundo, saco,
## medidor, moldura e textos leem daqui, então o tema é uma coisa só e
## muda de uma vez.

# ---------------------------------------------------------------- fundo
## Céu do salão: claro em cima, quente perto do chão.
const CEU_TOPO := Color("19060d")
const CEU_BASE := Color("4a0918")
## Piso do palco e as linhas de perspectiva.
const PISO := Color("220710")
const PISO_LINHA := Color("8f2330")
## A luz do refletor, quente, caindo sobre o saco.
const LUZ := Color("ffe044")
## Creme do miolo do letreiro: o fundo sobre o qual a marca é montada.
const CREME := Color("f6fbff")

# ---------------------------------------------------------------- peças
const CARTAO := Color("330c16")
const CARTAO_BORDA := Color("933042")
## Sombra padrão das peças. Azulada, não cinza: sombra cinza sobre fundo
## azul-claro parece sujeira.
const SOMBRA := Color(0.0, 0.0, 0.0, 0.52)
## Fundo de campos e trilhos vazios.
const VAZIO := Color("230912")

# ---------------------------------------------------------------- tinta
const TINTA := Color("f4f8ff")        ## títulos e números
const TINTA_FRACA := Color("ead1ca")  ## rótulos e apoio
const TINTA_LEVE := Color("bd9691")   ## legendas discretas

# ---------------------------------------------------------------- marca
## Tiradas da logo da casa: o vermelho do alvo e o azul do dardo.
const VERMELHO := Color("ff1934")
const CIANO := Color("ffdc27")
const AMBAR := Color("ffdc27")
const VERDE := Color("32f2a0")
const ROXO := Color("9965ff")
const ROSA := Color("ff3047")
## Azul profundo do bezel do letreiro e das bordas fortes.
const MARINHO := Color("260710")
## Contorno das letras de fliperama. Quase preto, e não o marinho: o
## contorno grosso só funciona se for MUITO mais escuro que o
## preenchimento — é ele que segura a letra sobre qualquer fundo.
const CONTORNO := Color("260710")
## O vidro escuro do visor de LED, e o brilho do reflexo em cima dele.
const VISOR_FUNDO := Color("220911")
const VISOR_VIDRO := Color("aa434c")

## Cores de festa — confete e fogos. Escurecidas o suficiente para
## aparecerem sobre um fundo claro; branco puro sumiria.
const FESTA := [
	Color("ff1934"), Color("ffda27"), Color("fff9ef"),
	Color("ff6230"), Color("ffb713"), Color("e91230"),
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
