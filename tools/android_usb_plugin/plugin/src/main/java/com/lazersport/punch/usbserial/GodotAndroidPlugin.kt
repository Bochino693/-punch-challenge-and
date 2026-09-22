package com.lazersport.punch.usbserial

import android.app.PendingIntent
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import com.jiangdg.ausbc.MultiCameraClient
import com.jiangdg.ausbc.camera.bean.CameraRequest
import com.jiangdg.ausbc.callback.ICameraStateCallBack
import com.jiangdg.ausbc.callback.IDeviceConnectCallBack
import com.jiangdg.ausbc.callback.IPreviewDataCallBack
import com.jiangdg.ausbc.widget.AspectRatioTextureView
import com.serenegiant.usb.USBMonitor
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot),
    SerialInputOutputManager.Listener {

    companion object {
        private const val ACTION_USB_PERMISSION = "com.lazersport.punch.USB_PERMISSION"
        private const val CAMERA_PERMISSION_REQUEST = 9041
        private const val WRITE_TIMEOUT_MS = 250
        private const val MAX_QUEUED_LINES = 512
        private const val UVC_WIDTH = 640
        private const val UVC_HEIGHT = 480
        private const val UVC_MIN_FRAME_INTERVAL_MS = 90L
        /**
         * A LEITURA DA SUPERFICIE E CARA E FICA NA THREAD DA INTERFACE.
         *
         * `TextureView.getBitmap` e uma copia da GPU para a memoria comum
         * que sincroniza a thread de desenho. A 180 ms isso acontecia
         * cinco vezes por segundo, para sempre, enquanto a webcam nao
         * entregasse quadros pelo caminho normal -- ou seja, exatamente
         * no caso quebrado, e exatamente com a cara de "abriu a camera e
         * o jogo travou". Agora e raro e desiste sozinho.
         */
        private const val UVC_RENDER_FALLBACK_INTERVAL_MS = 420L
        private const val UVC_RENDER_FALLBACK_MAX_TRIES = 12
        /** Intervalo minimo entre dois pedidos de autorizacao da webcam. */
        private const val UVC_PERMISSION_RETRY_MS = 4000L
    }

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    /**
     * NUNCA LANCA. A versao anterior era `requireNotNull(activity)`, e um
     * `by lazy` que lanca guarda a excecao PARA SEMPRE: a segunda leitura
     * relanca a mesma falha mesmo depois de a Activity existir. Bastava o
     * jogo perguntar as portas um instante cedo demais para a ponte USB
     * ficar morta pelo resto da sessao.
     */
    private val usbManager: UsbManager?
        get() = try {
            activity?.getSystemService(Context.USB_SERVICE) as? UsbManager
        } catch (_: Throwable) {
            null
        }
    private val lock = Any()
    private val completeLines = ArrayDeque<String>()
    private val partialLine = StringBuilder()
    private val writer = Executors.newSingleThreadExecutor()
    private val cameraWorker = Executors.newSingleThreadExecutor()
    private val serialPermissionRequested = mutableSetOf<Int>()
    @Volatile private var serialPort: UsbSerialPort? = null
    @Volatile private var ioManager: SerialInputOutputManager? = null
    @Volatile private var lastError = ""
    @Volatile private var cameraStatus = "Câmera USB ainda não consultada"
    private val cameraFrameLock = Any()
    @Volatile private var cameraClient: MultiCameraClient? = null
    @Volatile private var activeCamera: MultiCameraClient.Camera? = null
    @Volatile private var cameraFrameWidth = 0
    @Volatile private var cameraFrameHeight = 0
    @Volatile private var lastCameraFrameAt = 0L
    @Volatile private var lastCameraFrameFormat = ""
    @Volatile private var cameraFramesAccepted = 0L
    @Volatile private var cameraFramesRejected = 0L
    private var latestRgbaFrame: ByteArray? = null
    private var cameraPreviewView: AspectRatioTextureView? = null
    private val renderedFrameInFlight = AtomicBoolean(false)
    @Volatile private var lastRenderedFrameRequestAt = 0L
    @Volatile private var renderedFrameTries = 0
    @Volatile private var proximoPedidoUvcEm = 0L

    /**
     * OS TRES RETORNOS DO AUSBC SO NASCEM QUANDO A CAMERA E PEDIDA.
     *
     * Eles eram tres `object :` guardados em campos comuns, ou seja,
     * construidos dentro do CONSTRUTOR do plugin -- que o Godot executa
     * no arranque, antes do primeiro quadro. Construir uma classe
     * anonima obriga a carregar as interfaces que ela implementa: aqui,
     * as do AUSBC e do libuvc.
     *
     * Ou seja: bastava alguma dessas classes nao estar no APK -- uma
     * dependencia que o Gradle nao resolveu, uma ABI podada, uma troca
     * de versao da biblioteca -- para a falha acontecer no pior lugar
     * possivel, dentro da criacao do plugin, longe de qualquer
     * `try/catch` nosso e antes de a tela existir.
     *
     * NAO TENHO COMO AFIRMAR QUE ERA ISSO NA TV BOX DO OPERADOR: nao vi
     * o `logcat`. O que da para afirmar e que o arranque nao precisava
     * correr esse risco. Com `by lazy` nenhuma classe do AUSBC e tocada
     * ate alguem pedir a camera de verdade, e ai a falha cai dentro do
     * `catch (Throwable)` de `startUvcCamera` e vira uma frase na tela,
     * em vez de acontecer onde ninguem pode pega-la.
     */
    private val previewCallback: IPreviewDataCallBack by lazy { object : IPreviewDataCallBack {
        override fun onPreviewData(data: ByteArray?, format: IPreviewDataCallBack.DataFormat) {
            if (data == null) return
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - lastCameraFrameAt < UVC_MIN_FRAME_INTERVAL_MS) return
            val size = activeCamera?.getPreviewSize()
            val width = size?.width ?: UVC_WIDTH
            val height = size?.height ?: UVC_HEIGHT
            val formatName = format.name
            val rgba = when (formatName) {
                "RGBA" -> {
                    if (data.size != width * height * 4) {
                        cameraFramesRejected++
                        cameraStatus = "UVC RGBA INVÁLIDO: ${data.size} BYTES PARA ${width}x${height}"
                        return
                    }
                    data.copyOf()
                }
                "NV21" -> {
                    if (data.size != width * height * 3 / 2) {
                        cameraFramesRejected++
                        cameraStatus = "UVC NV21 INVÁLIDO: ${data.size} BYTES PARA ${width}x${height}"
                        return
                    }
                    nv21ToRgba(data, width, height)
                }
                else -> {
                    cameraFramesRejected++
                    cameraStatus = "FORMATO UVC NÃO SUPORTADO: $formatName"
                    return
                }
            }
            synchronized(cameraFrameLock) {
                latestRgbaFrame = rgba
                cameraFrameWidth = width
                cameraFrameHeight = height
                lastCameraFrameAt = now
                lastCameraFrameFormat = formatName
                cameraFramesAccepted++
            }
            // O caminho normal funciona: a leitura cara da superfície não
            // precisa mais existir, e sua cota volta ao cheio caso um dia
            // o caminho normal pare.
            renderedFrameTries = 0
            cameraStatus = "CÂMERA USB/UVC AO VIVO — $formatName ${width}x${height}"
        }
    } }

    private val cameraStateCallback: ICameraStateCallBack by lazy { object : ICameraStateCallBack {
        override fun onCameraState(
            self: MultiCameraClient.Camera,
            code: ICameraStateCallBack.State,
            msg: String?
        ) {
            cameraStatus = when (code) {
                ICameraStateCallBack.State.OPENED -> "CÂMERA USB/UVC NATIVA TRANSMITINDO"
                ICameraStateCallBack.State.CLOSED -> "CÂMERA USB/UVC FECHADA"
                ICameraStateCallBack.State.ERROR -> "ERRO UVC: ${msg ?: "falha ao abrir vídeo"}"
            }
        }
    } }

    private val deviceCallback: IDeviceConnectCallBack by lazy { object : IDeviceConnectCallBack {
        override fun onAttachDev(device: UsbDevice?) {
            if (device == null || !isUvcCamera(device)) return
            cameraStatus = "WEBCAM USB DETECTADA — SOLICITANDO ACESSO"
            cameraClient?.requestPermission(device)
        }

        override fun onDetachDec(device: UsbDevice?) {
            if (activeCamera?.getUsbDevice()?.deviceId == device?.deviceId) closeActiveCamera()
            cameraStatus = "WEBCAM USB DESCONECTADA"
        }

        override fun onConnectDev(device: UsbDevice?, ctrlBlock: USBMonitor.UsbControlBlock?) {
            val host = activity ?: return
            if (device == null || ctrlBlock == null || !isUvcCamera(device)) return
            closeActiveCamera()
            val camera = MultiCameraClient.Camera(host.applicationContext, device)
            camera.setUsbControlBlock(ctrlBlock)
            camera.addPreviewDataCallBack(previewCallback)
            camera.setCameraStateCallBack(cameraStateCallback)
            activeCamera = camera
            val request = CameraRequest.Builder()
                .setPreviewWidth(UVC_WIDTH)
                .setPreviewHeight(UVC_HEIGHT)
                .create()
            val preview = ensureCameraPreviewView(host)
            cameraStatus = "PREPARANDO SUPERFÍCIE DA CÂMERA USB/UVC…"
            // A view acabou de ser anexada ao GodotActivity. Aguarda o Android
            // publicar sua SurfaceTexture antes de entregar a view ao AUSBC.
            preview.postDelayed({
                if (activeCamera !== camera) return@postDelayed
                try {
                    cameraStatus = "ABRINDO VÍDEO USB/UVC NATIVO…"
                    camera.openCamera(preview, request)
                } catch (t: Throwable) {
                    cameraStatus = "ERRO AO ABRIR UVC: ${t.message ?: t.javaClass.simpleName}"
                }
            }, 250L)
        }

        override fun onDisConnectDec(device: UsbDevice?, ctrlBlock: USBMonitor.UsbControlBlock?) {
            if (activeCamera?.getUsbDevice()?.deviceId == device?.deviceId) closeActiveCamera()
            cameraStatus = "WEBCAM USB SEM CONEXÃO"
        }

        override fun onCancelDev(device: UsbDevice?) {
            cameraStatus = "ACESSO À WEBCAM USB NEGADO"
            // A negativa LIBERA a proxima tentativa. Antes o pedido ficava
            // marcado como feito para sempre e a camera parava de vez apos
            // um unico toque errado no dialogo.
            proximoPedidoUvcEm = android.os.SystemClock.elapsedRealtime() + UVC_PERMISSION_RETRY_MS
        }
    } }

    private fun isUvcCamera(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_VIDEO) return true
        for (index in 0 until device.interfaceCount) {
            if (device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_VIDEO) return true
        }
        return false
    }

    private fun uvcCameras(): List<UsbDevice> =
        usbManager?.deviceList?.values?.filter(::isUvcCamera).orEmpty()

    /** AUSBC precisa de uma superfície real para iniciar o pipeline OpenGL.
     * Ela fica atrás da superfície do Godot, mas possui o tamanho real do
     * fluxo. Algumas TV boxes não chamam IPreviewDataCallBack; nesses aparelhos
     * copiamos os pixels desta TextureView como caminho alternativo. */
    private fun ensureCameraPreviewView(host: android.app.Activity): AspectRatioTextureView {
        cameraPreviewView?.let { existing ->
            if (existing.parent != null) return existing
        }
        val preview = AspectRatioTextureView(host).apply {
            alpha = 1.0f
            isClickable = false
            isFocusable = false
        }
        val root = host.findViewById<ViewGroup>(android.R.id.content)
        val params = FrameLayout.LayoutParams(UVC_WIDTH, UVC_HEIGHT)
        root.addView(preview, 0, params)
        cameraPreviewView = preview
        return preview
    }

    /**
     * Coloca a Activity em tela cheia real e mantém retrato nas TVs verticais.
     * SENSOR_PORTRAIT aceita as duas posições verticais, mas nunca gira o jogo
     * para paisagem nem o coloca na pequena janela de compatibilidade.
     */
    @UsedByGodot
    fun prepareAndroidKiosk(): Boolean {
        val host = activity ?: return fail("tela Android ainda não está disponível")
        host.runOnUiThread { try {
            // A ORIENTAÇÃO NÃO É MAIS TROCADA AQUI.
            //
            // Esta linha punha a tela em `UNSPECIFIED` em tempo de
            // execução, CONTRADIZENDO o que o próprio pacote declara
            // (`screen/orientation` do preset). Duas fontes discordando
            // sobre a mesma coisa, e a que vencia dependia de quando a
            // ponte fosse acordada — que agora, de propósito, não é mais
            // no primeiro quadro.
            //
            // Não estou dizendo que ela derrubava o aplicativo: a
            // Activity do Godot declara `orientation` em `configChanges`,
            // então o Android não a recria por causa disso. Estou dizendo
            // que ela é uma troca de estado da janela feita no meio do
            // arranque, sem precisar existir: o manifesto já diz a mesma
            // coisa, do primeiro quadro ao último, e sem discordância.
            host.window.addFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )
            host.window.setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                host.window.setDecorFitsSystemWindows(false)
                host.window.insetsController?.hide(WindowInsets.Type.systemBars())
            }
            @Suppress("DEPRECATION")
            host.window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        } catch (t: Throwable) {
            // Tela cheia é enfeite. Um firmware que recuse qualquer uma
            // destas chamadas não pode levar o jogo junto.
            lastError = "tela cheia recusada: ${t.message ?: t.javaClass.simpleName}"
        } }
        return true
    }

    /**
     * UM DONO SÓ PARA A AUTORIZAÇÃO DA WEBCAM.
     *
     * A versão anterior pedia a autorização USB DUAS VEZES, por dois
     * caminhos diferentes e ao mesmo tempo: aqui, com um `PendingIntent`
     * nosso, e lá dentro do AUSBC, com o `PendingIntent` dele, quando
     * `startUvcCamera` chamava `cameraClient.requestPermission`.
     *
     * Só um dos dois podia ganhar o diálogo. Pior: o nosso NÃO TINHA
     * RECEIVER REGISTRADO — o resultado do toque do operador não chegava
     * a lugar nenhum. Autorizada por esse caminho, a webcam ficava
     * autorizada de verdade no sistema, mas o AUSBC nunca era avisado, e
     * `onConnectDev` — que é quem abre o vídeo — não acontecia. É o
     * retrato exato da queixa: "mesmo pedindo permissão ela não cede a
     * imagem ao Godot".
     *
     * E havia o travamento permanente: `cameraPermissionRequested` só
     * crescia. Um diálogo dispensado sem querer marcava o aparelho como
     * "já pedi" para o resto da sessão, e a tela ficava em "AGUARDANDO
     * AUTORIZAÇÃO" sem nunca mais perguntar nada.
     *
     * Agora esta função faz só o que é dela — a permissão CAMERA do
     * Android, que é de aplicativo — e entrega o barramento USB inteiro
     * ao AUSBC, que é quem tem o receiver e quem abre o vídeo.
     */
    @UsedByGodot
    fun requestUsbCameraAccess(): String = try {
        val host = activity
        if (host == null) {
            "TELA ANDROID AINDA NÃO DISPONÍVEL"
        } else {
            host.runOnUiThread {
                try {
                    if (host.checkSelfPermission(Manifest.permission.CAMERA)
                        != PackageManager.PERMISSION_GRANTED
                    ) {
                        host.requestPermissions(
                            arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST
                        )
                    }
                } catch (t: Throwable) {
                    cameraStatus = "ANDROID RECUSOU O PEDIDO DE CÂMERA: " +
                        (t.message ?: t.javaClass.simpleName)
                }
            }
            startUvcCamera()
            cameraStatus
        }
    } catch (t: Throwable) {
        "ERRO AO PEDIR A WEBCAM: ${t.message ?: t.javaClass.simpleName}"
    }

    /** Abre a UVC de verdade. CameraServer sozinho não publica webcams USB
     * em várias TV boxes; esta ponte entrega o RGBA diretamente ao Godot.
     *
     * Pode ser chamada quantas vezes quiser: o cliente é registrado uma
     * vez só e o pedido de autorização é espaçado por
     * `UVC_PERMISSION_RETRY_MS`, de modo que uma negativa volta a
     * perguntar mais tarde em vez de desistir para sempre. */
    @UsedByGodot
    fun startUvcCamera(): Boolean {
        val host = activity ?: return fail("tela Android ainda não disponível")
        host.runOnUiThread {
            try {
                if (cameraClient == null) {
                    // A PRIMEIRA LINHA QUE TOCA NO AUSBC EM TODA A SESSÃO.
                    // Se a biblioteca não estiver no APK, a falha nasce
                    // aqui dentro — dentro deste `catch` — e vira uma
                    // frase na tela, não um aplicativo que não abre.
                    cameraClient = MultiCameraClient(host.applicationContext, deviceCallback)
                        .also { it.register() }
                }
                val cameras = cameraClient?.getDeviceList()?.filter(::isUvcCamera).orEmpty()
                if (cameras.isEmpty()) {
                    cameraStatus = "NENHUMA WEBCAM USB/UVC DETECTADA"
                } else if (activeCamera == null) {
                    val agora = android.os.SystemClock.elapsedRealtime()
                    if (agora >= proximoPedidoUvcEm) {
                        proximoPedidoUvcEm = agora + UVC_PERMISSION_RETRY_MS
                        cameraStatus = "SOLICITANDO FLUXO DA WEBCAM USB…"
                        // O AUSBC decide sozinho: se o sistema já concedeu
                        // o dispositivo, ele conecta direto; se não, ele
                        // abre o diálogo COM o receiver dele escutando.
                        cameraClient?.requestPermission(cameras.first())
                    }
                }
            } catch (t: Throwable) {
                cameraStatus = "ERRO UVC: ${t.message ?: t.javaClass.simpleName}"
            }
        }
        return true
    }

    @UsedByGodot
    fun stopUvcCamera() {
        val host = activity
        val action = {
            closeActiveCamera()
            try { cameraClient?.unRegister() } catch (_: Throwable) { }
            try { cameraClient?.destroy() } catch (_: Throwable) { }
            cameraClient = null
            cameraPreviewView?.let { preview ->
                try { (preview.parent as? ViewGroup)?.removeView(preview) } catch (_: Throwable) { }
            }
            cameraPreviewView = null
            cameraStatus = "CÂMERA USB/UVC FECHADA"
        }
        if (host != null) host.runOnUiThread { action() } else action()
    }

    private fun closeActiveCamera() {
        val camera = activeCamera
        activeCamera = null
        try { camera?.closeCamera() } catch (_: Throwable) { }
        synchronized(cameraFrameLock) {
            latestRgbaFrame = null
            cameraFrameWidth = 0
            cameraFrameHeight = 0
            lastCameraFrameAt = 0L
            lastCameraFrameFormat = ""
        }
        renderedFrameInFlight.set(false)
        renderedFrameTries = 0
        proximoPedidoUvcEm = 0L
    }

    /** Cada quadro só é entregue uma vez. Assim não cresce fila e nenhum
     * frame atrasado trava a animação no momento do soco. */
    @UsedByGodot
    fun pollUvcFrame(): ByteArray {
        synchronized(cameraFrameLock) {
            val frame = latestRgbaFrame
            if (frame != null) {
                latestRgbaFrame = null
                return frame
            }
        }
        requestRenderedFrameFallback()
        return ByteArray(0)
    }

    /** Fallback para firmwares que renderizam UVC na TextureView, mas não
     * entregam IPreviewDataCallBack. A cópia começa na UI thread e a conversão
     * ARGB->RGBA ocorre numa thread exclusiva, sem bloquear o jogo. */
    private fun requestRenderedFrameFallback() {
        if (renderedFrameTries >= UVC_RENDER_FALLBACK_MAX_TRIES) return
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastRenderedFrameRequestAt < UVC_RENDER_FALLBACK_INTERVAL_MS) return
        if (!renderedFrameInFlight.compareAndSet(false, true)) return
        renderedFrameTries++
        lastRenderedFrameRequestAt = now
        val host = activity
        val preview = cameraPreviewView
        if (host == null || preview == null || activeCamera == null) {
            renderedFrameInFlight.set(false)
            return
        }
        host.runOnUiThread {
            try {
                if (!preview.isAvailable) {
                    renderedFrameInFlight.set(false)
                    return@runOnUiThread
                }
                val bitmap = preview.getBitmap(UVC_WIDTH, UVC_HEIGHT)
                if (bitmap == null) {
                    renderedFrameInFlight.set(false)
                    return@runOnUiThread
                }
                cameraWorker.execute {
                    try {
                        val pixels = IntArray(UVC_WIDTH * UVC_HEIGHT)
                        bitmap.getPixels(pixels, 0, UVC_WIDTH, 0, 0, UVC_WIDTH, UVC_HEIGHT)
                        bitmap.recycle()
                        val rgba = ByteArray(pixels.size * 4)
                        var output = 0
                        for (argb in pixels) {
                            rgba[output++] = (argb shr 16).toByte()
                            rgba[output++] = (argb shr 8).toByte()
                            rgba[output++] = argb.toByte()
                            rgba[output++] = (argb ushr 24).toByte()
                        }
                        val acceptedAt = android.os.SystemClock.elapsedRealtime()
                        synchronized(cameraFrameLock) {
                            latestRgbaFrame = rgba
                            cameraFrameWidth = UVC_WIDTH
                            cameraFrameHeight = UVC_HEIGHT
                            lastCameraFrameAt = acceptedAt
                            lastCameraFrameFormat = "TEXTURE_RGBA"
                            cameraFramesAccepted++
                        }
                        cameraStatus = "CÂMERA USB/UVC AO VIVO — SUPERFÍCIE ${UVC_WIDTH}x${UVC_HEIGHT}"
                        renderedFrameTries = 0
                    } catch (t: Throwable) {
                        cameraStatus = "UVC SEM PIXELS: ${t.message ?: t.javaClass.simpleName}"
                    } finally {
                        renderedFrameInFlight.set(false)
                    }
                }
            } catch (t: Throwable) {
                cameraStatus = "UVC SEM SUPERFÍCIE: ${t.message ?: t.javaClass.simpleName}"
                renderedFrameInFlight.set(false)
            }
        }
    }

    @UsedByGodot
    fun getUvcFrameWidth(): Int = cameraFrameWidth

    @UsedByGodot
    fun getUvcFrameHeight(): Int = cameraFrameHeight

    @UsedByGodot
    fun getUvcStatus(): String = cameraStatus

    @UsedByGodot
    fun getUvcDiagnostics(): String =
        "status=$cameraStatus; formato=$lastCameraFrameFormat; " +
            "quadros=$cameraFramesAccepted; rejeitados=$cameraFramesRejected; " +
            "tamanho=${cameraFrameWidth}x${cameraFrameHeight}"

    /** AUSBC 3.2.7 fornece NV21. A conversão fica no thread da câmera e é
     * limitada a aproximadamente 11 fps, sem bloquear o thread do Godot. */
    private fun nv21ToRgba(nv21: ByteArray, width: Int, height: Int): ByteArray {
        val frameSize = width * height
        val out = ByteArray(frameSize * 4)
        var output = 0
        for (y in 0 until height) {
            val uvRow = frameSize + (y shr 1) * width
            for (x in 0 until width) {
                val yy = (nv21[y * width + x].toInt() and 0xff) - 16
                val uv = uvRow + (x and 1.inv())
                val v = (nv21[uv].toInt() and 0xff) - 128
                val u = (nv21[uv + 1].toInt() and 0xff) - 128
                val y1192 = 1192 * maxOf(yy, 0)
                val r = (y1192 + 1634 * v).coerceIn(0, 262143)
                val g = (y1192 - 833 * v - 400 * u).coerceIn(0, 262143)
                val b = (y1192 + 2066 * u).coerceIn(0, 262143)
                out[output++] = (r shr 10).toByte()
                out[output++] = (g shr 10).toByte()
                out[output++] = (b shr 10).toByte()
                out[output++] = 0xff.toByte()
            }
        }
        return out
    }

    @UsedByGodot
    fun getUsbCameraStatus(): String {
        if (activeCamera != null) return cameraStatus
        val cameras = try { uvcCameras() } catch (_: Throwable) { emptyList() }
        if (cameras.isEmpty()) return "NENHUMA WEBCAM USB/UVC DETECTADA"
        val gerente = usbManager ?: return "BARRAMENTO USB INDISPONÍVEL NESTE APARELHO"
        val allowed = cameras.count { gerente.hasPermission(it) }
        return if (allowed == cameras.size) {
            "WEBCAM USB/UVC AUTORIZADA ($allowed/${cameras.size})"
        } else {
            "WEBCAM USB AGUARDANDO AUTORIZAÇÃO ($allowed/${cameras.size})"
        }
    }

    private fun drivers(): List<UsbSerialDriver> {
        val gerente = usbManager ?: return emptyList()
        return UsbSerialProber.getDefaultProber().findAllDrivers(gerente)
    }

    private fun key(driver: UsbSerialDriver): String {
        val d = driver.device
        return "usb:%04X:%04X:%d".format(d.vendorId, d.productId, d.deviceId)
    }

    @UsedByGodot
    fun listPorts(): String = try {
        drivers().joinToString("\n") { key(it) }.also { lastError = "" }
    } catch (t: Throwable) {
        lastError = "falha ao listar USB: ${t.message ?: t.javaClass.simpleName}"
        ""
    }

    @UsedByGodot
    fun openPort(portKey: String, baud: Int): Boolean {
        closePort()
        return try {
            val gerente = usbManager
                ?: return fail("este aparelho nao expoe barramento USB host")
            val driver = drivers().firstOrNull { key(it) == portKey }
                ?: return fail("dispositivo USB nao esta mais conectado")
            if (!gerente.hasPermission(driver.device)) {
                val host = activity
                    ?: return fail("tela Android ainda nao esta disponivel")
                val pedir = synchronized(lock) { serialPermissionRequested.add(driver.device.deviceId) }
                if (pedir) {
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    val intent = Intent(ACTION_USB_PERMISSION).setPackage(host.packageName)
                    gerente.requestPermission(
                        driver.device,
                        PendingIntent.getBroadcast(host, driver.device.deviceId, intent, flags)
                    )
                    return fail("autorize o Arduino uma vez e aguarde a reconexao")
                }
                return fail("aguardando autorizacao USB do Arduino")
            }
            synchronized(lock) { serialPermissionRequested.remove(driver.device.deviceId) }
            val connection = gerente.openDevice(driver.device)
                ?: return fail("Android recusou a abertura do dispositivo USB")
            val port = driver.ports.firstOrNull()
                ?: return fail("adaptador USB serial nao possui porta")
            port.open(connection)
            port.setParameters(baud, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            try { port.dtr = true } catch (_: Throwable) { }
            try { port.rts = true } catch (_: Throwable) { }
            val manager = SerialInputOutputManager(port, this)
            serialPort = port
            ioManager = manager
            manager.start()
            lastError = ""
            true
        } catch (t: Throwable) {
            closePort()
            fail("falha ao abrir USB serial: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun fail(message: String): Boolean {
        lastError = message
        return false
    }

    @UsedByGodot
    fun closePort() {
        val manager = ioManager
        val port = serialPort
        ioManager = null
        serialPort = null
        try { manager?.stop() } catch (_: Throwable) { }
        try { port?.close() } catch (_: Throwable) { }
        synchronized(lock) {
            completeLines.clear()
            partialLine.setLength(0)
        }
    }

    @UsedByGodot
    fun isOpen(): Boolean = serialPort != null

    @UsedByGodot
    fun writeLine(line: String): Boolean {
        val port = serialPort ?: return fail("USB serial fechada")
        writer.execute {
            try {
                port.write((line.trimEnd() + "\n").toByteArray(StandardCharsets.UTF_8), WRITE_TIMEOUT_MS)
            } catch (t: Throwable) {
                lastError = "falha ao escrever na USB: ${t.message ?: t.javaClass.simpleName}"
            }
        }
        return true
    }

    @UsedByGodot
    fun pollLines(): String = synchronized(lock) {
        if (completeLines.isEmpty()) return@synchronized ""
        buildString {
            while (completeLines.isNotEmpty()) {
                if (isNotEmpty()) append('\n')
                append(completeLines.removeFirst())
            }
        }
    }

    @UsedByGodot
    fun getLastError(): String = lastError

    override fun onNewData(data: ByteArray) {
        val text = String(data, StandardCharsets.UTF_8)
        synchronized(lock) {
            for (character in text) {
                if (character == '\n') {
                    val line = partialLine.toString().trimEnd('\r')
                    partialLine.setLength(0)
                    if (line.isNotEmpty()) {
                        if (completeLines.size >= MAX_QUEUED_LINES) completeLines.removeFirst()
                        completeLines.addLast(line)
                    }
                } else {
                    partialLine.append(character)
                }
            }
        }
    }

    override fun onRunError(e: Exception) {
        lastError = "USB desconectada: ${e.message ?: e.javaClass.simpleName}"
        closePort()
    }
}
