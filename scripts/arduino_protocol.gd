class_name ArduinoProtocol
extends RefCounted

## Protocolo serial da variante optica LM393.
## Linhas terminadas em \n, campos separados por vírgula. Mensagens
## incompletas ou com valores inválidos são descartadas aqui — o jogo
## nunca recebe lixo. Ver docs/PROTOCOLO_SERIAL.md.

## parse(line) -> Dictionary com ao menos a chave "type".
## type == "" significa "linha inválida, ignore".
static func parse(line: String) -> Dictionary:
	var parts := line.split(",")
	if parts.is_empty():
		return {"type": ""}
	var head := parts[0].strip_edges().to_upper()
	match head:
		"READY":
			# READY,PUNCH_OPTICAL,V1
			return {
				"type": "READY",
				"device": parts[1] if parts.size() > 1 else "",
				"version": parts[2] if parts.size() > 2 else "",
			}
		"CALIBRATING":
			if parts.size() != 2 or not parts[1].is_valid_int():
				return {"type": ""}
			return {"type": "CALIBRATING", "percent": clampi(parts[1].to_int(), 0, 100)}
		"CALIBRATED":
			if parts.size() != 4:
				return {"type": ""}
			var offs := _floats(parts, 1, 3)
			if offs.is_empty():
				return {"type": ""}
			return {"type": "CALIBRATED", "offsets": offs}
		"PONG":
			return {"type": "PONG"}
		"PINS":
			# PINS,<start>,<credito> — 1 é APERTADO. O estado cru dos dois
			# pinos, para a Central mostrar ao vivo: se o número não muda
			# quando o botão é apertado, o problema é antes do firmware.
			if parts.size() not in [3, 4]:
				return {"type": ""}
			return {
				"type": "PINS",
				"start": parts[1].strip_edges() == "1",
				"credit": parts[2].strip_edges() == "1",
				"config": parts.size() == 4 and parts[3].strip_edges() == "1",
			}
		"BUTTON":
			if parts.size() != 2:
				return {"type": ""}
			var botao := parts[1].strip_edges().to_upper()
			if botao not in ["START", "CREDIT", "CONFIG"]:
				return {"type": ""}
			return {"type": "BUTTON", "button": botao}
		"TELEMETRY":
			# TELEMETRY,ax,ay,az,gx,gy,gz,velocidade,pico_g
			if parts.size() != 9:
				return {"type": ""}
			var vals := _floats(parts, 1, 8)
			if vals.is_empty():
				return {"type": ""}
			return {
				"type": "TELEMETRY",
				"accel": Vector3(vals[0], vals[1], vals[2]),
				"gyro": Vector3(vals[3], vals[4], vals[5]),
				"velocity": vals[6],
				"peak_g": vals[7],
			}
		"HIT":
			# HIT,velocidade_pico,aceleracao_pico,duracao_ms,eixo
			if parts.size() != 5:
				return {"type": ""}
			var vals := _floats(parts, 1, 3)
			if vals.is_empty():
				return {"type": ""}
			var eixo := parts[4].strip_edges().to_upper()
			if eixo not in ["X", "Y", "Z", "O"]:
				return {"type": ""}
			# Valores impossíveis não viram golpe.
			if vals[0] < 0.0 or vals[0] > 60.0 or vals[1] < 0.0 or vals[1] > 17.0 or vals[2] <= 0.0 or vals[2] > 5000.0:
				return {"type": ""}
			return {"type": "HIT", "speed": vals[0], "accel": vals[1], "duration_ms": vals[2], "axis": eixo}
		"REJECT":
			# REJECT,<motivo>,<pico_g>,<duracao_ms>,<giro_dps>,<velocidade>
			#
			# A PLACA VIU ALGO E DESCARTOU, e diz por quê. É o que
			# transforma "nada acontece" — que é o mesmo sintoma para seis
			# causas diferentes — numa frase que aponta o limiar errado.
			if parts.size() != 6:
				return {"type": ""}
			var nums := _floats(parts, 2, 4)
			if nums.is_empty():
				return {"type": ""}
			return {
				"type": "REJECT",
				"reason": parts[1].strip_edges().to_upper(),
				"peak_g": nums[0],
				"duration_ms": nums[1],
				"gyro_dps": nums[2],
				"speed": nums[3],
			}
		"STATUS":
			# STATUS,<medindo>,<forca_agora_g>,<gatilho_g>
			#
			# `forca_agora` é a aceleração já sem a gravidade. Parada, a
			# máquina mostra perto de zero; um soco passa de 3. É o número
			# que se confere a olho, sem interpretar nada.
			if parts.size() != 4:
				return {"type": ""}
			var st := _floats(parts, 2, 2)
			if st.is_empty():
				return {"type": ""}
			return {
				"type": "STATUS",
				"measuring": parts[1].strip_edges() == "1",
				"force_g": st[0],
				"trigger_g": st[1],
			}
		"NOISE":
			# NOISE,<ruido_g>,<ruido_dps> — o piso medido nesta montagem.
			if parts.size() != 3:
				return {"type": ""}
			var nz := _floats(parts, 1, 2)
			if nz.is_empty():
				return {"type": ""}
			return {"type": "NOISE", "noise_g": nz[0], "noise_dps": nz[1]}
		"SATURATION":
			if parts.size() != 2:
				return {"type": ""}
			var fonte := parts[1].strip_edges().to_upper()
			if fonte != "ACCEL" and fonte != "GYRO":
				return {"type": ""}
			return {"type": "SATURATION", "source": fonte}
		"ERROR":
			return {"type": "ERROR", "code": parts[1].strip_edges().to_upper() if parts.size() > 1 else "DESCONHECIDO"}
		"MOTOR":
			# MOTOR,<estado>,<posicao>,<resta_ms>
			#
			# O firmware manda esta linha a CADA mudança, e nunca em
			# repetição: quem a recebe sabe o que o motor está fazendo
			# sem precisar perguntar. `resta` é quanto falta do curso em
			# milissegundos, e serve para a Central mostrar uma barra que
			# anda de verdade em vez de um "aguarde" parado.
			if parts.size() != 4:
				return {"type": ""}
			for i in range(1, 4):
				if not parts[i].strip_edges().is_valid_int():
					return {"type": ""}
			return {
				"type": "MOTOR",
				"estado": clampi(parts[1].strip_edges().to_int(), 0, 2),
				"posicao": clampi(parts[2].strip_edges().to_int(), 0, 2),
				"resta_ms": maxi(parts[3].strip_edges().to_int(), 0),
			}
		"OK":
			return {"type": "OK", "detail": parts[1].strip_edges().to_upper() if parts.size() > 1 else ""}
	return {"type": ""}

## Extrai `count` floats a partir do índice `from`. Se qualquer campo
## não for float válido, devolve array vazio (mensagem rejeitada).
static func _floats(parts: PackedStringArray, from: int, count: int) -> Array:
	var out: Array = []
	for i in range(from, from + count):
		if i >= parts.size() or not parts[i].strip_edges().is_valid_float():
			return []
		out.append(parts[i].strip_edges().to_float())
	return out

## O TETO DE PLAUSIBILIDADE, EM m/s — E POR QUE ELE MORA AQUI.
##
## O firmware recusa como `CURTO` qualquer pulso mais rápido do que o
## `pulsoMinUs` que recebe no CONFIG, e recusa SEPARADAMENTE qualquer
## velocidade acima de `max(8, velocidadeMax * 2,2)`. São dois limites
## para a mesma ideia — "isto é rápido demais para ser um soco" — e,
## quando discordam, o mais apertado vence sem dizer o nome dele: a placa
## responde `CURTO` a um soco perfeitamente válido, e do lado de fora
## parece que o sensor simplesmente não viu.
##
## Esta função é a regra, escrita uma vez só. `pulso_minimo_ms` a
## converte em tempo usando a largura da palheta, e é assim que os dois
## limites passam a tropeçar exatamente no mesmo soco.
static func velocidade_teto(max_speed: float) -> float:
	return maxf(8.0, maxf(max_speed, 0.0) * 2.2)

## O PULSO MÍNIMO QUE O FIRMWARE DEVE EXIGIR, em milissegundos.
##
## A palheta atravessa a fenda: a velocidade é a largura dela dividida
## pela duração do bloqueio. Quanto mais rápido o soco, MAIS CURTO o
## pulso — então o pulso mínimo é um limite SUPERIOR de velocidade, e não
## de força. É essa inversão que fazia a regulagem à mão virar armadilha:
## um número aumentado "para ficar mais sensível" apertava o teto e
## passava a recusar justamente os socos fortes.
##
## Por isso ele é DERIVADO, e nunca escolhido a dedo: largura da palheta
## e teto calibrado entram, milissegundos saem.
static func pulso_minimo_ms(flag_width_m: float, max_speed: float) -> float:
	var largura := clampf(flag_width_m, 0.005, 0.100)
	var ms := largura / velocidade_teto(max_speed) * 1000.0
	return clampf(ms, 0.15, 20.0)

## A JANELA QUE ESTA MONTAGEM CONSEGUE MEDIR, em m/s, dada a largura da
## palheta e o pulso mínimo em vigor. A Central mostra isto ao lado dos
## dois ajustes, porque "20 mm" e "1,75 ms" não dizem nada sozinhos —
## "mede de 0,07 a 11,4 m/s" diz tudo, e diz na hora se a faixa de
## pontuação cabe dentro do que o sensor enxerga.
static func janela_medivel(flag_width_m: float, min_pulse_ms: float) -> Vector2:
	var largura := clampf(flag_width_m, 0.005, 0.100)
	var rapida := largura / (clampf(min_pulse_ms, 0.15, 20.0) / 1000.0)
	# 300 ms é o `PULSO_MAX_US` do firmware: mais lento que isso ele
	# descarta como `SUSTENTADO` — a palheta parou dentro da fenda.
	var lenta := largura / 0.300
	return Vector2(lenta, rapida)

static func build_config(
	polarity: String, flag_width_m: float, min_speed: float, min_pulse_ms: float, max_speed := 0.0
) -> String:
	var eixo := polarity.to_upper()
	if eixo not in ["A", "H", "L"]:
		eixo = "A"
	var raio := clampf(flag_width_m, 0.005, 0.100)
	var vmin := clampf(min_speed, 0.1, 20.0)
	var amin := clampf(min_pulse_ms, 0.15, 20.0)
	if max_speed <= 0.0:
		return "CONFIG,%s,%.3f,%.2f,%.2f" % [eixo, raio, vmin, amin]
	# O QUINTO CAMPO É O TETO DAS FITAS DE LED.
	#
	# A placa precisa dele para saber que velocidade enche a coluna
	# inteira quando estiver se virando sozinha — com o PC desligado, ou
	# nos décimos de segundo entre o golpe e o primeiro `LEDS` do jogo.
	# É opcional nos dois lados: firmware novo aceita CONFIG de quatro
	# campos, e este método só manda o quinto quando ele existe.
	var vmax := clampf(max_speed, vmin + 0.5, 40.0)
	return "CONFIG,%s,%.3f,%.2f,%.2f,%.2f" % [eixo, raio, vmin, amin, vmax]

## A ALTURA DA COLUNA DE LED, em por mil.
##
## Mandada enquanto o placar sobe na tela: assim a fita acompanha o NÚMERO
## subindo, e não o golpe cru. As duas coisas no mesmo compasso é o que
## faz a máquina parecer uma peça só, em vez de um monitor com uma fita
## pendurada do lado.
static func build_leds(fracao: float) -> String:
	return "LEDS,%d" % clampi(int(round(clampf(fracao, 0.0, 1.0) * 1000.0)), 0, 1000)


# ====================================================================
# O MOTOR DO SACO
# ====================================================================

## Os três estados que o firmware relata, e os três lugares onde o saco
## pode estar. Os números são o protocolo; os nomes são para gente.
const MOTOR_PARADO := 0
const MOTOR_DESCENDO := 1
const MOTOR_SUBINDO := 2
const POS_DESCONHECIDA := 0
const POS_EM_CIMA := 1
const POS_EM_BAIXO := 2

static func nome_do_estado(estado: int) -> String:
	match estado:
		MOTOR_DESCENDO: return "DESCENDO"
		MOTOR_SUBINDO: return "SUBINDO"
		_: return "PARADO"

static func nome_da_posicao(posicao: int) -> String:
	match posicao:
		POS_EM_CIMA: return "EM CIMA"
		POS_EM_BAIXO: return "EM BAIXO"
		_: return "POSIÇÃO DESCONHECIDA"

## `sentido` é "DESCE", "SOBE" ou "PARA". Qualquer outra coisa vira
## "PARA": num comando que liga um motor, o padrão seguro é desligar.
static func build_motor(sentido: String) -> String:
	var s := sentido.strip_edges().to_upper()
	if s != "DESCE" and s != "SOBE" and s != "ESTADO":
		s = "PARA"
	return "MOTOR,%s" % s

## O curso em milissegundos, a pausa de inversão e se há fim de curso
## ligado. Os limites são os MESMOS do firmware, de propósito: um valor
## que o jogo aceita e a placa recusa vira uma configuração que parece
## ter sido gravada e não foi.
static func build_motor_config(curso_ms: int, pausa_ms: int, fim_de_curso: bool) -> String:
	return "MOTOR,CONFIG,%d,%d,%d" % [
		clampi(curso_ms, 200, 15000), clampi(pausa_ms, 50, 2000), 1 if fim_de_curso else 0
	]
