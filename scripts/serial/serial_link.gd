class_name SerialLink
extends RefCounted

## Interface serial da edicao Android/TV Box. Esta variante nunca cria
## processos externos: o Arduino e acessado pelo USB Host do Android.

signal line_received(line: String)
signal opened(port: String)
signal closed(port: String)

const CAMINHO_ANDROID_USB := "android_usb"
# Mantidos apenas para compatibilidade de leitura de configuracoes antigas.
const CAMINHO_NENHUM := "nenhuma"
const CAMINHO_NATIVO := "nativa_inativa_no_android"
const CAMINHO_PONTE := "ponte_inativa_no_android"

static func create_best(_evitar := "", _preferir := "") -> SerialLink:
	if OS.get_name() == "Android":
		var usb := AndroidUsbSerialLink.new()
		if usb.available():
			return usb
		var vazio := NullSerialLink.new()
		vazio.explicar(usb.motivo_da_falta())
		return vazio
	var fora_do_android := NullSerialLink.new()
	fora_do_android.explicar("esta edicao usa USB Host do Android; execute-a numa TV Box Android")
	return fora_do_android

func nome_do_caminho() -> String:
	return CAMINHO_NENHUM

func available() -> bool:
	return false

func pode_insistir() -> bool:
	return false

func descricao() -> String:
	return "nenhuma"

func motivo_da_falta() -> String:
	return ""

func list_ports() -> PackedStringArray:
	return PackedStringArray()

func portas_promissoras() -> PackedStringArray:
	return PackedStringArray()

func open_port(_port: String, _baud: int = GameDef.SERIAL_BAUD) -> bool:
	return false

func close_port() -> void:
	pass

func is_open() -> bool:
	return false

func send_line(_line: String) -> bool:
	return false

func poll() -> void:
	pass

func encerrar() -> void:
	pass
