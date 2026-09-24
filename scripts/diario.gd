class_name Diario
extends RefCounted

## O DIÁRIO DA INICIALIZAÇÃO.
##
## Cada etapa da abertura do jogo (carregar, montar, aquecer, acordar a
## câmera, pedir permissão, abrir o Arduino) é gravada NA HORA num arquivo
## pequeno. Se a TV Box travar numa delas, o arquivo fica parado ali — e na
## próxima vez que o jogo abre ele sabe, e mostra, em que etapa parou.
## Sem cabo, sem computador, sem adivinhar.

const ARQUIVO := "user://diario_inicializacao.txt"
const FIM := "PRONTO"

static var _inicio_ms := 0
static var _travou_em := ""
static var _aberto := false
static var _pronto := false

## Começa um diário novo, lendo antes o da vez anterior.
static func inicio() -> void:
	if _aberto:
		return
	_aberto = true
	_inicio_ms = Time.get_ticks_msec()
	if FileAccess.file_exists(ARQUIVO):
		var velho := FileAccess.open(ARQUIVO, FileAccess.READ)
		if velho != null:
			var ultima := ""
			while not velho.eof_reached():
				var linha := velho.get_line().strip_edges()
				if not linha.is_empty():
					ultima = linha
			velho.close()
			if not ultima.is_empty() and not ultima.ends_with(FIM):
				_travou_em = ultima
	var novo := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if novo != null:
		novo.store_line("0.0s INICIO")
		novo.close()

## Grava uma etapa (com o tempo desde o início).
static func marca(etapa: String) -> void:
	if not _aberto or _pronto:
		return
	var f := FileAccess.open(ARQUIVO, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%.1fs %s" % [float(Time.get_ticks_msec() - _inicio_ms) / 1000.0, etapa])
	f.close()

## A inicialização terminou inteira: daqui em diante não se grava mais.
static func pronto() -> void:
	marca(FIM)
	_pronto = true

## Onde a inicialização ANTERIOR parou, se ela não chegou ao fim.
static func travou_em() -> String:
	return _travou_em
