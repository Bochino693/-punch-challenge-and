class_name CameraDoctor
extends Node

## Diagnostico Android sem comandos externos. A fonte de verdade e a lista
## publicada pelo CameraServer depois de o usuario aceitar CAMERA.

signal terminou

const RAMO_USUARIO := ""
const RAMO_MAQUINA := ""

var linhas: Array[String] = []
var rodando := false
var indices: Array[int] = []
var backend := "CameraServer Android"

func diagnosticar(resolver: bool, _caminho_antigo := "", _caminho_inspetor := "") -> void:
	if rodando:
		return
	rodando = true
	linhas.clear()
	indices.clear()
	if OS.get_name() != "Android":
		linhas.append("Esta edicao de camera foi preparada para Android.")
	else:
		if resolver and not OS.get_granted_permissions().has("android.permission.CAMERA"):
			OS.request_permission("CAMERA")
			linhas.append("Permissao CAMERA solicitada ao Android.")
		var feeds := CameraServer.feeds()
		for i in range(feeds.size()):
			indices.append(i)
			linhas.append("CAMERA %d: %s" % [i, str(feeds[i].get_name())])
		if feeds.is_empty():
			linhas.append("Android nao publicou nenhuma camera; confirme permissao e suporte Camera2/UVC.")
		else:
			linhas.append("%d camera(s) disponivel(is) pelo Android." % feeds.size())
	rodando = false
	call_deferred("emit_signal", "terminou")

static func ler_registro(_caminho: String) -> String:
	return ""

static func liberar_privacidade() -> PackedStringArray:
	return PackedStringArray()
