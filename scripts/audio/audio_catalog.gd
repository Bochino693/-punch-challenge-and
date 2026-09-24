extends RefCounted
## Catálogo único dos arquivos sonoros. AudioBank cuida da reprodução.
const FALLBACK := {
	"credit": "res://assets/audio/credit.wav",
	"start": "res://assets/audio/start.wav",
	"count": "res://assets/audio/count.wav",
	"go": "res://assets/audio/go.wav",
	"hit": "res://assets/audio/hit.wav",
	"tick": "res://assets/audio/tick.wav",
	"charge": "res://assets/audio/charge.wav",
	"win": "res://assets/audio/win.wav",
	"medium": "res://assets/audio/medium.wav",
	"lose": "res://assets/audio/lose.wav",
	"error": "res://assets/audio/error.wav",
	"menu": "res://assets/audio/menu.wav",
	"record": "res://assets/audio/record.wav",
	"legendary": "res://assets/audio/legendary.wav",
}
## Sons que existem só como arquivo em `assets/audio/arcade/` e não têm
## um par no FALLBACK. Os oito níveis entram aqui: eles nasceram já na
## mesa nova e nunca tiveram versão antiga.
const EXTRA := [
	"music", "shutter", "ranking", "score_loop",
	"ranking_neutral_1", "ranking_neutral_2", "ranking_neutral_3",
	"ranking_burst", "disconnect_alert",
	"nivel_leve", "nivel_bom", "nivel_forte", "nivel_explosivo",
	"nivel_nocaute", "nivel_peso", "nivel_lendario", "nivel_perfeito",
	"start_negado", "armado", "couro", "subgrave",
	# A ARENA TROUXE SONS PRÓPRIOS. O soco já tinha o couro e o
	# subgrave — o que faltava era o CORPO: o baque de quem leva, a
	# queda na lona e a plateia reagindo. Sem eles o lutador aparecia
	# na tela mas o ouvido continuava batendo num saco de areia.
	"arena_corpo", "arena_queda", "arena_publico", "torcida_desdenho",
	"torcida_recorde", "torcida_podio", "torcida_top10", "torcida_top20",
	# A torcida longa do fim de rodada: vaia (o jogador perdeu e o
	# lutador tira onda) e festa (o jogador ganhou, o ginásio pega fogo).
	"torcida_vaia", "torcida_festa",
	# E a torcida do MEIO da luta: empurra quem está batendo, nunca vaia.
	"torcida_incentivo",
	# Vozes especiais da rodada de dois golpes.
	"not_supress", "good_player",
]
const LOOPS := ["music", "charge", "score_loop"]
const ROOT := "res://assets/audio/arcade/"

static func path_for(cue: String) -> String:
	return ROOT + cue + ".wav"

## A QUE MESA CADA SOM VAI.
##
## Quatro barramentos, e não um só, porque eles precisam de volumes
## independentes E de um abaixar a voz para o outro aparecer:
##
##   Music   a trilha, que toca o dia inteiro e tem de sumir de baixo do
##           veredito sem parar;
##   Impact  o soco e os oito níveis — o que precisa doer;
##   UI      crédito, START, contagem, obturador: informação, e informação
##           não pode ser abafada pela festa;
##   SFX     o resto.
##
## Um som que não aparecer aqui vai para SFX.
const BARRAMENTOS := {
	"music": "Music",
	"hit": "Impact", "subgrave": "Impact", "couro": "Impact",
	"nivel_leve": "Impact", "nivel_bom": "Impact", "nivel_forte": "Impact",
	"nivel_explosivo": "Impact", "nivel_nocaute": "Impact", "nivel_peso": "Impact",
	"nivel_lendario": "Impact", "nivel_perfeito": "Impact",
	"arena_corpo": "Impact", "arena_queda": "Impact", "arena_publico": "SFX",
	"not_supress": "Impact", "good_player": "SFX",
	"credit": "UI", "start": "UI", "start_negado": "UI", "menu": "UI",
	"error": "UI", "disconnect_alert": "UI",
	"count": "UI", "go": "UI", "tick": "UI",
	"shutter": "UI", "armado": "UI", "round_bell": "UI",
}
const BARRAMENTO_PADRAO := "SFX"

static func bus_for(cue: String) -> String:
	return str(BARRAMENTOS.get(cue, BARRAMENTO_PADRAO))
