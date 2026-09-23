package com.lazersport.punch.usbserial

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Recebe o encaixe do Arduino ou da webcam (USB_DEVICE_ATTACHED).
 *
 * Existir já é o trabalho: por ela o Android oferece "Usar por padrão" e,
 * marcado, guarda a permissão USB para o aplicativo. Aqui só se abre (ou
 * se traz para frente) o jogo e se fecha, sem desenhar nada.
 */
class UsbAttachActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val abrir = packageManager.getLaunchIntentForPackage(packageName)
                ?: packageManager.getLeanbackLaunchIntentForPackage(packageName)
            if (abrir != null) {
                abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                startActivity(abrir)
            }
        } catch (_: Throwable) {
        }
        finish()
    }
}
