class_name CameraService
extends Node

## Webcam nativa. No Windows, CameraServerExtension usa Media Foundation e
## entrega os quadros diretamente ao Godot: sem Python, OpenCV, processo
## auxiliar ou JPEG intermediário.
##
## ------------------------------------------------------------------
## POR QUE A CÂMERA "NÃO FUNCIONA EM OUTRAS MÁQUINAS"
##
## O FATO QUE EXPLICA TUDO: **o Godot não tem suporte de câmera no
## Windows.** Não é um detalhe de configuração — o `CameraServer` do motor
## só é implementado em Linux, macOS, Android e iOS. No Windows,
## `CameraServer.feeds()` devolve uma lista VAZIA para sempre, haja webcam
## ou não.
##
## Ou seja: no Windows a câmera deste jogo depende INTEIRAMENTE da
## extensão nativa `CameraServerExtension` (a DLL em `addons/`). Com ela,
## funciona; sem ela, não existe câmera nenhuma — nem a embutida do
## notebook, que é exatamente o caso relatado.
##
## E A DLL SE PERDE COM FACILIDADE, por três motivos, nesta ordem:
##
##   1. COPIARAM SÓ O .EXE. O `.pck` e as bibliotecas nativas são arquivos
##      separados no pacote Windows. Copiar só o EXE deixa o jogo e a DLL
##      para trás; a unidade de distribuição é sempre o ZIP completo.
##   2. FALTA O MEDIA FOUNDATION. E **não** o Visual C++ Redistributable,
##      que é o que estava escrito aqui e estava errado. Lendo a tabela de
##      importações da DLL da câmera, ela só chama `MF.dll`, `MFPlat.dll`,
##      `MFReadWrite.dll`, `ole32`, `advapi32`, `kernel32` e `shlwapi` —
##      tudo do próprio Windows, nada de runtime da Microsoft. O que
##      derruba esta DLL é o Windows não ter Media Foundation: as edições
##      **N/KN** da Europa e o Windows Server sem o recurso de mídia
##      instalado. Quem precisa de `VCRUNTIME140.dll` é a OUTRA extensão,
##      a extensao serial usada pela antiga edicao de desktop.
##      esse arquivo ao lado do executável, o que dispensa instalar o
##      redistributable na máquina de destino.
##   3. WINDOWS ARM64. A extensão só traz `x86_64`. Num notebook Snapdragon
##      a DLL não carrega.
##
## O DEFEITO DE VERDADE ERA A MENSAGEM. Em todos os três casos a tela
## dizia "CONECTE UMA CÂMERA USB — BUSCANDO…", que é uma acusação falsa:
## manda procurar hardware quando o problema é software, e some com a
## única pista que resolveria em um minuto. `_diagnostico_da_plataforma`
## existe para isso — dizer qual dos três aconteceu.

const PHOTO_DIR := "user://ranking_photos"
const THUMB_SIZE := 640
const VIDA_MAXIMA_MS := 10000
const INTERVALO_AMOSTRA_MS := 500
const INTERVALO_OBTURADOR_MS := 66
const INTERVALO_NOVA_BUSCA_MS := 2500
const CONTRASTE_MINIMO := 0.04

enum Estado { DESLIGADA, SUBINDO, ACESA, EXAME, PARADA }

var enabled := true
var mirrored := true
var selected_index := 0
var estado := Estado.DESLIGADA
var status := "PROCURANDO CÂMERA"
var ultima_foto: Image = null

# Não tipar como CameraFeed: o addon documenta que o upcast desabilita
# get_formats/set_format no CameraFeedExtension.
var _feed = null
var _texture: CameraTexture = null
var _camera_extension = null
var _extension_iniciada := false
var _proxima_amostra_ms := 0
var _proxima_busca_ms := 0
var _last_frame_ms := 0
var _last_image: Image = null
var _sessao_aprovada := false
var _assinatura_do_quadro := 0
var _ultima_mudanca_ms := 0
var _ultima_quantidade_feeds := -1
var _android_bridge = null
var _proxima_permissao_usb_ms := 0
var _uvc_texture: ImageTexture = null
var _proxima_leitura_uvc_ms := 0
## Cadência de leitura da webcam, em ms. O jogo muda conforme a tela:
## rápida só quando a imagem aparece (ver `definir_ritmo`).
var intervalo_uvc_ms := 90

## A PRIVACIDADE JÁ FOI LIBERADA NESTA SESSÃO? Uma vez basta, e mais de
## uma seria mexer no registro a cada volta da busca.
var _privacidade_liberada := false
## Quando a busca começou. Só depois de alguns segundos sem achar nada é
## que vale a pena mexer na privacidade — uma webcam USB pode levar um
## tempo para o Windows montar.
var _busca_comecou_ms := 0
## OS NOMES DE CÂMERA QUE O SISTEMA JÁ MOSTRAVA. Serve para reconhecer a
## que ACABOU DE SER ESPETADA: num notebook, a que nasce depois do jogo
## aberto é a USB externa, sempre.
var _cameras_conhecidas := PackedStringArray()
var _lista_comparavel := false
## E as que apareceram DEPOIS: a lista que decide a preferência.
var _recem_chegadas := PackedStringArray()

var _melhor_imagem: Image = null
var _melhor_nota := -1.0
var _obturador_ate_ms := 0
var _obturador_teve_vida := false
var _obturador_foi_aberto := false

func _ready() -> void:
	_preparar_android_usb()
	_pedir_permissao_android()
	_acordar_servidor()
	if not CameraServer.camera_feed_added.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_added.connect(_on_camera_feeds_updated)
	if not CameraServer.camera_feed_removed.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_removed.connect(_on_camera_feeds_updated)
	if enabled:
		iniciar_captura()
	else:
		estado = Estado.DESLIGADA
		status = "CÂMERA DESATIVADA"
	set_process(true)

func _pedir_permissao_android() -> void:
	if OS.get_name() != "Android":
		return
	# A permissao declarada no APK ainda precisa ser aceita pelo operador.
	# A chamada e assincrona; a busca periodica adotara o feed assim que o
	# Android o publicar, sem pausar a animacao nem o audio.
	if not OS.get_granted_permissions().has("android.permission.CAMERA"):
		OS.request_permission("CAMERA")
	_requisitar_webcam_usb_android(true)

func _preparar_android_usb() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("PunchUsbSerial"):
		return
	_android_bridge = Engine.get_singleton("PunchUsbSerial")
	if _android_bridge != null and _android_bridge.has_method("prepareAndroidKiosk"):
		_android_bridge.call("prepareAndroidKiosk")

## QUEM ABRE A CÂMERA NO ANDROID — um só, nunca os dois.
##
## A ponte do plugin (API clássica do Android, com a UVC direta de reserva)
## enxerga a webcam USB das TV boxes Amlogic, que o CameraServer do Godot
## não lista. Quando a ponte vê câmera, o CameraServer fica de fora; quando
## só o CameraServer vê (HAL novo com câmera externa), a ponte fica de fora.
func _ponte_tem_camera() -> bool:
	return _android_bridge != null and _android_bridge.has_method("getSystemCameraCount") \
		and int(_android_bridge.call("getSystemCameraCount")) > 0

func _servidor_tem_camera() -> bool:
	return not CameraServer.feeds().is_empty()

func _requisitar_webcam_usb_android(forcar := false) -> void:
	if OS.get_name() != "Android" or _android_bridge == null:
		return
	if _feed != null or (_servidor_tem_camera() and not _ponte_tem_camera()):
		return
	var agora := Time.get_ticks_msec()
	if not forcar and agora < _proxima_permissao_usb_ms:
		return
	_proxima_permissao_usb_ms = agora + 5000
	if _android_bridge.has_method("requestUsbCameraAccess"):
		var resposta := str(_android_bridge.call("requestUsbCameraAccess"))
		if CameraServer.feeds().is_empty() and not resposta.is_empty():
			status = resposta

func _process(_delta: float) -> void:
	if not enabled or estado in [Estado.DESLIGADA, Estado.EXAME]:
		return
	var agora := Time.get_ticks_msec()
	# Em muitas TV boxes a webcam recebe permissão, mas nunca aparece no
	# CameraServer. O plugin Android abre UVC nativamente e mantém somente o
	# quadro mais recente; ler aqui não cria fila nem segura o impacto.
	if _amostrar_uvc_android(agora):
		return
	# Mesmo com uma câmera aberta, continua observando a lista. Assim uma
	# webcam USB conectada depois substitui automaticamente a integrada.
	var hora_de_buscar := agora >= _proxima_busca_ms
	if hora_de_buscar:
		_requisitar_webcam_usb_android()
		_proxima_busca_ms = agora + INTERVALO_NOVA_BUSCA_MS
		var quantidade := CameraServer.feeds().size()
		if quantidade != _ultima_quantidade_feeds:
			_ultima_quantidade_feeds = quantidade
			_adotar_camera_usb_preferida()
	if _feed == null:
		# Só repete a descoberta enquanto não há câmera. Uma câmera aberta
		# nunca é derrubada por relógio, evitando CONECTANDO/CONECTADA.
		if hora_de_buscar:
			_descobrir_cameras(true)
		return
	if agora < _proxima_amostra_ms:
		return
	var obturador_aberto := agora <= _obturador_ate_ms
	_proxima_amostra_ms = agora + (INTERVALO_OBTURADOR_MS if obturador_aberto else INTERVALO_AMOSTRA_MS)
	_amostrar_quadro()

func iniciar_captura() -> void:
	enabled = true
	estado = Estado.SUBINDO
	status = "PROCURANDO CÂMERA USB…"
	_iniciar_uvc_android()
	_descobrir_cameras(false)

func _iniciar_uvc_android() -> void:
	if OS.get_name() != "Android" or _android_bridge == null:
		return
	if _feed != null or (_servidor_tem_camera() and not _ponte_tem_camera()):
		return
	if _android_bridge.has_method("startUvcCamera"):
		_android_bridge.call("startUvcCamera")

func _amostrar_uvc_android(agora: int) -> bool:
	if OS.get_name() != "Android" or _android_bridge == null \
			or not _android_bridge.has_method("pollUvcFrame"):
		return false
	if agora < _proxima_leitura_uvc_ms:
		return _uvc_texture != null and ao_vivo()
	_proxima_leitura_uvc_ms = agora + intervalo_uvc_ms
	var dados_variant = _android_bridge.call("pollUvcFrame")
	if not dados_variant is PackedByteArray:
		return _uvc_texture != null and ao_vivo()
	var dados: PackedByteArray = dados_variant
	if dados.is_empty():
		if _android_bridge.has_method("getUvcStatus") and _feed == null:
			status = str(_android_bridge.call("getUvcStatus"))
		return _uvc_texture != null and ao_vivo()
	var largura := int(_android_bridge.call("getUvcFrameWidth"))
	var altura := int(_android_bridge.call("getUvcFrameHeight"))
	if largura <= 0 or altura <= 0 or dados.size() != largura * altura * 4:
		return false
	var imagem := Image.create_from_data(largura, altura, false, Image.FORMAT_RGBA8, dados)
	if imagem == null or imagem.is_empty():
		return false
	if _uvc_texture == null or _uvc_texture.get_width() != largura or _uvc_texture.get_height() != altura:
		_uvc_texture = ImageTexture.create_from_image(imagem)
	else:
		_uvc_texture.update(imagem)
	_registrar_quadro(imagem, agora)
	estado = Estado.ACESA
	status = "CÂMERA USB/UVC NATIVA — VÍDEO AO VIVO"
	return true

## Quantos ms entre quadros da webcam. Na contagem (prévia ao vivo) é
## rápido; durante o soco e o ranking a imagem não aparece, então a
## leitura quase para — e o plugin deixa de converter quadros que
## ninguém vai ver, liberando CPU para o impacto.
func definir_ritmo(ms: int) -> void:
	if ms == intervalo_uvc_ms:
		return
	intervalo_uvc_ms = ms
	_proxima_leitura_uvc_ms = mini(_proxima_leitura_uvc_ms, Time.get_ticks_msec() + ms)
	if _android_bridge != null and _android_bridge.has_method("setUvcFrameInterval"):
		_android_bridge.call("setUvcFrameInterval", ms)

func _descobrir_cameras(recriar_extensao: bool) -> void:
	_acordar_servidor()
	# Com a ponte Android dona da câmera, o CameraServer não abre nada:
	# dois donos para a mesma webcam derrubam os dois.
	if OS.get_name() == "Android" and _ponte_tem_camera():
		return
	# Primeiro aproveita qualquer feed já publicado. Isso cobre backends do
	# próprio sistema e evita recriar a extensão quando a câmera já está viva.
	if not CameraServer.feeds().is_empty():
		_abrir_feed_disponivel()
		return
	if OS.get_name() == "Windows" and ClassDB.class_exists(&"CameraServerExtension"):
		if recriar_extensao:
			_parar_feed()
			_camera_extension = null
			_extension_iniciada = false
		if not _extension_iniciada:
			_camera_extension = ClassDB.instantiate(&"CameraServerExtension")
			_extension_iniciada = _camera_extension != null
			if _camera_extension != null and _camera_extension.has_signal("permission_result"):
				var callback := Callable(self, "_on_permission_result")
				if not _camera_extension.is_connected("permission_result", callback):
					_camera_extension.connect("permission_result", callback)
			if _camera_extension != null and _camera_extension.has_method("permission_granted"):
				if not bool(_camera_extension.call("permission_granted")):
					status = "WINDOWS BLOQUEOU A CÂMERA — USE RESOLVER ACESSO"
					if _camera_extension.has_method("request_permission"):
						_camera_extension.call("request_permission")
					return
	_abrir_feed_disponivel()

## A EXTENSÃO NATIVA ESTÁ CARREGADA?
##
## `ClassDB` só conhece a classe se a DLL foi carregada de verdade — é a
## prova mais direta que existe, e não depende de procurar arquivo em
## disco nem de adivinhar caminho de instalação.
func extensao_nativa_presente() -> bool:
	return ClassDB.class_exists(&"CameraServerExtension")

## ONDE A DLL DA CÂMERA DEVERIA ESTAR, ao lado do executável.
##
## O `.gdextension` declara este caminho a partir de `res://`, e o
## exportador do Godot copia a biblioteca preservando a estrutura. Numa
## build exportada, portanto, ela fica exatamente aqui — e procurar o
## ARQUIVO é o que separa "não copiaram" de "copiaram e não carregou",
## que são dois problemas com duas soluções completamente diferentes.
const CAMINHO_DA_DLL := "addons/CameraServerExtension/x86_64/libcameraserver-extension.windows.dll"

func _dll_da_camera_esta_no_disco() -> bool:
	return FileAccess.file_exists(
		OS.get_executable_path().get_base_dir().path_join(CAMINHO_DA_DLL)
	)

## SEM CÂMERA: POR QUÊ, EM UMA FRASE QUE RESOLVE.
##
## Vazio quer dizer "é mesmo falta de câmera, procure uma". Qualquer outra
## coisa é a máquina apontando o próprio defeito.
##
## AQUI MORAVA UMA ACUSAÇÃO FALSA, e ela custou uma máquina inteira.
## Sem a extensão carregada, esta função devolvia "CÂMERA INDISPONÍVEL —
## RECONECTE O CABO USB" — mandando conferir o cabo quando o problema é
## que um arquivo não veio na cópia. É exatamente o defeito que o
## cabeçalho deste arquivo diz ter corrigido, com a frase trocada e a
## acusação intacta: quem leva o jogo para outro PC mexe no cabo, troca
## de porta USB, troca de câmera, e nada disso tem a menor chance de
## funcionar.
##
## Agora as três causas são separadas, e cada uma diz o que fazer.
func _diagnostico_da_plataforma() -> String:
	if OS.get_name() == "Android" and _android_bridge != null \
			and _android_bridge.has_method("getUsbCameraStatus"):
		return str(_android_bridge.call("getUsbCameraStatus"))
	if OS.get_name() != "Windows":
		return ""
	if extensao_nativa_presente():
		return ""
	# No editor não há "pasta exportada" para conferir, e a extensão pode
	# estar simplesmente desligada no projeto. Não se inventa causa.
	if OS.has_feature("editor"):
		return "EXTENSÃO DA CÂMERA NÃO CARREGADA NO EDITOR"
	if not _dll_da_camera_esta_no_disco():
		# O caso número um, de longe: copiaram só o .exe. O jogo abre
		# igual, sem câmera e sem erro — e por isso ninguém desconfia do
		# arquivo que ficou para trás.
		return "FALTA A DLL DA CÂMERA — COPIE A PASTA INTEIRA, NÃO SÓ O EXE"
	# O arquivo está lá e mesmo assim não carregou. Sobram duas causas, e
	# as duas são do WINDOWS da máquina, não do cabo nem da câmera.
	return "A DLL DA CÂMERA NÃO CARREGOU — WINDOWS SEM MEDIA FOUNDATION (EDIÇÃO N) OU ARM64"

## OS NOMES QUE UMA CÂMERA EMBUTIDA DE NOTEBOOK USA.
##
## Media Foundation entrega o nome amigável e nada mais — não diz em que
## barramento o dispositivo está, e mesmo que dissesse não ajudaria: a
## webcam embutida de um notebook TAMBÉM é USB, ligada num hub interno.
## O que separa uma da outra é o nome, e o nome vem do fabricante do
## MÓDULO, não da marca do notebook: Chicony, Sunplus, Quanta,
## Azurewave, Bison, Syntek e Realtek fabricam quase todas as embutidas
## do mercado, e nenhuma delas vende webcam avulsa.
const NOMES_DE_EMBUTIDA := [
	"integrated", "integrada", "built-in", "builtin", "internal",
	"user facing", "front", "facetime", "ir camera", "infrared",
	"windows hello", "easycamera", "truevision", "hd webcam",
	"chicony", "sunplus", "quanta", "azurewave", "bison", "syntek",
	"realtek", "vimicro", "sonix", "lite-on", "liteon", "acer crystal",
]

## E OS NOMES DE QUEM VENDE WEBCAM AVULSA.
const NOMES_DE_EXTERNA := [
	"usb", "logitech", "webcam", "external", "externa", "capture",
	"brio", "c920", "c922", "c930", "c270", "streamcam",
	"microsoft lifecam", "lifecam", "razer", "elgato", "aukey",
	"trust", "genius", "multilaser", "intelbras", "hikvision",
]

## ESCOLHE A WEBCAM EXTERNA, NÃO A CÂMERA DO NOTEBOOK.
##
## A regra vale mesmo quando o notebook já tem câmera: o gabinete usa uma
## USB, e é ela que tem de entrar no jogo. Quatro sinais, nesta ordem de
## peso:
##
##   1. ESPETADA AGORA. A câmera que NASCE com o jogo já aberto é a
##      externa — a embutida estava lá desde que o Windows subiu. É o
##      sinal mais forte que existe e não depende de nome nenhum;
##   2. o nome é de quem vende webcam avulsa;
##   3. o nome é de quem fabrica módulo embutido — penalidade pesada;
##   4. em empate, a última da lista: o Windows costuma enumerar a
##      embutida primeiro.
func _indice_camera_usb(feeds: Array) -> int:
	if feeds.is_empty():
		return -1
	var melhor := -1
	var melhor_nota := -100000
	for i in range(feeds.size()):
		var nome := _nome_do_feed(feeds[i])
		var nota := i * 10
		if _recem_chegadas.has(nome):
			nota += 50000
		for termo in NOMES_DE_EXTERNA:
			if str(termo) in nome:
				nota += 1000
		for termo in NOMES_DE_EMBUTIDA:
			if str(termo) in nome:
				nota -= 5000
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = i
	return melhor

func _nome_do_feed(feed) -> String:
	if feed == null or not feed.has_method("get_name"):
		return ""
	return str(feed.get_name()).strip_edges().to_lower()

## Compara a lista de agora com a de antes. Uma câmera que NASCE é, num
## notebook, a USB que alguém acabou de espetar — e é ela que o jogo
## quer, mesmo que o nome dela não diga nada.
func _notar_cameras_novas(feeds: Array) -> void:
	var agora := PackedStringArray()
	for feed in feeds:
		agora.append(_nome_do_feed(feed))
	if not _lista_comparavel:
		# A primeira lista é o retrato de partida: no gabinete a câmera já
		# está espetada quando o jogo abre, e nada ali é novidade.
		_lista_comparavel = true
		_cameras_conhecidas = agora
		return
	for nome in agora:
		if not _cameras_conhecidas.has(nome) and not _recem_chegadas.has(nome):
			_recem_chegadas.append(str(nome))
	_cameras_conhecidas = agora

## LIBERA O INTERRUPTOR DE PRIVACIDADE DA WEBCAM, UMA VEZ, SOZINHO.
##
## É uma das duas causas mais comuns de "não funciona nessa máquina", e a
## única que o jogo pode resolver sem ninguém. Não é escondido nem
## irreversível: é o mesmo valor que o aplicativo Configurações grava
## quando alguém move o interruptor à mão, no ramo do USUÁRIO — não pede
## administrador e não mexe na máquina inteira.
##
## Só acontece quando a extensão ESTÁ carregada e mesmo assim nenhuma
## câmera aparece por alguns segundos. Com a extensão faltando, mexer na
## privacidade não resolveria nada e só confundiria o diagnóstico.
func _tentar_liberar_privacidade() -> void:
	if _privacidade_liberada or OS.get_name() != "Windows":
		return
	if not extensao_nativa_presente():
		return
	var agora := Time.get_ticks_msec()
	if _busca_comecou_ms == 0:
		_busca_comecou_ms = agora
		return
	if agora - _busca_comecou_ms < ESPERA_ANTES_DE_LIBERAR_MS:
		return
	_privacidade_liberada = true
	var antes := CameraDoctor.ler_registro(CameraDoctor.RAMO_USUARIO + "\\NonPackaged")
	if antes.to_lower() == "allow":
		# Já estava liberado: o problema é outro, e dizer isso poupa o
		# operador de procurar no lugar errado.
		return
	CameraDoctor.liberar_privacidade()
	status = "PRIVACIDADE DA CÂMERA LIBERADA — PROCURANDO DE NOVO"
	_proxima_busca_ms = 0

func _adotar_camera_usb_preferida() -> void:
	if not enabled:
		return
	if OS.get_name() == "Android" and _ponte_tem_camera():
		return
	var feeds: Array = CameraServer.feeds()
	# REPARAR NAS NOVAS ANTES DE ESCOLHER. É aqui que uma webcam USB
	# espetada com o jogo já aberto substitui a embutida do notebook: sem
	# esta linha a lista mudaria e a preferência continuaria a mesma.
	_notar_cameras_novas(feeds)
	var preferida := _indice_camera_usb(feeds)
	if preferida < 0:
		return
	if _feed != null and selected_index == preferida:
		return
	_parar_feed()
	selected_index = preferida
	_abrir_feed_disponivel()

## SEGUNDOS DE BUSCA ANTES DE MEXER NA PRIVACIDADE.
##
## Uma webcam USB recém-espetada leva um instante para o Windows montar,
## e liberar o registro no primeiro quadro seria mexer numa coisa que
## talvez nem fosse o problema. Depois de três segundos sem nenhuma
## câmera, com a extensão carregada, a privacidade é o suspeito número
## um — e é o único que o jogo pode resolver sozinho.
const ESPERA_ANTES_DE_LIBERAR_MS := 3000

func _abrir_feed_disponivel() -> void:
	if not enabled or _feed != null:
		return
	var feeds: Array = CameraServer.feeds()
	if feeds.is_empty():
		estado = Estado.SUBINDO
		var motivo := _diagnostico_da_plataforma()
		status = motivo if not motivo.is_empty() else "CONECTE UMA CÂMERA USB — BUSCANDO…"
		_tentar_liberar_privacidade()
		return
	_notar_cameras_novas(feeds)
	selected_index = _indice_camera_usb(feeds)
	if selected_index < 0:
		return
	_feed = feeds[selected_index]
	_selecionar_formato_estavel()
	_feed.set_active(true)
	_texture = CameraTexture.new()
	_texture.camera_feed_id = _feed.get_id()
	_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	_proxima_amostra_ms = 0
	estado = Estado.SUBINDO
	status = "ABRINDO CÂMERA USB…"

## No Android prefere 640x480: a foto final tem 320 px e pedir 720p só
## aumenta USB, conversão e leitura da GPU no instante do impacto.
func _selecionar_formato_estavel() -> void:
	if _feed == null or not _feed.has_method("get_formats") or not _feed.has_method("set_format"):
		return
	var formatos: Array = _feed.get_formats()
	if formatos.is_empty():
		return
	var melhor := -1
	var melhor_nota := -1.0e30
	var alvo_largura := 640 if OS.get_name() == "Android" else 1280
	var alvo_altura := 480 if OS.get_name() == "Android" else 720
	for i in range(formatos.size()):
		var formato: Dictionary = formatos[i]
		var largura := int(formato.get("width", 0))
		var altura := int(formato.get("height", 0))
		var numerador := float(formato.get("framerate_numerator", 0))
		var denominador := maxf(float(formato.get("framerate_denominator", 1)), 1.0)
		var fps := numerador / denominador
		# A EXIGÊNCIA DE 20 fps DESCARTAVA CÂMERA DE NOTEBOOK.
		#
		# Muita câmera integrada não declara taxa de quadros: devolve
		# numerador 0 e o cálculo dá zero. Com o `continue`, TODOS os
		# formatos dela eram pulados e a escolha caía no formato 0 — que
		# em várias delas é o modo mais alto e mais lento que existe.
		# Taxa desconhecida não é taxa ruim; só não é informação.
		if largura <= 0 or altura <= 0:
			continue
		if fps > 0.0 and fps < 20.0:
			continue
		var distancia := absf(float(largura - alvo_largura)) + absf(float(altura - alvo_altura)) * 1.5
		var nota := -distancia + minf(fps, 30.0) * 20.0
		if largura > 1920 or altura > 1080:
			nota -= 10000.0
		if str(formato.get("format", "")) == "MJPG":
			nota += 250.0
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = i
	_feed.set_format(0 if melhor < 0 else melhor, {})

func _amostrar_quadro() -> void:
	if _texture == null:
		return
	var imagem := _texture.get_image()
	if imagem == null or imagem.is_empty():
		return
	_registrar_quadro(imagem, Time.get_ticks_msec())
	if estado != Estado.ACESA:
		estado = Estado.ACESA
		status = "CÂMERA CONECTADA — VÍDEO AO VIVO"

func _on_permission_result(granted: bool) -> void:
	if granted:
		status = "ACESSO LIBERADO — PROCURANDO CÂMERA…"
		procurar_de_novo()
	else:
		estado = Estado.PARADA
		status = "ACESSO À CÂMERA NEGADO PELO WINDOWS"

func _on_camera_feeds_updated(_id: int = 0) -> void:
	if enabled:
		call_deferred("_adotar_camera_usb_preferida")

func _acordar_servidor() -> void:
	if CameraServer.has_method("set_monitoring_feeds"):
		CameraServer.call("set_monitoring_feeds", true)

func set_enabled(value: bool) -> void:
	if value:
		if enabled and _feed != null:
			return
		iniciar_captura()
	else:
		enabled = false
		_parar_feed()
		_parar_uvc_android()
		_sessao_aprovada = false
		estado = Estado.DESLIGADA
		status = "CÂMERA DESATIVADA"

func cycle_camera() -> void:
	var total := CameraServer.feeds().size()
	selected_index = (selected_index + 1) % maxi(total, 1)
	_parar_feed()
	_sessao_aprovada = false
	estado = Estado.SUBINDO
	_abrir_feed_disponivel()

func procurar_de_novo() -> void:
	_parar_feed()
	_sessao_aprovada = false
	estado = Estado.SUBINDO
	status = "PROCURANDO CÂMERA USB…"
	_descobrir_cameras(true)

func entregar_ao_exame() -> void:
	# O PowerShell consulta PnP/privacidade; não abre o vídeo.
	pass

func terminar_exame() -> void:
	if enabled and _feed == null:
		procurar_de_novo()

func pedir_abertura() -> void:
	set_enabled(true)

func pedir_fechamento() -> void:
	set_enabled(false)

func pedir_exame() -> void:
	entregar_ao_exame()

func pronta() -> bool:
	return enabled and _sessao_aprovada and estado == Estado.ACESA and ao_vivo()

func estado_curto() -> String:
	return status

func preview_texture() -> Texture2D:
	return _uvc_texture if _uvc_texture != null else _texture

func available() -> bool:
	return pronta() and ao_vivo()

func tem_imagem() -> bool:
	return enabled and (_texture != null or _uvc_texture != null) and _sessao_aprovada

func ao_vivo() -> bool:
	return enabled and _last_frame_ms > 0 and Time.get_ticks_msec() - _last_frame_ms <= VIDA_MAXIMA_MS

func motivo_curto() -> String:
	if not enabled:
		return "CÂMERA DESLIGADA NA CENTRAL"
	if estado == Estado.PARADA:
		return status
	if _feed == null and _uvc_texture == null:
		return "NENHUMA CÂMERA USB ENCONTRADA"
	if not _sessao_aprovada:
		return "AGUARDANDO O PRIMEIRO QUADRO"
	return status

func ficha_da_ponte() -> String:
	if _uvc_texture != null:
		return "WEBCAM USB • UVC NATIVA ANDROID 640×480"
	if _feed == null:
		return "CAPTURA NATIVA — AGUARDANDO DISPOSITIVO"
	var nome := str(_feed.get_name()) if _feed.has_method("get_name") else "CÂMERA USB"
	return "%s • MEDIA FOUNDATION" % nome if OS.get_name() == "Windows" else "%s • CAPTURA NATIVA" % nome

## NÃO HÁ MAIS INSPETOR PARA DESEMBRULHAR.
##
## O diagnóstico antigo desembrulhava um script de sistema para o
## AppData só para poder chamar o PowerShell em cima dele. Hoje ele
## pergunta a mesma coisa ao `reg.exe`, ao `tasklist.exe` e ao
## `pnputil.exe`, que já estão no Windows e não precisam de arquivo
## nenhum (ver `CameraDoctor`). Esta função continua existindo, devolvendo
## vazio, porque quem chama o diagnóstico ainda a passa adiante.
func caminho_do_inspetor() -> String:
	return ""

func idade_do_quadro() -> int:
	return 999999 if _last_frame_ms <= 0 else Time.get_ticks_msec() - _last_frame_ms

func parada_ha() -> int:
	return 999999 if _ultima_mudanca_ms <= 0 else Time.get_ticks_msec() - _ultima_mudanca_ms

func abrir_obturador(janela_ms := 3200) -> void:
	_melhor_imagem = null
	_melhor_nota = -1.0
	_obturador_teve_vida = false
	_obturador_foi_aberto = true
	_obturador_ate_ms = Time.get_ticks_msec() + janela_ms
	_proxima_amostra_ms = 0

func _imagem_util(imagem: Image) -> bool:
	return _nota_da_imagem(imagem) >= CONTRASTE_MINIMO

func _nota_da_imagem(imagem: Image) -> float:
	return float(_medir_quadro(imagem)["nota"])

func _medir_quadro(imagem: Image) -> Dictionary:
	if imagem == null or imagem.is_empty() or imagem.get_width() < 8 or imagem.get_height() < 8:
		return {"nota": -1.0, "assinatura": 0}
	var claro := 0.0
	var escuro := 1.0
	var assinatura := 0
	for gx in range(8):
		for gy in range(6):
			var x := int((float(gx) + 0.5) / 8.0 * float(imagem.get_width()))
			var y := int((float(gy) + 0.5) / 6.0 * float(imagem.get_height()))
			var v := imagem.get_pixel(x, y).get_luminance()
			claro = maxf(claro, v)
			escuro = minf(escuro, v)
			assinatura = (assinatura * 31 + int(v * 255.0)) & 0x3FFFFFFF
	return {"nota": claro - escuro, "assinatura": assinatura}

func _registrar_quadro(imagem: Image, agora: int) -> void:
	if imagem == null or imagem.is_empty():
		return
	var medida := _medir_quadro(imagem)
	var assinatura := int(medida["assinatura"])
	if assinatura != _assinatura_do_quadro:
		_assinatura_do_quadro = assinatura
		_ultima_mudanca_ms = agora
		if agora <= _obturador_ate_ms:
			_obturador_teve_vida = true
	_last_image = imagem
	_last_frame_ms = agora
	_sessao_aprovada = true
	_oferecer_ao_obturador(imagem, float(medida["nota"]))

func _oferecer_ao_obturador(imagem: Image, nota_pronta := NAN) -> void:
	if imagem == null or Time.get_ticks_msec() > _obturador_ate_ms:
		return
	var nota := nota_pronta if not is_nan(nota_pronta) else _nota_da_imagem(imagem)
	if nota > _melhor_nota:
		_melhor_nota = nota
		_melhor_imagem = imagem.duplicate()

func capture_photo() -> String:
	var image: Image = null
	var captura_da_pose := _obturador_foi_aberto
	_obturador_foi_aberto = false
	_obturador_ate_ms = 0
	# Um rosto parado continua sendo uma foto válida. A versão anterior exigia
	# mudança dentro da janela do obturador e podia rejeitar um quadro estável.
	if _melhor_imagem != null and _melhor_nota >= CONTRASTE_MINIMO:
		image = _melhor_imagem
	elif _last_image != null and ao_vivo():
		image = _last_image.duplicate()
	elif not captura_da_pose:
		if _uvc_texture != null and _last_image != null:
			image = _last_image.duplicate()
		elif _texture != null:
			image = _texture.get_image()
	_melhor_imagem = null
	_melhor_nota = -1.0
	_obturador_teve_vida = false
	if image == null or image.is_empty():
		status = "CÂMERA SEM IMAGEM — %s" % motivo_curto()
		return ""
	if _nota_da_imagem(image) <= 0.0:
		status = "IMAGEM CHAPADA — TAMPA NA LENTE"
		return ""
	ultima_foto = image
	var path := "%s/player_%d.jpg" % [PHOTO_DIR, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PHOTO_DIR))
	# A opcao de espelho vale somente para a PREVIA, como um espelho de
	# academia. A foto salva preserva a orientacao real da camera; aplicar
	# flip_x aqui fazia a imagem mudar de lado depois do clique.
	WorkerThreadPool.add_task(_gravar_thumb_em_segundo_plano.bind(image.duplicate(), path))
	status = "FOTO OK — VÍDEO CONTINUA AO VIVO"
	return path

func _gravar_thumb_em_segundo_plano(imagem: Image, path: String) -> void:
	var side := mini(imagem.get_width(), imagem.get_height())
	if side <= 0:
		return
	var origin := Vector2i((imagem.get_width() - side) / 2, (imagem.get_height() - side) / 2)
	var recorte := imagem.get_region(Rect2i(origin, Vector2i(side, side)))
	recorte.resize(THUMB_SIZE, THUMB_SIZE, Image.INTERPOLATE_LANCZOS)
	recorte.save_jpg(path, 0.92)

func _parar_feed() -> void:
	if _feed != null:
		_feed.set_active(false)
	_feed = null
	_texture = null
	_last_image = null
	_last_frame_ms = 0

func _parar_uvc_android() -> void:
	if _android_bridge != null and _android_bridge.has_method("stopUvcCamera"):
		_android_bridge.call("stopUvcCamera")
	_uvc_texture = null
	_proxima_leitura_uvc_ms = 0

func _exit_tree() -> void:
	_parar_feed()
	_parar_uvc_android()
	_camera_extension = null
