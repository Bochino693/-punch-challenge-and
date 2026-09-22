class_name ScoreTier
extends RefCounted

## OS OITO NÍVEIS DE GOLPE, E O QUE CADA UM FAZ A TELA FAZER.
##
## Esta tabela é a única fonte da verdade sobre "o que acontece quando o
## soco vale N pontos". Nome, cor, tremor, clarão, hit-stop, zoom,
## quantas ondas, quanta brasa, qual som: tudo num lugar só.
##
## POR QUE NUMA TABELA E NÃO EM `if`s ESPALHADOS. Oito níveis com efeito
## próprio dá oito blocos de código quase iguais, e é assim que dois
## níveis acabam com a mesma animação e só o texto mudando — que é
## exatamente o que não se quer. Numa tabela, duas linhas iguais saltam
## aos olhos.
##
## As faixas são FIXAS. Elas descrevem o espetáculo, não a dificuldade:
## quem regula a dificuldade é a curva (`ScoreCurve`), pela velocidade
## mínima, máxima e pelo expoente. Mexer na curva muda quantas pessoas
## chegam a cada nível; mexer aqui mudaria o que cada nível É.

## O teto da escala. Só um golpe que alcance ou passe a velocidade
## máxima calibrada, depois de validado, chega aqui.
const PERFEITO := 9999

const NIVEIS := [
	{
		"id": "LEVE", "min": 0, "max": 1799,
		"nome": "IMPACTO LEVE",
		"cor": Color("8697b4"),
		"som": "nivel_leve",
		"tremor": 4.0, "clarao": 0.10, "hitstop": 0.0, "zoom": 1.0,
		"ondas": 1, "onda_raio": 380.0,
		"faiscas": 14, "brasas": 0, "raios": 0, "estilhacos": 10, "chuva": 0,
		"poeira": 10, "rachaduras": false, "tunel": false, "palco": false,
		"festa_intervalo": 0.0,
	},
	{
		"id": "BOM", "min": 1800, "max": 3999,
		"nome": "BOM GOLPE",
		"cor": Color("ff4d5e"),
		"som": "nivel_bom",
		"tremor": 9.0, "clarao": 0.22, "hitstop": 0.0, "zoom": 1.0,
		"ondas": 2, "onda_raio": 520.0,
		"faiscas": 26, "brasas": 22, "raios": 0, "estilhacos": 0, "chuva": 0,
		"poeira": 8, "rachaduras": false, "tunel": false, "palco": false,
		"festa_intervalo": 0.0,
	},
	{
		"id": "FORTE", "min": 4000, "max": 6499,
		"nome": "GOLPE FORTE",
		"cor": Color("ffb31f"),
		"som": "nivel_forte",
		"tremor": 16.0, "clarao": 0.38, "hitstop": 0.0, "zoom": 1.0,
		"ondas": 2, "onda_raio": 700.0,
		"faiscas": 34, "brasas": 60, "raios": 4, "estilhacos": 0, "chuva": 0,
		"poeira": 0, "rachaduras": false, "tunel": false, "palco": false,
		"festa_intervalo": 0.0,
	},
	{
		"id": "EXPLOSIVO", "min": 6500, "max": 7999,
		"nome": "EXPLOSIVO",
		"cor": Color("fff2d0"),
		"som": "nivel_explosivo",
		"tremor": 22.0, "clarao": 0.62, "hitstop": 0.0, "zoom": 1.0,
		"ondas": 2, "onda_raio": 860.0,
		"faiscas": 46, "brasas": 90, "raios": 8, "estilhacos": 0, "chuva": 0,
		"poeira": 0, "rachaduras": true, "tunel": false, "palco": false,
		"festa_intervalo": 0.0,
	},
	{
		"id": "NOCAUTE", "min": 8000, "max": 8999,
		"nome": "NOCAUTE",
		"cor": Color("ff6a12"),
		"som": "nivel_nocaute",
		"tremor": 30.0, "clarao": 0.72, "hitstop": 0.095, "zoom": 1.07,
		"ondas": 3, "onda_raio": 980.0,
		"faiscas": 54, "brasas": 110, "raios": 12, "estilhacos": 0, "chuva": 30,
		"poeira": 0, "rachaduras": true, "tunel": false, "palco": false,
		"festa_intervalo": 1.15,
	},
	{
		"id": "PESO", "min": 9000, "max": 9699,
		"nome": "PESO-PESADO",
		"cor": Color("ff2d45"),
		"som": "nivel_peso",
		"tremor": 36.0, "clarao": 0.80, "hitstop": 0.110, "zoom": 1.10,
		"ondas": 3, "onda_raio": 1100.0,
		"faiscas": 64, "brasas": 150, "raios": 18, "estilhacos": 0, "chuva": 55,
		"poeira": 0, "rachaduras": true, "tunel": true, "palco": false,
		"festa_intervalo": 0.90,
	},
	{
		"id": "LENDARIO", "min": 9700, "max": 9998,
		"nome": "LENDÁRIO",
		"cor": Color("ffd200"),
		"som": "nivel_lendario",
		"tremor": 40.0, "clarao": 0.88, "hitstop": 0.110, "zoom": 1.12,
		"ondas": 4, "onda_raio": 1240.0,
		"faiscas": 80, "brasas": 190, "raios": 26, "estilhacos": 0, "chuva": 80,
		"poeira": 0, "rachaduras": true, "tunel": true, "palco": true,
		"festa_intervalo": 0.70,
	},
	{
		"id": "PERFEITO", "min": 9999, "max": 9999,
		"nome": "SOCO PERFEITO",
		"cor": Color("ffffff"),
		"som": "nivel_perfeito",
		"tremor": 46.0, "clarao": 1.00, "hitstop": 0.360, "zoom": 1.18,
		"ondas": 5, "onda_raio": 1400.0,
		"faiscas": 110, "brasas": 260, "raios": 40, "estilhacos": 0, "chuva": 120,
		"poeira": 0, "rachaduras": true, "tunel": true, "palco": true,
		"festa_intervalo": 0.55,
	},
]

## O nível de uma pontuação. Nunca devolve vazio: acima do teto cai no
## último, abaixo do piso cai no primeiro.
static func de(pontos: int) -> Dictionary:
	var p := clampi(pontos, 0, PERFEITO)
	for nivel in NIVEIS:
		if p <= int(nivel["max"]):
			return nivel
	return NIVEIS[NIVEIS.size() - 1]

static func indice_de(pontos: int) -> int:
	var p := clampi(pontos, 0, PERFEITO)
	for i in range(NIVEIS.size()):
		if p <= int(NIVEIS[i]["max"]):
			return i
	return NIVEIS.size() - 1

static func nome_de(pontos: int) -> String:
	return str(de(pontos)["nome"])

static func cor_de(pontos: int) -> Color:
	return de(pontos)["cor"] as Color

## O quanto o golpe avançou DENTRO do seu nível, de 0 a 1. É o que deixa
## dois nocautes diferentes lerem diferente sem inventar mais níveis.
static func avanco_no_nivel(pontos: int) -> float:
	var nivel := de(pontos)
	var piso := int(nivel["min"])
	var teto := int(nivel["max"])
	if teto <= piso:
		return 1.0
	return clampf(float(pontos - piso) / float(teto - piso), 0.0, 1.0)
