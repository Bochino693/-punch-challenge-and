class_name AndroidUsbSerialLink
extends SerialLink

## Ponte entre o jogo e o plugin Android PunchUsbSerial.
##
## TROCA LIMPA, SEM TRAVAR O QUADRO:
##   • abrir, fechar e listar a USB rodam numa thread do plugin; aqui só
##     se lê o resultado pronto;
##   • UMA chamada JNI por quadro (`pollSerial`) traz o estado da porta e
##     todas as linhas recebidas; `is_open()` e `portas_promissoras()`
##     respondem do que já foi lido, sem atravessar o JNI de novo;
##   • a escrita vai para uma fila limitada do plugin e volta na hora.
##
## Com um plugin antigo (sem `pollSerial`) cai no caminho de antes.

const FECHADA := 0
const ABRINDO := 1
const ABERTA := 2

var _plugin: Object = null
var _motivo := "plugin PunchUsbSerial nao foi carregado"
var _assincrono := false
var _estado := FECHADA
var _porta := ""
var _porta_pedida := ""
var _portas := PackedStringArray()

func _init() -> void:
	if Engine.has_singleton("PunchUsbSerial"):
		_plugin = Engine.get_singleton("PunchUsbSerial")
		_motivo = ""
		# SÓ AS CHAMADAS QUE TODA VERSÃO DO PLUGIN TEM. Perguntar por uma
		# função que o plugin do APK não tem é erro de script no Android;
		# o caminho síncrono funciona com o plugin antigo e com o novo (o
		# novo só faz o trabalho lento em segundo plano por dentro).
		_assincrono = false

func nome_do_caminho() -> String:
	return CAMINHO_ANDROID_USB

func available() -> bool:
	return _plugin != null

func pode_insistir() -> bool:
	return _plugin != null

func descricao() -> String:
	return "USB ANDROID"

func motivo_da_falta() -> String:
	if _plugin != null:
		return str(_plugin.call("getLastError"))
	return _motivo + " — gere o APK com Gradle e o addon habilitado"

## A lista vem do cache do plugin (a enumeração roda lá, em segundo plano).
func list_ports() -> PackedStringArray:
	if _plugin == null:
		return PackedStringArray()
	var texto := str(_plugin.call("listPorts"))
	_portas = PackedStringArray(texto.split("\n", false)) if not texto.is_empty() else PackedStringArray()
	return _portas

func portas_promissoras() -> PackedStringArray:
	return _portas

func open_port(port: String, baud: int = GameDef.SERIAL_BAUD) -> bool:
	if _plugin == null:
		return false
	_porta_pedida = port
	if not bool(_plugin.call("openPort", port, baud)):
		_motivo = str(_plugin.call("getLastError"))
		return false
	_motivo = ""
	if _assincrono:
		# Pedido aceito; o "opened" sai do `poll()` quando a porta abrir.
		_estado = ABRINDO
	else:
		_estado = ABERTA
		_porta = port
		opened.emit(port)
	return true

func aguardando_permissao() -> bool:
	return "autoriz" in _motivo.to_lower()

func close_port() -> void:
	if _plugin == null:
		return
	_plugin.call("closePort")
	_mudar_estado(FECHADA)

## Aberta ou abrindo: enquanto abre, o motor de conexão espera (e não
## tenta outra porta por cima).
func is_open() -> bool:
	return _estado != FECHADA

func send_line(line: String) -> bool:
	return _estado == ABERTA and bool(_plugin.call("writeLine", line))

func poll() -> void:
	if _plugin == null:
		return
	if not _assincrono:
		_poll_antigo()
		return
	var lote := str(_plugin.call("pollSerial"))
	var linhas := lote.split("\n", false)
	if linhas.is_empty():
		return
	var cabeca := linhas[0].split("|", true, 1)
	var erro := cabeca[1] if cabeca.size() > 1 else ""
	if not erro.is_empty():
		_motivo = erro
	_mudar_estado(int(cabeca[0]))
	for i in range(1, linhas.size()):
		var limpa := linhas[i].strip_edges()
		if not limpa.is_empty():
			line_received.emit(limpa)

func _poll_antigo() -> void:
	if _estado == ABERTA and not bool(_plugin.call("isOpen")):
		_mudar_estado(FECHADA)
	var lote := str(_plugin.call("pollLines"))
	for linha in lote.split("\n", false):
		var limpa := str(linha).strip_edges()
		if not limpa.is_empty():
			line_received.emit(limpa)

func _mudar_estado(novo: int) -> void:
	if novo == _estado:
		return
	var antes := _estado
	_estado = novo
	if novo == ABERTA:
		_motivo = ""
		_porta = _porta_pedida
		opened.emit(_porta)
	elif novo == FECHADA and antes != FECHADA:
		var porta := _porta if not _porta.is_empty() else _porta_pedida
		_porta = ""
		closed.emit(porta)

func encerrar() -> void:
	close_port()

func soltar_para_sair() -> void:
	if _plugin != null:
		_plugin.call("closePort")
