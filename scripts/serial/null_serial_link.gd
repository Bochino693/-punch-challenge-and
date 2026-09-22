class_name NullSerialLink
extends SerialLink

## Backend vazio: só entra quando NENHUM caminho até a placa deu certo —
## nem a extensão nativa, nem a ponte por processo. O jogo continua
## abrindo e jogável no teclado, mas a máquina de verdade está morta, e
## quem está na frente dela precisa saber disso e por quê. É só para isso
## que este backend guarda uma frase.

var _motivo := ""

func nome_do_caminho() -> String:
	return SerialLink.CAMINHO_NENHUM

func explicar(motivo: String) -> void:
	_motivo = motivo

func motivo_da_falta() -> String:
	return _motivo
