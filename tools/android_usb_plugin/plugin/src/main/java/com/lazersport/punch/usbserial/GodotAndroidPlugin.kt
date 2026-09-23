package com.lazersport.punch.usbserial

import android.app.PendingIntent
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
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
import java.util.concurrent.atomic.AtomicInteger

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot),
    SerialInputOutputManager.Listener {

    companion object {
        private const val ACTION_USB_PERMISSION = "com.lazersport.punch.USB_PERMISSION"
        private const val CAMERA_PERMISSION_REQUEST = 9041
        private const val WRITE_TIMEOUT_MS = 250
        private const val MAX_QUEUED_LINES = 512
        private const val MAX_LINE_BYTES = 240
        private const val MAX_PENDING_WRITES = 48
        private const val PORT_LIST_CACHE_MS = 1000L
        private const val UVC_CALLBACK_GRACE_MS = 1500L

        // Estado da serial, lido pelo Godot a cada quadro (ver pollSerial).
        private const val SERIAL_FECHADA = 0
        private const val SERIAL_ABRINDO = 1
        private const val SERIAL_ABERTA = 2
        private const val UVC_WIDTH = 640
        private const val UVC_HEIGHT = 480
        private const val UVC_MIN_FRAME_INTERVAL_MS = 90L
        private const val UVC_RENDER_FALLBACK_INTERVAL_MS = 180L
    }

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    private val usbManager: UsbManager by lazy {
        val host = requireNotNull(activity) { "Godot Activity ainda nao esta disponivel" }
        host.getSystemService(Context.USB_SERVICE) as UsbManager
    }
    private val lock = Any()
    private val completeLines = ArrayDeque<String>()
    private val partialLine = ByteArray(MAX_LINE_BYTES)
    private var partialLength = 0
    private var partialOverflow = false
    private val writer = Executors.newSingleThreadExecutor { r -> Thread(r, "punch-serial-tx").apply { isDaemon = true } }
    // Abrir, fechar e listar a USB podem levar dezenas de milissegundos (e
    // muito mais numa TV Box lenta). Tudo isso roda AQUI, nunca na thread
    // do jogo: o Godot só lê o estado pronto.
    private val serialWorker = Executors.newSingleThreadExecutor { r -> Thread(r, "punch-serial-io").apply { isDaemon = true } }
    private val pendingWrites = AtomicInteger(0)
    @Volatile private var serialState = SERIAL_FECHADA
    @Volatile private var cachedPorts = ""
    @Volatile private var cachedPortsAt = 0L
    private val listingInFlight = AtomicBoolean(false)
    private val cameraWorker = Executors.newSingleThreadExecutor()
    private val serialPermissionRequested = mutableSetOf<Int>()
    private val cameraPermissionRequested = mutableSetOf<Int>()
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
    @Volatile private var lastCallbackAt = 0L
    @Volatile private var uvcFrameIntervalMs = UVC_MIN_FRAME_INTERVAL_MS

    private val previewCallback = object : IPreviewDataCallBack {
        override fun onPreviewData(data: ByteArray?, format: IPreviewDataCallBack.DataFormat) {
            if (data == null) return
            val now = android.os.SystemClock.elapsedRealtime()
            lastCallbackAt = now
            // O jogo diz quantos quadros quer (ver setUvcFrameInterval):
            // durante o soco ele pede poucos, e a conversão NV21 deixa de
            // disputar CPU com o impacto.
            if (now - lastCameraFrameAt < uvcFrameIntervalMs) return
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
            cameraStatus = "CÂMERA USB/UVC AO VIVO — $formatName ${width}x${height}"
        }
    }

    private val cameraStateCallback = object : ICameraStateCallBack {
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
    }

    private val deviceCallback = object : IDeviceConnectCallBack {
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
        }
    }

    private fun isUvcCamera(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_VIDEO) return true
        for (index in 0 until device.interfaceCount) {
            if (device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_VIDEO) return true
        }
        return false
    }

    private fun uvcCameras(): List<UsbDevice> =
        usbManager.deviceList.values.filter(::isUvcCamera)

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
        val root: ViewGroup? = host.findViewById(android.R.id.content)
        val params = FrameLayout.LayoutParams(UVC_WIDTH, UVC_HEIGHT)
        root?.addView(preview, 0, params)
        cameraPreviewView = preview
        return preview
    }

    /**
     * A Smart Pro só oferece framebuffer horizontal em tela cheia. A Activity
     * permanece em paisagem e a cena principal gira seu canvas internamente.
     */
    @UsedByGodot
    fun prepareAndroidKiosk(): Boolean {
        val host = activity ?: return fail("tela Android ainda não está disponível")
        host.runOnUiThread {
            host.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
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
        }
        return true
    }

    /**
     * Pede as DUAS autorizações necessárias: CAMERA do Android e acesso ao
     * dispositivo USB UVC. A segunda é independente da primeira e era a parte
     * que faltava na TV Box. Pode ser chamada repetidamente: só abre diálogo
     * enquanto ainda houver autorização pendente.
     */
    @UsedByGodot
    fun requestUsbCameraAccess(): String {
        val host = activity ?: return "TELA ANDROID AINDA NÃO DISPONÍVEL"
        host.runOnUiThread {
            if (host.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                host.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
            }
            val cameras = uvcCameras()
            if (cameras.isEmpty()) {
                cameraStatus = "NENHUMA WEBCAM USB/UVC NO BARRAMENTO"
                return@runOnUiThread
            }
            val pending = cameras.firstOrNull { !usbManager.hasPermission(it) }
            if (pending != null) {
                val pedir = synchronized(lock) { cameraPermissionRequested.add(pending.deviceId) }
                if (pedir) {
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    val intent = Intent(ACTION_USB_PERMISSION).setPackage(host.packageName)
                    usbManager.requestPermission(
                        pending,
                        PendingIntent.getBroadcast(host, 10000 + pending.deviceId, intent, flags)
                    )
                    cameraStatus = "AUTORIZE A WEBCAM USB UMA VEZ"
                } else {
                    cameraStatus = "AGUARDANDO AUTORIZAÇÃO DA WEBCAM USB"
                }
            } else {
                synchronized(lock) { cameras.forEach { cameraPermissionRequested.remove(it.deviceId) } }
                startUvcCamera()
            }
        }
        return cameraStatus
    }

    /** Abre a UVC de verdade. CameraServer sozinho não publica webcams USB
     * em várias TV boxes; esta ponte entrega o RGBA diretamente ao Godot. */
    @UsedByGodot
    fun startUvcCamera(): Boolean {
        val host = activity ?: return fail("tela Android ainda não disponível")
        host.runOnUiThread {
            try {
                if (cameraClient == null) {
                    cameraClient = MultiCameraClient(host.applicationContext, deviceCallback).also {
                        it.register()
                    }
                }
                val cameras = cameraClient?.getDeviceList()?.filter(::isUvcCamera).orEmpty()
                if (cameras.isEmpty()) {
                    cameraStatus = "NENHUMA WEBCAM USB/UVC DETECTADA"
                } else if (activeCamera == null) {
                    cameraStatus = "SOLICITANDO FLUXO DA WEBCAM USB…"
                    cameraClient?.requestPermission(cameras.first())
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
        val now = android.os.SystemClock.elapsedRealtime()
        // O caminho alternativo (copiar a TextureView na UI thread) só vale
        // para firmwares em que o callback NÃO entrega quadros. Antes ele
        // disparava em toda leitura vazia, mesmo com o callback vivo.
        if (now - lastCallbackAt < UVC_CALLBACK_GRACE_MS) return
        if (now - lastRenderedFrameRequestAt < maxOf(UVC_RENDER_FALLBACK_INTERVAL_MS, uvcFrameIntervalMs)) return
        if (!renderedFrameInFlight.compareAndSet(false, true)) return
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

    /** Intervalo mínimo entre quadros entregues ao jogo, em ms. */
    @UsedByGodot
    fun setUvcFrameInterval(intervalMs: Int) {
        uvcFrameIntervalMs = intervalMs.coerceIn(33, 5000).toLong()
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
        val allowed = cameras.count { usbManager.hasPermission(it) }
        return if (allowed == cameras.size) {
            "WEBCAM USB/UVC AUTORIZADA ($allowed/${cameras.size})"
        } else {
            "WEBCAM USB AGUARDANDO AUTORIZAÇÃO ($allowed/${cameras.size})"
        }
    }

    private fun drivers(): List<UsbSerialDriver> =
        UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)

    private fun key(driver: UsbSerialDriver): String {
        val d = driver.device
        return "usb:%04X:%04X:%d".format(d.vendorId, d.productId, d.deviceId)
    }

    /** Lista em cache; a enumeração USB roda no worker, nunca no jogo. */
    @UsedByGodot
    fun listPorts(): String {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - cachedPortsAt >= PORT_LIST_CACHE_MS && listingInFlight.compareAndSet(false, true)) {
            serialWorker.execute {
                try {
                    cachedPorts = drivers().joinToString("\n") { key(it) }
                } catch (t: Throwable) {
                    lastError = "falha ao listar USB: ${t.message ?: t.javaClass.simpleName}"
                } finally {
                    cachedPortsAt = android.os.SystemClock.elapsedRealtime()
                    listingInFlight.set(false)
                }
            }
        }
        return cachedPorts
    }

    /**
     * Pede a abertura e volta NA HORA. O resultado aparece em pollSerial():
     * estado ABERTA, ou FECHADA com getLastError() dizendo o motivo.
     */
    @UsedByGodot
    fun openPort(portKey: String, baud: Int): Boolean {
        if (serialState == SERIAL_ABRINDO) return true
        closePort()
        serialState = SERIAL_ABRINDO
        serialWorker.execute { openNow(portKey, baud) }
        return true
    }

    private fun openNow(portKey: String, baud: Int) {
        try {
            val driver = drivers().firstOrNull { key(it) == portKey }
            if (driver == null) {
                openFailed("dispositivo USB nao esta mais conectado")
                return
            }
            if (!usbManager.hasPermission(driver.device)) {
                val host = activity
                if (host == null) {
                    openFailed("tela Android ainda nao esta disponivel")
                    return
                }
                val pedir = synchronized(lock) { serialPermissionRequested.add(driver.device.deviceId) }
                if (pedir) {
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    val intent = Intent(ACTION_USB_PERMISSION).setPackage(host.packageName)
                    host.runOnUiThread {
                        usbManager.requestPermission(
                            driver.device,
                            PendingIntent.getBroadcast(host, driver.device.deviceId, intent, flags)
                        )
                    }
                    openFailed("autorize o Arduino uma vez e aguarde a reconexao")
                } else {
                    openFailed("aguardando autorizacao USB do Arduino")
                }
                return
            }
            synchronized(lock) { serialPermissionRequested.remove(driver.device.deviceId) }
            val connection = usbManager.openDevice(driver.device)
            if (connection == null) {
                openFailed("Android recusou a abertura do dispositivo USB")
                return
            }
            val port = driver.ports.firstOrNull()
            if (port == null) {
                connection.close()
                openFailed("adaptador USB serial nao possui porta")
                return
            }
            port.open(connection)
            port.setParameters(baud, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            try { port.dtr = true } catch (_: Throwable) { }
            try { port.rts = true } catch (_: Throwable) { }
            synchronized(lock) {
                completeLines.clear()
                partialLength = 0
                partialOverflow = false
            }
            val manager = SerialInputOutputManager(port, this)
            serialPort = port
            ioManager = manager
            manager.start()
            lastError = ""
            // Outra chamada pode ter pedido o fechamento enquanto abria.
            if (serialState == SERIAL_ABRINDO) {
                serialState = SERIAL_ABERTA
            } else {
                closeNow()
            }
        } catch (t: Throwable) {
            closeNow()
            openFailed("falha ao abrir USB serial: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun openFailed(message: String) {
        lastError = message
        serialState = SERIAL_FECHADA
    }

    private fun fail(message: String): Boolean {
        lastError = message
        return false
    }

    /** Marca fechada na hora; liberar a USB acontece no worker. */
    @UsedByGodot
    fun closePort() {
        serialState = SERIAL_FECHADA
        synchronized(lock) {
            completeLines.clear()
            partialLength = 0
            partialOverflow = false
        }
        serialWorker.execute { closeNow() }
    }

    private fun closeNow() {
        val manager = ioManager
        val port = serialPort
        ioManager = null
        serialPort = null
        try { manager?.stop() } catch (_: Throwable) { }
        try { port?.close() } catch (_: Throwable) { }
    }

    @UsedByGodot
    fun isOpen(): Boolean = serialState == SERIAL_ABERTA

    @UsedByGodot
    fun getSerialState(): Int = serialState

    /**
     * Uma chamada por quadro: a primeira linha é o estado (0 fechada,
     * 1 abrindo, 2 aberta) e as seguintes são as linhas recebidas desde a
     * última chamada. Uma travessia JNI em vez de três.
     */
    @UsedByGodot
    fun pollSerial(): String = synchronized(lock) {
        if (completeLines.isEmpty()) return@synchronized serialState.toString()
        buildString {
            append(serialState)
            while (completeLines.isNotEmpty()) {
                append('\n')
                append(completeLines.removeFirst())
            }
        }
    }

    /**
     * A escrita entra numa fila própria e não segura o jogo. Se a placa
     * parar de ler, a fila não cresce sem fim: acima do limite a linha é
     * descartada (os comandos do jogo são todos repetíveis).
     */
    @UsedByGodot
    fun writeLine(line: String): Boolean {
        val port = serialPort
        if (port == null || serialState != SERIAL_ABERTA) return fail("USB serial fechada")
        if (pendingWrites.get() >= MAX_PENDING_WRITES) return fail("fila de escrita cheia")
        pendingWrites.incrementAndGet()
        val bytes = (line.trimEnd() + "\n").toByteArray(StandardCharsets.US_ASCII)
        writer.execute {
            try {
                if (serialPort === port) port.write(bytes, WRITE_TIMEOUT_MS)
            } catch (t: Throwable) {
                lastError = "falha ao escrever na USB: ${t.message ?: t.javaClass.simpleName}"
            } finally {
                pendingWrites.decrementAndGet()
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

    /**
     * Montagem de linha BYTE A BYTE, em ASCII. O protocolo do Arduino é
     * texto simples; decodificar pedaços como UTF-8 quebrava caracteres
     * divididos entre dois pacotes USB. Ruído (byte de controle, linha
     * gigante sem fim) é descartado em vez de acumular.
     */
    override fun onNewData(data: ByteArray) {
        synchronized(lock) {
            for (b in data) {
                val c = b.toInt() and 0xff
                when {
                    c == 0x0A -> {
                        if (!partialOverflow && partialLength > 0) {
                            var end = partialLength
                            while (end > 0 && partialLine[end - 1].toInt() == 0x0D) end--
                            if (end > 0) {
                                if (completeLines.size >= MAX_QUEUED_LINES) completeLines.removeFirst()
                                completeLines.addLast(String(partialLine, 0, end, StandardCharsets.US_ASCII))
                            }
                        }
                        partialLength = 0
                        partialOverflow = false
                    }
                    c == 0x0D -> if (partialLength < MAX_LINE_BYTES) partialLine[partialLength++] = b
                    c < 0x20 || c > 0x7E -> Unit
                    partialLength < MAX_LINE_BYTES -> partialLine[partialLength++] = b
                    else -> partialOverflow = true
                }
            }
        }
    }

    override fun onRunError(e: Exception) {
        lastError = "USB desconectada: ${e.message ?: e.javaClass.simpleName}"
        closePort()
    }
}
