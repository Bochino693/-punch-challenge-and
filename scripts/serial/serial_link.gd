class_name SerialLink
extends RefCounted

## Interface serial da edição Android/TV Box. O Arduino é acessado pelo
## USB Host do Android (`AndroidUsbSerialLink`); fora do Android não há
## caminho e a Central diz isso.

signal line_received(line: String)
signal opened(port: String)
signal closed(port: String)

const CAMINHO_ANDROID_USB := "android_usb"
const CAMINHO_NENHUM := "nenhuma"

static func create_best() -> SerialLink:
	# O singleton só existe no APK; aceitar ele fora do Android permite
	# testar o motor de conexão com um plugin simulado na bancada.
	if OS.get_name() == "Android" or Engine.has_singleton("PunchUsbSerial"):
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

## Saída do jogo: solta o aparelho SEM ESPERAR por ele.
func soltar_para_sair() -> void:
	encerrar()

func encerrar() -> void:
	pass

## Verdade enquanto o Android espera a pessoa autorizar o USB da placa.
func aguardando_permissao() -> bool:
	return false
