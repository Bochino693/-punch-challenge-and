class_name AudioBank
extends Node

## Central de sons. Cada som vira um AudioStreamPlayer filho deste nó;
## se o arquivo não existir (projeto recém-clonado antes da importação),
## o player fica mudo em vez de derrubar o jogo.

const Catalog = preload("res://scripts/audio/audio_catalog.gd")
const SONS = Catalog.FALLBACK

var _players: Dictionary = {}
var music_target := -80.0

## OS QUATRO BARRAMENTOS, criados em tempo de execução.
##
## Em código e não no arquivo do projeto porque o `default_bus_layout.tres`
## é um recurso binário que ninguém consegue revisar num diff: uma mesa de
## som alterada por engano some sem deixar rastro. Aqui, criar um
## barramento é uma linha que se lê.
const MESA := ["Music", "SFX", "Impact", "UI"]

## Volume de cada barramento, em dB. `Music` e `SFX` são o que o operador
## regula na Central; `Impact` e `UI` acompanham o `SFX`.
var volume_musica := 0.0
var volume_efeitos := 0.0

## O ABAFAMENTO DA TRILHA.
##
## Quando a voz da máquina fala — contagem, foto, golpe, veredito — a
## música desce e volta sozinha. Sem isso, a trilha e o veredito disputam
## a mesma faixa de frequência e nenhum dos dois se entende; abaixar de
## vez seria perder o que segura a pessoa na frente da máquina.
var _duck_db := 0.0
var _duck_alvo := 0.0
var _duck_ate_ms := 0

func _process(delta: float) -> void:
	# O abafamento sobe rápido e volta devagar: é assim que um compressor
	# de rádio se comporta, e é o que o ouvido aceita sem perceber.
	if _duck_ate_ms > 0 and Time.get_ticks_msec() > _duck_ate_ms:
		_duck_alvo = 0.0
		_duck_ate_ms = 0
	var passo := delta * (60.0 if _duck_alvo < _duck_db else 14.0)
	_duck_db = move_toward(_duck_db, _duck_alvo, passo)
	_aplicar_volume_dos_barramentos()

	var player: AudioStreamPlayer = _players.get("music")
	if player != null:
		player.volume_db = move_toward(player.volume_db, music_target, delta * 45.0)
		if music_target <= -79.0 and player.volume_db <= -79.0:
			player.stop()

## Abafa a trilha por `segundos`, em `db` abaixo do normal.
func duck(db: float, segundos: float) -> void:
	_duck_alvo = minf(_duck_alvo, -absf(db))
	_duck_ate_ms = maxi(_duck_ate_ms, Time.get_ticks_msec() + int(segundos * 1000.0))

func set_volumes(musica_db: float, efeitos_db: float) -> void:
	volume_musica = clampf(musica_db, -40.0, 6.0)
	volume_efeitos = clampf(efeitos_db, -40.0, 6.0)
	_aplicar_volume_dos_barramentos()

func _aplicar_volume_dos_barramentos() -> void:
	_set_bus_db("Music", volume_musica + _duck_db)
	_set_bus_db("SFX", volume_efeitos)
	# O impacto fica um pouco acima do resto dos efeitos: é o som que
	# justifica a máquina existir, e ele precisa passar por cima da festa.
	_set_bus_db("Impact", volume_efeitos + 1.5)
	_set_bus_db("UI", volume_efeitos)

func _set_bus_db(nome: String, db: float) -> void:
	var i := AudioServer.get_bus_index(nome)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, clampf(db, -60.0, 12.0))

## Cria os barramentos que ainda não existem e liga todos ao Master.
func _montar_mesa() -> void:
	for nome in MESA:
		if AudioServer.get_bus_index(nome) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, nome)
		AudioServer.set_bus_send(i, "Master")

func music(level: float) -> void:
	music_target = level
	var player: AudioStreamPlayer = _players.get("music")
	if player != null and level > -79.0 and not player.playing:
		player.volume_db = -45.0
		player.play()

func silence() -> void:
	music_target = -80.0
	for player in _players.values():
		player.stop()

## Corta os efeitos e MANTÉM a música tocando.
##
## A tela de abertura chamava `silence`, que para tudo — e por isso a
## máquina ficava muda justamente na tela que passa o dia inteiro ligada
## tentando chamar alguém. Uma máquina calada no salão parece desligada.
func attract(level: float) -> void:
	for nome in _players:
		if nome != "music":
			(_players[nome] as AudioStreamPlayer).stop()
	music(level)

func start_score_loop() -> void:
	if not _players.has("score_loop"):
		var player := AudioStreamPlayer.new()
		player.bus = Catalog.bus_for("score_loop")
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = 22050
		var pcm := PackedByteArray()
		pcm.resize(44100)
		for i in range(22050):
			var t := float(i) / 22050.0
			var envelope := 0.65 + 0.35 * cos(TAU * 8.0 * t)
			var sample := (sin(TAU * 220.0 * t) + 0.25 * sin(TAU * 440.0 * t)) * envelope * 0.22
			pcm.encode_s16(i * 2, int(sample * 32767.0))
		stream.data = pcm
		player.stream = stream
		add_child(player)
		_players["score_loop"] = player
	play("score_loop", -12.0)

func score_progress(progress: float) -> void:
	var player: AudioStreamPlayer = _players.get("score_loop")
	if player != null:
		player.pitch_scale = lerpf(0.85, 1.8, clampf(progress, 0.0, 1.0))

func _ready() -> void:
	_montar_mesa()
	for nome in SONS:
		var player := AudioStreamPlayer.new()
		player.name = "Som_%s" % nome
		var caminho: String = SONS[nome]
		if ResourceLoader.exists(caminho):
			player.stream = load(caminho)
		player.bus = Catalog.bus_for(nome)
		add_child(player)
		_players[nome] = player
	# WAVs originais; leitura direta também funciona na primeira importação.
	for nome in SONS.keys() + Catalog.EXTRA:
		var path := Catalog.path_for(nome)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var stream: AudioStreamWAV = load(path).duplicate() if ResourceLoader.exists(path) else AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
		if stream == null:
			continue
		if nome in Catalog.LOOPS:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			# O FIM DO LOOP SAI DA DURAÇÃO, E NÃO DO TAMANHO EM BYTES.
			#
			# `data` é o buffer JÁ CODIFICADO, e o Godot importa WAV em
			# QOA por padrão — comprimido. Dividir os bytes por dois
			# (supondo PCM de 16 bits mono) dava um ponto de loop cinco
			# vezes menor que o arquivo: a música de doze segundos
			# reiniciava a cada dois e meio, o que fazia a trilha soar
			# curta e repetitiva sem que nada parecesse quebrado.
			#
			# `get_length()` já vem em segundos, qualquer que seja o
			# formato, então esta conta continua certa se um dia o
			# projeto trocar de compressão.
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		var player: AudioStreamPlayer = _players.get(nome)
		if player == null:
			player = AudioStreamPlayer.new()
			player.bus = Catalog.bus_for(nome)
			add_child(player)
			_players[nome] = player
		player.stream = stream
	_criar_sino_de_round()

## Sino próprio, preparado no arranque e nunca no quadro em que o soco é
## liberado. Assim o APK não depende de um arquivo extra e a primeira
## chamada não sofre criação/decodificação tardia em uma TV Box.
func _criar_sino_de_round() -> void:
	if _players.has("round_bell"):
		return
	const TAXA := 22050
	const DURACAO := 1.20
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TAXA
	var total := int(TAXA * DURACAO)
	var pcm := PackedByteArray()
	pcm.resize(total * 2)
	for i in range(total):
		var t := float(i) / float(TAXA)
		var env := exp(-t * 3.1)
		var ataque := exp(-t * 70.0) * sin(TAU * 3100.0 * t) * 0.24
		var metal := (
			sin(TAU * 620.0 * t) * 0.55
			+ sin(TAU * 947.0 * t) * 0.34
			+ sin(TAU * 1315.0 * t) * 0.20
		) * env
		pcm.encode_s16(i * 2, int(clampf((metal + ataque) * 0.78, -1.0, 1.0) * 32767.0))
	stream.data = pcm
	var player := AudioStreamPlayer.new()
	player.name = "Som_round_bell"
	player.bus = Catalog.bus_for("round_bell")
	player.stream = stream
	add_child(player)
	_players["round_bell"] = player

## SOM PEDIDO COM O JOGO SAINDO NÃO É SOM: É UM ERRO NO CONSOLE.
##
## Na saída, `_exit_tree` do jogo fecha a porta serial, e fechar a porta
## avisa quem estava ouvindo — inclusive este banco, que tenta tocar o
## som de desconexão. Só que a essa altura os tocadores já estão saindo
## da árvore, e o Godot recusa com um erro. Ninguém ia ouvir esse som de
## qualquer jeito: o jogo está fechando. Quem toca é quem está de pé.
func play(nome: String, volume_db: float = 0.0) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null and player.stream != null and player.is_inside_tree():
		player.volume_db = volume_db
		player.play()

func stop(nome: String) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null:
		player.stop()

func playing(nome: String) -> bool:
	var player: AudioStreamPlayer = _players.get(nome)
	return player != null and player.is_inside_tree() and player.playing
