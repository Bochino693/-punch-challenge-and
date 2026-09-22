class_name AndroidUsbSerialLink
extends SerialLink

## Adaptador entre o jogo e o plugin PunchUsbSerial. O plugin trabalha em
## thread propria; poll() apenas recolhe linhas prontas, sem bloquear efeitos.

var _plugin: Object = null
var _porta := ""
var _motivo := "plugin PunchUsbSerial nao foi carregado"

func _init() -> void:
	if Engine.has_singleton("PunchUsbSerial"):
		_plugin = Engine.get_singleton("PunchUsbSerial")
		_motivo = ""

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

func list_ports() -> PackedStringArray:
	if _plugin == null:
		return PackedStringArray()
	var texto := str(_plugin.call("listPorts"))
	if texto.is_empty():
		return PackedStringArray()
	return PackedStringArray(texto.split("\n", false))

func portas_promissoras() -> PackedStringArray:
	return list_ports()

func open_port(port: String, baud: int = GameDef.SERIAL_BAUD) -> bool:
	if _plugin == null:
		return false
	if bool(_plugin.call("openPort", port, baud)):
		_porta = port
		emit_signal("opened", port)
		return true
	_motivo = str(_plugin.call("getLastError"))
	return false

func close_port() -> void:
	if _plugin == null:
		return
	var anterior := _porta
	_plugin.call("closePort")
	_porta = ""
	if not anterior.is_empty():
		emit_signal("closed", anterior)

func is_open() -> bool:
	return _plugin != null and bool(_plugin.call("isOpen"))

func send_line(line: String) -> bool:
	return _plugin != null and bool(_plugin.call("writeLine", line))

func poll() -> void:
	if _plugin == null:
		return
	var lote := str(_plugin.call("pollLines"))
	if lote.is_empty():
		return
	for linha in lote.split("\n", false):
		var limpa := str(linha).strip_edges()
		if not limpa.is_empty():
			emit_signal("line_received", limpa)

func encerrar() -> void:
	close_port()
