class_name RankingStore
extends RefCounted

const LIMIT := 20
## A NOTA MÍNIMA PARA ENTRAR NO TOP 20. Abaixo disto a rodada conta na
## estatística, mas não vira linha da tabela: o ranking é de quem bate.
## Vale também para o que já estava gravado — uma tabela que recusa 4800
## hoje e ainda mostra um 3200 de ontem estaria mentindo sobre a regra.
## (As fotos das linhas que saem ficam órfãs e a faxina as recolhe.)
const MINIMO := 5000
const PHOTO_DIR := "user://ranking_photos"

## A VERSÃO DO ESQUEMA DAS MARCAS GUARDADAS.
##
##   1 — escala 0 a 999, como saiu das primeiras máquinas;
##   2 — escala 0 a 9999.
##
## A conversão de 1 para 2 multiplica por dez. Ela precisa acontecer UMA
## VEZ e ficar registrada: sem a versão gravada, toda abertura
## multiplicaria de novo e o recorde da casa iria para o teto em três
## dias. É por isso que a versão é um número no arquivo, e não uma
## adivinhação a partir do maior valor encontrado — uma casa que nunca
## passou de 90 pontos ficaria indistinguível de uma já convertida.
const ESQUEMA := 2
const ESQUEMA_LEGADO := 1
const FATOR_LEGADO := 10

## `esquema` é a versão que estava gravada no disco. O padrão é a atual,
## para quem monta uma lista na mão (testes, ferramentas) não ser
## convertido sem querer.
static func migrate(raw: Variant, old_best := 0, esquema := ESQUEMA) -> Array[Dictionary]:
	var fator := FATOR_LEGADO if esquema <= ESQUEMA_LEGADO else 1
	var result: Array[Dictionary] = []
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				var entry := _sanitize_entry(item, fator)
				if int(entry["score"]) >= MINIMO:
					result.append(entry)
			else:
				var score := clampi(int(item) * fator, 0, GameDef.SCORE_MAX)
				if score >= MINIMO:
					result.append(_new_entry(score, "", "LEGADO"))
	if result.is_empty() and old_best * fator >= MINIMO:
		result.append(_new_entry(clampi(old_best * fator, 0, GameDef.SCORE_MAX), "", "LEGADO"))
	result.sort_custom(_higher_score)
	if result.size() > LIMIT:
		result.resize(LIMIT)
	return result

static func insert(entries: Array[Dictionary], score: int, photo_path := "", source := "SENSOR") -> Dictionary:
	if score < MINIMO:
		return {"entries": entries.duplicate(true), "position": 0, "dropped_photos": []}
	var next := entries.duplicate(true)
	var entry := _new_entry(clampi(score, 0, GameDef.SCORE_MAX), photo_path, source)
	# O id identifica a tentativa, então empates nunca roubam a posição
	# da pessoa errada como acontecia com Array.find(pontos).
	next.append(entry)
	next.sort_custom(_higher_score)
	var position := 0
	for i in range(next.size()):
		if str(next[i]["id"]) == str(entry["id"]):
			position = i + 1
			break
	var dropped: Array[String] = []
	while next.size() > LIMIT:
		var removed: Dictionary = next.pop_back()
		var path := str(removed.get("photo_path", ""))
		if not path.is_empty():
			dropped.append(path)
	if position > LIMIT:
		position = 0
	return {"entries": next, "position": position, "dropped_photos": dropped}

static func best(entries: Array[Dictionary]) -> int:
	return int(entries[0].get("score", 0)) if not entries.is_empty() else 0

static func score_at(entries: Array[Dictionary], index: int) -> int:
	if index < 0 or index >= entries.size():
		return 0
	return int(entries[index].get("score", 0))

## Devolve `true` quando a foto não está mais lá — apagada agora ou já
## ausente. `false` é arquivo que RESISTIU (em uso, sem permissão), e a
## faxina conta esses em vez de fingir que deu certo.
static func delete_photo(path: String) -> bool:
	if not path.begins_with(PHOTO_DIR):
		return true
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

static func clear_photos(entries: Array[Dictionary]) -> void:
	for entry in entries:
		delete_photo(str(entry.get("photo_path", "")))

## TODA FOTO QUE ESTÁ NA PASTA, e não só as vinte que a lista conhece.
##
## Esta diferença é o defeito inteiro: o ranking guarda vinte marcas, e
## quem entrou nele e depois caiu dele deixou a foto para trás. O
## "RANKING + FOTOS" varria a LISTA, então essas nunca saíam de lugar
## nenhum — numa casa que roda há um mês, o operador apagava vinte
## arquivos e deixava centenas. Quem lê a pasta encontra as centenas.
static func listar_fotos() -> PackedStringArray:
	var achadas := PackedStringArray()
	var pasta := DirAccess.open(PHOTO_DIR)
	if pasta == null:
		return achadas
	pasta.list_dir_begin()
	var nome := pasta.get_next()
	while nome != "":
		if not pasta.current_is_dir():
			achadas.append("%s/%s" % [PHOTO_DIR, nome])
		nome = pasta.get_next()
	pasta.list_dir_end()
	return achadas

static func _new_entry(score: int, photo_path: String, source: String) -> Dictionary:
	return {
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()],
		"score": score,
		"photo_path": photo_path,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"source": source,
	}

static func _sanitize_entry(value: Dictionary, fator := 1) -> Dictionary:
	var entry := value.duplicate(true)
	entry["id"] = str(entry.get("id", "%d-%d" % [Time.get_ticks_usec(), randi()]))
	entry["score"] = clampi(int(entry.get("score", 0)) * fator, 0, GameDef.SCORE_MAX)
	entry["photo_path"] = str(entry.get("photo_path", ""))
	entry["created_at"] = str(entry.get("created_at", ""))
	entry["source"] = str(entry.get("source", "LEGADO"))
	return entry

static func _higher_score(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a.get("score", 0))
	var score_b := int(b.get("score", 0))
	if score_a == score_b:
		return str(a.get("created_at", "")) < str(b.get("created_at", ""))
	return score_a > score_b
