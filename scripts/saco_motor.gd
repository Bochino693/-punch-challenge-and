class_name SacoMotor
extends RefCounted

## O MOTOR QUE BAIXA E LEVANTA O SACO — o lado do jogo.
##
## O QUE ELE FAZ, EM UMA LINHA: o saco desce quando a rodada começa e
## sobe quando ela acaba, e nada além disso pode ligar o motor.
##
## POR QUE ISTO É UMA CLASSE E NÃO DUAS LINHAS DENTRO DO `main.gd`.
## Porque um motor não é um LED. Um LED aceso por engano é um LED aceso;
## um motor ligado por engano é uma correia arrebentada, um saco no chão
## ou um fim de curso destruído — e acontece longe de quem programou,
## numa festa, às onze da noite. Tudo o que decide ligar o motor está
## nesta página, e ela é curta de propósito para caber inteira na cabeça
## de quem for mexer.
##
## AS QUATRO REGRAS, e nenhuma delas é opcional:
##
##   1. INTENÇÃO, E NÃO COMANDO. O jogo diz onde o saco DEVE estar
##      ("em baixo", "em cima"); nunca diz "liga o motor". Um comando
##      repetido é uma intenção repetida, e intenção repetida não faz
##      nada — é isso que impede o jogo de manter o motor ligado à força
##      de mandar a mesma coisa sessenta vezes por segundo.
##
##   2. NADA DE ESPERAR. Nenhuma função aqui bloqueia. O jogo manda a
##      intenção e segue desenhando; a confirmação chega depois, pela
##      serial, como qualquer outra mensagem da placa. Esperar o motor
##      seria congelar a tela por três segundos e meio no momento exato
##      em que o jogador aperta START.
##
##   3. O TEMPO É O TETO, E ELE É DO FIRMWARE. Quem desliga o motor é a
##      placa, sempre, mesmo que o jogo trave, feche ou o cabo caia. Este
##      lado só pede; a garantia mora do outro lado do cabo. Ver
##      `motorAtualizar` no firmware.
##
##   4. SEM MOTOR, O JOGO É O MESMO. Um gabinete sem motor ligado (ou
##      com ele desligado na Central) joga exatamente igual. Esta é a
##      diferença entre um recurso e uma dependência.

## Onde o saco deve estar. É isto que o jogo escreve.
enum Onde { EM_CIMA, EM_BAIXO }

## QUANTO TEMPO ESPERAR ANTES DE DESISTIR de uma intenção.
##
## Se a placa não confirmar dentro do curso inteiro mais uma folga, o
## jogo para de insistir e diz que não sabe onde o saco está. Insistir
## para sempre é o laço infinito com outro nome.
const FOLGA_DA_CONFIRMACAO_MS := 2500

## O intervalo mínimo entre dois pedidos IGUAIS. Existe para o caso de a
## placa reiniciar no meio do curso e perder o comando: o jogo repete uma
## vez por segundo, e não sessenta.
const REPETIR_A_CADA_MS := 1000

var ligado := false
var curso_ms := 3500
var pausa_ms := 350
var fim_de_curso := true

var estado := ArduinoProtocol.MOTOR_PARADO
var posicao := ArduinoProtocol.POS_DESCONHECIDA
var resta_ms := 0

var _querido: int = Onde.EM_CIMA
var _pedido_em_ms := 0
var _ultimo_envio_ms := 0
var _desistiu := false
## UMA INTENÇÃO NOVA SAI NA HORA, e esta bandeira é o que garante isso.
##
## Antes o "já mandei há pouco?" era uma subtração de relógios com
## `_ultimo_envio_ms` começando em zero — e zero não quer dizer "nunca
## mandei", quer dizer "no instante em que o programa subiu". Nos
## primeiros mil milissegundos de vida do processo, portanto, o primeiro
## comando do motor era engolido pelo próprio intervalo de repetição.
## Uma bandeira diz o que a conta não sabia dizer.
var _mandar_ja := false

## O que o jogo chama. Não manda nada por si: só registra a intenção.
func quero(onde: int) -> void:
	if _querido == onde and not _desistiu:
		return
	_querido = onde
	_desistiu = false
	_mandar_ja = true
	_pedido_em_ms = Time.get_ticks_msec()
	_ultimo_envio_ms = Time.get_ticks_msec()

## Chamada a cada quadro. Devolve a linha a enviar, ou "" quando não há
## nada a dizer — que é o caso na esmagadora maioria dos quadros.
func passo() -> String:
	if not ligado or _desistiu:
		return ""
	var alvo := (
		ArduinoProtocol.POS_EM_BAIXO if _querido == Onde.EM_BAIXO
		else ArduinoProtocol.POS_EM_CIMA
	)
	if posicao == alvo and estado == ArduinoProtocol.MOTOR_PARADO:
		return ""
	var agora := Time.get_ticks_msec()
	# DESISTIR É PARTE DO PROJETO. Passado o curso inteiro mais a folga
	# sem a placa confirmar, o jogo para de pedir e passa a dizer que não
	# sabe onde o saco está — que é a verdade. Continuar mandando seria
	# um laço infinito distribuído entre dois aparelhos.
	if agora - _pedido_em_ms > curso_ms + FOLGA_DA_CONFIRMACAO_MS:
		_desistiu = true
		posicao = ArduinoProtocol.POS_DESCONHECIDA
		return ""
	if not _mandar_ja and agora - _ultimo_envio_ms < REPETIR_A_CADA_MS:
		return ""
	_mandar_ja = false
	_ultimo_envio_ms = agora
	return ArduinoProtocol.build_motor(
		"DESCE" if _querido == Onde.EM_BAIXO else "SOBE"
	)

## A placa respondeu. Aqui o jogo aprende onde o saco está de verdade.
func receber(msg: Dictionary) -> void:
	estado = int(msg.get("estado", ArduinoProtocol.MOTOR_PARADO))
	posicao = int(msg.get("posicao", ArduinoProtocol.POS_DESCONHECIDA))
	resta_ms = int(msg.get("resta_ms", 0))
	if estado != ArduinoProtocol.MOTOR_PARADO:
		# Enquanto anda, o relógio da desistência anda junto: um curso
		# longo configurado pelo operador não pode virar desistência só
		# porque demora o que ele mesmo mandou demorar.
		_pedido_em_ms = Time.get_ticks_msec()
		_desistiu = false

## A parada de emergência. Ela é diferente de `quero`: não é uma
## intenção, é uma ordem — e ela apaga a intenção junto, senão o passo
## seguinte religaria o motor que o operador acabou de mandar parar.
func parar() -> String:
	_querido = Onde.EM_CIMA if posicao == ArduinoProtocol.POS_EM_CIMA else Onde.EM_BAIXO
	_desistiu = true
	return ArduinoProtocol.build_motor("PARA")

## Tira o freio de mão depois de um PARA ou de uma desistência.
func destravar() -> void:
	_desistiu = false
	_mandar_ja = true
	_pedido_em_ms = Time.get_ticks_msec()
	_ultimo_envio_ms = Time.get_ticks_msec()

func andando() -> bool:
	return estado != ArduinoProtocol.MOTOR_PARADO

func desistiu() -> bool:
	return _desistiu

## Quanto do curso já andou, de 0 a 1 — para a Central desenhar uma barra
## que anda de verdade.
func progresso() -> float:
	if estado == ArduinoProtocol.MOTOR_PARADO or curso_ms <= 0:
		return 1.0
	return clampf(1.0 - float(resta_ms) / float(curso_ms), 0.0, 1.0)

## Uma frase pronta para a tela, e ela nunca mente: quando o jogo não
## sabe onde o saco está, ela diz isso.
func ficha() -> String:
	if not ligado:
		return "MOTOR DESLIGADO NA CENTRAL"
	if _desistiu:
		return "MOTOR NÃO RESPONDEU — CONFIRA A LIGAÇÃO"
	if estado == ArduinoProtocol.MOTOR_DESCENDO:
		return "BAIXANDO O SACO… %d%%" % int(progresso() * 100.0)
	if estado == ArduinoProtocol.MOTOR_SUBINDO:
		return "SUBINDO O SACO… %d%%" % int(progresso() * 100.0)
	return ArduinoProtocol.nome_da_posicao(posicao)

func para_salvar() -> Dictionary:
	return {
		"ligado": ligado, "curso_ms": curso_ms,
		"pausa_ms": pausa_ms, "fim_de_curso": fim_de_curso,
	}

func carregar(dados: Dictionary) -> void:
	ligado = bool(dados.get("ligado", false))
	curso_ms = clampi(int(dados.get("curso_ms", 3500)), 200, 15000)
	pausa_ms = clampi(int(dados.get("pausa_ms", 350)), 50, 2000)
	fim_de_curso = bool(dados.get("fim_de_curso", true))
