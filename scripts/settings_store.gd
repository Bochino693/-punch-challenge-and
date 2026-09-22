class_name SettingsStore
extends RefCounted

## Persistência em user:// com gravação segura: escreve num arquivo
## temporário e só então renomeia por cima do oficial. Se a máquina
## desligar no meio da escrita, o arquivo antigo continua intacto.

const PATH := "user://punch_challenge_settings.json"
const PATH_TMP := "user://punch_challenge_settings.tmp"

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

## ======================================================================
## GRAVAR NÃO PODE ACONTECER NO QUADRO DO PLACAR.
##
## `_fechar_rodada()` fecha o ranking, atualiza a estatística e GRAVA O
## ARQUIVO — tudo no mesmo quadro em que o número começa a subir na tela.
## Num PC com SSD isso passa despercebido. Na memória eMMC de um TV box,
## abrir, escrever e renomear são três chamadas de sistema que levam
## milissegundos de verdade, e elas caem exatamente no instante em que a
## tela mais precisa ser instantânea. É a descrição de "trava quando gera
## a pontuação".
##
## A montagem do texto continua na linha do jogo, e é de propósito: ela é
## barata (vinte linhas de ranking) e é o que congela o estado NAQUELE
## instante. O que vai para a linha de trabalho é só o disco.
##
## UMA GRAVAÇÃO PENDENTE DE CADA VEZ, e a última vence: um arquivo de
## ajustes não tem histórico, tem estado atual. Se três gravações forem
## pedidas enquanto uma está no ar, duas seriam escrita jogada fora — e
## disco desperdiçado é bateria e vida útil desperdiçadas num aparelho
## que fica ligado o dia inteiro.
static var _tarefa := -1
static var _pendente := ""

static func save_data_async(data: Dictionary) -> void:
	_pendente = JSON.stringify(data, "\t")
	_bombear()

static func _bombear() -> void:
	if _pendente.is_empty():
		return
	if _tarefa != -1:
		if not WorkerThreadPool.is_task_completed(_tarefa):
			return
		WorkerThreadPool.wait_for_task_completion(_tarefa)
		_tarefa = -1
	var texto := _pendente
	_pendente = ""
	_tarefa = WorkerThreadPool.add_task(_gravar.bind(texto), false, "ajustes: gravar")

## Chamado a cada quadro por quem grava, para a gravação pendente sair
## assim que a anterior terminar.
static func bombear() -> void:
	_bombear()

## Espera o disco antes de a máquina fechar. Sem isto, sair logo depois
## de mexer num ajuste poderia perder a última gravação.
static func encerrar() -> void:
	if _tarefa != -1:
		WorkerThreadPool.wait_for_task_completion(_tarefa)
		_tarefa = -1
	if not _pendente.is_empty():
		_gravar(_pendente)
		_pendente = ""

static func _gravar(texto: String) -> void:
	var tmp := FileAccess.open(PATH_TMP, FileAccess.WRITE)
	if tmp == null:
		return
	tmp.store_string(texto)
	tmp.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(PATH_TMP),
		ProjectSettings.globalize_path(PATH)
	)
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(PATH_TMP),
			ProjectSettings.globalize_path(PATH)
		)

static func save_data(data: Dictionary) -> bool:
	var tmp := FileAccess.open(PATH_TMP, FileAccess.WRITE)
	if tmp == null:
		return false
	tmp.store_string(JSON.stringify(data, "\t"))
	tmp.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(PATH_TMP),
		ProjectSettings.globalize_path(PATH)
	)
	if err != OK:
		# Windows não renomeia por cima de arquivo existente em alguns casos.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		err = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(PATH_TMP),
			ProjectSettings.globalize_path(PATH)
		)
	return err == OK
