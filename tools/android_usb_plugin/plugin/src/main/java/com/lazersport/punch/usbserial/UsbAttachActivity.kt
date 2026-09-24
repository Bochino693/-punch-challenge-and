package com.lazersport.punch.usbserial

import android.app.Activity
import android.os.Bundle

/**
 * Recebe o encaixe do Arduino ou da webcam (USB_DEVICE_ATTACHED).
 *
 * EXISTIR JÁ É O TRABALHO, E SÓ ISSO. Por causa desta atividade o Android
 * oferece a caixa de "sempre" na janela de permissão USB; marcada uma vez,
 * o Android passa a DAR a permissão ao jogo sozinho a cada encaixe (e no
 * boot), sem perguntar mais.
 *
 * ELA NÃO ABRE O JOGO. A versão anterior chamava a tela do jogo daqui:
 * com o jogo já aberto (pela inicialização do Android), isso empilhava uma
 * segunda tela do Godot por cima da primeira — e a TV Box travava na hora
 * de autorizar o Arduino. Quem abre o jogo é a inicialização da TV Box;
 * aqui só se fecha, sem desenhar nada.
 */
class UsbAttachActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        finish()
    }
}
