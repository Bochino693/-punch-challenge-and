class_name RankingCelebration
extends RefCounted

## Uma colocação não é só um número: ela define o tamanho da cerimônia.
## Manter as quatro receitas aqui impede que 1º e 10º voltem a compartilhar
## som, quantidade de papel, batida e desenho por acidente.

static func para(posicao: int) -> Dictionary:
	if posicao == 1:
		return {
			"id": "campeao", "titulo": "NOVO CAMPEÃO", "subtitulo": "PRIMEIRO LUGAR DA ARENA",
			"som": "torcida_recorde", "volume": 1.0, "confetes": 680,
			"confete_lote": 22, "confete_intervalo": 0.11, "confete_duracao": 3.4,
			"canhoes": 3, "forca": 880.0, "tremor": 22.0, "raios": 28,
			"raio_selo": 296.0, "cor": Color("ffd34e"), "queda": 215.0,
			"emblemas": 3, "aneis": 3, "giro": 1.0,
		}
	if posicao <= 3:
		return {
			"id": "podio", "titulo": "VOCÊ ESTÁ NO PÓDIO", "subtitulo": ["", "", "SEGUNDO LUGAR", "TERCEIRO LUGAR"][posicao],
			"som": "torcida_podio", "volume": -1.0, "confetes": 390,
			"confete_lote": 17, "confete_intervalo": 0.15, "confete_duracao": 2.9,
			"canhoes": 2, "forca": 760.0, "tremor": 15.0, "raios": 20,
			"raio_selo": 286.0, "cor": Color("ff9f36"), "queda": 185.0,
			"emblemas": 2, "aneis": 2, "giro": 0.72,
		}
	if posicao <= 10:
		return {
			"id": "top10", "titulo": "ENTROU NO TOP 10", "subtitulo": "POSIÇÃO %d" % posicao,
			"som": "torcida_top10", "volume": -3.0, "confetes": 210,
			"confete_lote": 12, "confete_intervalo": 0.21, "confete_duracao": 2.4,
			"canhoes": 1, "forca": 660.0, "tremor": 10.0, "raios": 14,
			"raio_selo": 276.0, "cor": Color("33d7ff"), "queda": 160.0,
			"emblemas": 1, "aneis": 2, "giro": 0.48,
		}
	if posicao <= 20:
		return {
			"id": "top20", "titulo": "VOCÊ ENTROU", "subtitulo": "POSIÇÃO %d DO TOP 20" % posicao,
			"som": "torcida_top20", "volume": -5.0, "confetes": 95,
			"confete_lote": 8, "confete_intervalo": 0.30, "confete_duracao": 1.8,
			"canhoes": 0, "forca": 560.0, "tremor": 6.0, "raios": 9,
			"raio_selo": 266.0, "cor": Color("7be495"), "queda": 145.0,
			"emblemas": 0, "aneis": 1, "giro": 0.28,
		}
	return {}

static func valida(posicao: int) -> bool:
	return not para(posicao).is_empty()
