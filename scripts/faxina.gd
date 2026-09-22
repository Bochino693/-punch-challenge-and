class_name Faxina
extends RefCounted

## APAGAR AS FOTOS SEM PARAR O JOGO.
##
## "RANKING + FOTOS" apagava tudo dentro do clique: o laço percorria a
## lista e só devolvia a máquina depois do último arquivo. Com as vinte
## fotos do ranking ninguém nota. Só que a pasta guarda MUITO mais do
## que vinte — cada pessoa que entrou no ranking e depois caiu dele
## deixou a foto para trás, e nada nunca apagava essas. Numa casa que
## roda há um mês são centenas de arquivos ocupando disco, e o "zerar"
## não limpava nenhum deles: apagava só as vinte que estavam na lista.
##
## Varrer a pasta inteira conserta isso e cria o problema oposto —
## centenas de remoções dentro de um clique congelam a tela no meio do
## salão, com fila esperando. Por isso o trabalho sai fatiado, algumas
## por quadro, com o número aparecendo na Central.
##
## A ORDEM IMPORTA, e é ela que faz isto não poder quebrar o jogo: a
## lista e o arquivo de configuração são gravados ANTES de sumir o
## primeiro arquivo. Se a energia cair no meio da faxina, o que sobra é
## foto órfã na pasta — lixo que a próxima faxina leva. O contrário
## (apagar antes de gravar) deixaria o ranking apontando para fotos que
## não existem mais, e aí a tela de recordes quebra de verdade.
##
## Nada aqui bloqueia: o jogo continua aceitando soco, crédito e START
## o tempo todo, e sair da Central não interrompe a faxina.

## Quantos arquivos por quadro. Oito remoções custam bem menos de um
## milissegundo num disco comum e menos de três no pior HD mecânico que
## ainda aparece em gabinete — cabe com folga no orçamento de 16 ms.
const POR_QUADRO := 8

var total := 0
var feitas := 0
var rodando := false

var _fila: PackedStringArray = PackedStringArray()
var _erros := 0

## Abre a faxina com a lista JÁ TIRADA da pasta. A lista é um retrato do
## instante do clique, de propósito: uma foto tirada DEPOIS do reset é
## de uma partida nova e não tem nada a ver com o que se mandou apagar.
func comecar(arquivos: PackedStringArray) -> void:
	_fila = arquivos.duplicate()
	total = _fila.size()
	feitas = 0
	_erros = 0
	rodando = total > 0

## Uma fatia. Chamada uma vez por quadro; sem faxina aberta não faz nada
## e não custa nada.
func passo(orcamento := POR_QUADRO) -> void:
	if not rodando:
		return
	var restam := orcamento
	while restam > 0 and feitas < total:
		var caminho := _fila[feitas]
		feitas += 1
		restam -= 1
		if not RankingStore.delete_photo(caminho):
			# Arquivo em uso, sem permissão, ou já apagado. Contar e
			# seguir: uma foto teimosa não pode travar a faxina inteira,
			# e a próxima faxina tenta de novo.
			_erros += 1
	if feitas >= total:
		rodando = false

## Quanto já foi, de 0 a 1. Sem faxina aberta devolve 1 — a barra da
## Central desenha "pronto", não "nada feito".
func progresso() -> float:
	if total <= 0:
		return 1.0
	return clampf(float(feitas) / float(total), 0.0, 1.0)

## A linha que a Central mostra.
func ficha() -> String:
	if total <= 0:
		return "nenhuma foto para apagar"
	if rodando:
		return "apagando fotos: %d de %d" % [feitas, total]
	if _erros > 0:
		return "%d fotos apagadas  •  %d resistiram (a próxima faxina tenta de novo)" % [
			total - _erros, _erros
		]
	return "%d fotos apagadas" % total

func erros() -> int:
	return _erros
