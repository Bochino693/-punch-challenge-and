package com.lazersport.punch.usbserial

import android.app.PendingIntent
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.HandlerThread
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

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot),
    SerialInputOutputManager.Listener {

    companion object {
        private const val CAMERA_COUNT_TTL_MS = 1500L
        private const val ACTION_USB_PERMISSION = "com.lazersport.punch.USB_PERMISSION"
        private const val CAMERA_PERMISSION_REQUEST = 9041
        private const val WRITE_TIMEOUT_MS = 250
        private const val MAX_QUEUED_LINES = 512
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
    private val partialLine = StringBuilder()
    private val writer = Executors.newSingleThreadExecutor()
    private val cameraWorker = Executors.newSingleThreadExecutor()
    /** Consultas ao serviço de câmera do Android, que podem demorar segundos
     * enquanto o USB se reorganiza (webcam entrando ou saindo). Nunca na
     * thread do jogo nem na da interface. */
    private val infoWorker = Executors.newSingleThreadExecutor()
    @Volatile private var cachedCameraCount = 0
    @Volatile private var cameraCountAt = 0L
    private val countInFlight = java.util.concurrent.atomic.AtomicBoolean(false)
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

    // ------------------------------------------------------------------
    // CÂMERA DO SISTEMA (API clássica android.hardware.Camera).
    //
    // O CameraServer do Godot usa a Camera2 do NDK, que NÃO lista câmeras
    // de nível LEGACY — e é exatamente assim que as TV boxes Amlogic
    // publicam a webcam USB (driver uvcvideo do kernel + HAL antigo). A
    // API clássica enxerga essas câmeras. Ela é tentada primeiro; a UVC
    // direta (AUSBC) fica como reserva para aparelhos sem HAL de câmera.
    @Suppress("DEPRECATION")
    @Volatile private var systemCamera: android.hardware.Camera? = null
    private var systemCameraThread: HandlerThread? = null
    private var systemCameraTexture: SurfaceTexture? = null
    @Volatile private var systemCameraTried = false
    private val runtimePermissionsAsked = AtomicBoolean(false)
    // A câmera do sistema existe mas não abriu: daí em diante vale a UVC direta.
    @Volatile private var systemCameraFailed = false

    // UVC DIRETA: a mesma libuvc do AUSBC, mas chamada sem o USBMonitor
    // registrado (o registro dele quebra no Android 12+ por causa de um
    // PendingIntent sem FLAG_MUTABLE/IMMUTABLE). A permissão USB é pedida
    // por este plugin, do jeito certo, e a câmera é aberta por reflexão —
    // se algum nome da biblioteca mudar, o erro vira texto na Central, e o
    // build nunca quebra por isso.
    @Volatile private var uvcDireta: Any? = null
    @Volatile private var uvcDiretaFalhou = ""
    private var uvcDiretaTextura: SurfaceTexture? = null
    private var uvcDiretaSuperficie: android.view.Surface? = null
    private var uvcDiretaMonitor: Any? = null

    private val previewCallback = object : IPreviewDataCallBack {
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
        val root = host.findViewById<ViewGroup>(android.R.id.content)
        val params = FrameLayout.LayoutParams(UVC_WIDTH, UVC_HEIGHT)
        root.addView(preview, 0, params)
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
            // CAMERA e MICROFONE juntos, uma vez só. O microfone não é usado:
            // é que a janela USB do Android ESCONDE a caixa "Usar por padrão"
            // para aparelhos com áudio (toda webcam tem microfone) quando o
            // app não tem RECORD_AUDIO. Sem a caixa, a webcam seria pedida de
            // novo a cada vez que a TV Box liga.
            //
            // E UMA VEZ POR EXECUÇÃO, nunca a cada busca. Esta função roda a
            // cada poucos segundos enquanto não há câmera; pedir de novo a
            // cada chamada abria a janela do Android por cima do jogo sem
            // parar (e cada janela pausa a Activity e derruba a câmera que
            // estava abrindo). O microfone, que nem é usado, só é pedido
            // uma vez na vida do aparelho: recusado, fica recusado.
            if (runtimePermissionsAsked.compareAndSet(false, true)) {
                val prefs = host.getSharedPreferences("punch_usb", Context.MODE_PRIVATE)
                val micJaPedido = prefs.getBoolean("mic_pedido", false)
                val faltam = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
                    .filter { host.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                    .filter { it != Manifest.permission.RECORD_AUDIO || !micJaPedido }
                if (faltam.isNotEmpty()) {
                    if (faltam.contains(Manifest.permission.RECORD_AUDIO)) {
                        prefs.edit().putBoolean("mic_pedido", true).apply()
                    }
                    host.requestPermissions(faltam.toTypedArray(), CAMERA_PERMISSION_REQUEST)
                    // A janela está aberta: a câmera abre na próxima busca,
                    // com a Activity de volta ao primeiro plano.
                    if (faltam.contains(Manifest.permission.CAMERA)) {
                        cameraStatus = "AUTORIZE A CÂMERA NA JANELA DO ANDROID"
                        return@runOnUiThread
                    }
                }
            }
            // Com a câmera do sistema disponível, não se pede a USB da webcam:
            // quem fala com ela é o próprio Android.
            if (!systemCameraFailed && (systemCamera != null || systemCameraTried || systemCameraCount() > 0)) {
                startUvcCamera()
                return@runOnUiThread
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
                    cameraStatus = "WEBCAM: MARQUE USAR POR PADRÃO E TOQUE OK"
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

    /** Quantas câmeras a API clássica do Android enxerga. */
    /**
     * RELATÓRIO DA CÂMERA, uma linha por fato, para a Central mostrar e o
     * operador fotografar: o que a API clássica vê, o que a Camera2 vê (e
     * em que nível), cada aparelho USB com classe e permissão, e o estado
     * das duas pontes. É o que separa "a TV Box não tem driver" de "o
     * Android tem, mas falta permissão" de "a câmera nem está no USB".
     */
    @UsedByGodot
    fun getCameraReport(): String {
        val linhas = ArrayList<String>()
        val host = activity
        linhas.add("ANDROID ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) • ${Build.MANUFACTURER} ${Build.MODEL}")
        if (host != null) {
            val ok = host.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            linhas.add("PERMISSÃO CAMERA: " + if (ok) "CONCEDIDA" else "NEGADA")
        }
        linhas.add("API CLÁSSICA: ${systemCameraCount()} câmera(s)" + if (systemCameraFailed) " • FALHOU AO ABRIR" else "")
        try {
            val cm = host?.getSystemService(Context.CAMERA_SERVICE) as? android.hardware.camera2.CameraManager
            val ids = cm?.cameraIdList.orEmpty()
            val partes = ids.map { id ->
                val c = cm!!.getCameraCharacteristics(id)
                val lado = when (c.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)) {
                    0 -> "frente"; 1 -> "trás"; 2 -> "EXTERNA"; else -> "?"
                }
                val nivel = when (c.get(android.hardware.camera2.CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)) {
                    2 -> "LEGACY"; 0 -> "LIMITED"; 1 -> "FULL"; 3 -> "NIVEL3"; 4 -> "EXTERNAL"; else -> "?"
                }
                "$id:$lado/$nivel"
            }
            linhas.add("CAMERA2: " + if (partes.isEmpty()) "nenhuma" else partes.joinToString("  "))
        } catch (t: Throwable) {
            linhas.add("CAMERA2: erro ${t.javaClass.simpleName}")
        }
        try {
            val devs = usbManager.deviceList.values
            if (devs.isEmpty()) linhas.add("USB: nenhum aparelho no barramento")
            for (d in devs) {
                val video = isUvcCamera(d)
                val perm = if (usbManager.hasPermission(d)) "com permissão" else "SEM permissão"
                val nome = d.productName ?: d.deviceName
                linhas.add("USB %04X:%04X %s%s • %s".format(d.vendorId, d.productId, nome, if (video) " • VÍDEO" else "", perm))
            }
        } catch (t: Throwable) {
            linhas.add("USB: erro ${t.javaClass.simpleName}")
        }
        linhas.add("UVC DIRETA: " + when {
            uvcDireta != null -> "ABERTA"
            uvcDiretaFalhou.isNotEmpty() -> "FALHOU — $uvcDiretaFalhou"
            else -> "não tentada"
        })
        linhas.add("PONTE: $cameraStatus")
        linhas.add("QUADROS: aceitos $cameraFramesAccepted • rejeitados $cameraFramesRejected • $lastCameraFrameFormat ${cameraFrameWidth}x${cameraFrameHeight}")
        return linhas.joinToString("\n")
    }

    /** Para o jogo decidir quem abre a câmera: esta ponte ou o CameraServer. */
    @UsedByGodot
    fun getSystemCameraCount(): Int = if (systemCameraFailed) 0 else systemCameraCount()

    /** A contagem vem da memória e é renovada em segundo plano: quem
     * pergunta nunca espera o serviço de câmera responder. */
    private fun systemCameraCount(): Int {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - cameraCountAt > CAMERA_COUNT_TTL_MS && countInFlight.compareAndSet(false, true)) {
            infoWorker.execute {
                try {
                    cachedCameraCount = realSystemCameraCount()
                } finally {
                    cameraCountAt = android.os.SystemClock.elapsedRealtime()
                    countInFlight.set(false)
                }
            }
        }
        return cachedCameraCount
    }

    @Suppress("DEPRECATION")
    private fun realSystemCameraCount(): Int = try {
        android.hardware.Camera.getNumberOfCameras()
    } catch (_: Throwable) {
        0
    }

    /**
     * Abre a câmera pela API clássica numa thread própria com Looper (os
     * quadros chegam nela, nunca na thread do jogo). Devolve true se o
     * pedido foi feito; o resultado aparece em cameraStatus e nos quadros.
     */
    @Suppress("DEPRECATION")
    private fun startSystemCamera(host: android.app.Activity): Boolean {
        if (systemCamera != null) return true
        if (systemCameraFailed) return false
        val total = systemCameraCount()
        if (total <= 0) return false
        if (host.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            // A câmera existe: espera a permissão em vez de cair na UVC
            // direta, que tomaria o aparelho para si.
            cameraStatus = "PERMITA A CÂMERA DO ANDROID"
            return true
        }
        systemCameraTried = true
        val thread = systemCameraThread ?: HandlerThread("punch-camera").also {
            it.start()
            systemCameraThread = it
        }
        Handler(thread.looper).post { openSystemCameraNow(total) }
        cameraStatus = "ABRINDO CÂMERA DO SISTEMA ($total ENCONTRADA)"
        return true
    }

    @Suppress("DEPRECATION")
    private fun openSystemCameraNow(total: Int) {
        if (systemCamera != null) return
        var camera: android.hardware.Camera? = null
        var ultimoErro = ""
        // A webcam USB costuma ser a última da lista; a primeira que abrir vale.
        for (index in (total - 1) downTo 0) {
            try {
                camera = android.hardware.Camera.open(index)
                break
            } catch (t: Throwable) {
                ultimoErro = t.message ?: t.javaClass.simpleName
            }
        }
        if (camera == null) {
            cameraStatus = "CÂMERA DO SISTEMA NÃO ABRIU: $ultimoErro"
            systemCameraTried = false
            systemCameraFailed = true
            return
        }
        try {
            val params = camera.parameters
            val tamanhos = params.supportedPreviewSizes.orEmpty()
            val escolhido = tamanhos.minByOrNull {
                kotlin.math.abs(it.width - UVC_WIDTH) + kotlin.math.abs(it.height - UVC_HEIGHT)
            }
            if (escolhido != null) params.setPreviewSize(escolhido.width, escolhido.height)
            params.previewFormat = android.graphics.ImageFormat.NV21
            try { camera.parameters = params } catch (_: Throwable) { }
            val tamanho = camera.parameters.previewSize
            val largura = tamanho.width
            val altura = tamanho.height
            val bytes = largura * altura * 3 / 2
            // Superfície de mentira: a API exige um destino de pré-visualização,
            // mas os quadros de verdade vêm pelo callback abaixo.
            val textura = SurfaceTexture(42)
            systemCameraTexture = textura
            camera.setPreviewTexture(textura)
            camera.addCallbackBuffer(ByteArray(bytes))
            camera.addCallbackBuffer(ByteArray(bytes))
            camera.setPreviewCallbackWithBuffer { data, cam ->
                if (data != null) {
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (now - lastCameraFrameAt >= UVC_MIN_FRAME_INTERVAL_MS && data.size >= largura * altura * 3 / 2) {
                        val rgba = nv21ToRgba(data, largura, altura)
                        synchronized(cameraFrameLock) {
                            latestRgbaFrame = rgba
                            cameraFrameWidth = largura
                            cameraFrameHeight = altura
                            lastCameraFrameAt = now
                            lastCameraFrameFormat = "SISTEMA_NV21"
                            cameraFramesAccepted++
                        }
                        cameraStatus = "CÂMERA AO VIVO — ${largura}x${altura}"
                    }
                }
                try { cam.addCallbackBuffer(data) } catch (_: Throwable) { }
            }
            camera.setErrorCallback { erro, _ ->
                cameraStatus = "CÂMERA DO SISTEMA CAIU (erro $erro)"
                stopSystemCamera()
            }
            camera.startPreview()
            systemCamera = camera
            cameraStatus = "CÂMERA DO SISTEMA TRANSMITINDO ${largura}x${altura}"
        } catch (t: Throwable) {
            cameraStatus = "CÂMERA DO SISTEMA FALHOU: ${t.message ?: t.javaClass.simpleName}"
            try { camera.release() } catch (_: Throwable) { }
            systemCameraTried = false
            systemCameraFailed = true
        }
    }

    @Suppress("DEPRECATION")
    private fun stopSystemCamera() {
        val camera = systemCamera
        systemCamera = null
        systemCameraTried = false
        try { camera?.setPreviewCallbackWithBuffer(null) } catch (_: Throwable) { }
        try { camera?.stopPreview() } catch (_: Throwable) { }
        try { camera?.release() } catch (_: Throwable) { }
        try { systemCameraTexture?.release() } catch (_: Throwable) { }
        systemCameraTexture = null
    }

    /** Abre a webcam pela libuvc SEM o USBMonitor registrado. */
    private fun startDirectUvc(device: UsbDevice): Boolean {
        if (uvcDireta != null) return true
        val host = activity ?: return false
        return try {
            val cUvc = Class.forName("com.serenegiant.usb.UVCCamera")
            val cMonitor = Class.forName("com.serenegiant.usb.USBMonitor")
            val cOuvinte = Class.forName("com.serenegiant.usb.USBMonitor\$OnDeviceConnectListener")
            val cBloco = Class.forName("com.serenegiant.usb.USBMonitor\$UsbControlBlock")
            val ouvinte = java.lang.reflect.Proxy.newProxyInstance(
                cOuvinte.classLoader, arrayOf(cOuvinte)
            ) { _, _, _ -> null }
            val monitor = cMonitor.getConstructor(Context::class.java, cOuvinte)
                .newInstance(host.applicationContext, ouvinte)
            uvcDiretaMonitor = monitor
            val ctorBloco = cBloco.getDeclaredConstructor(cMonitor, UsbDevice::class.java)
            ctorBloco.isAccessible = true
            val bloco = ctorBloco.newInstance(monitor, device)
            val uvc = cUvc.getDeclaredConstructor().newInstance()
            cUvc.getMethod("open", cBloco).invoke(uvc, bloco)
            // Tamanho: 640x480 em MJPEG; se a câmera recusar, YUYV.
            val setSize = cUvc.getMethod("setPreviewSize", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            val mjpeg = try { cUvc.getField("FRAME_FORMAT_MJPEG").getInt(null) } catch (_: Throwable) { 1 }
            val yuyv = try { cUvc.getField("FRAME_FORMAT_YUYV").getInt(null) } catch (_: Throwable) { 0 }
            var largura = UVC_WIDTH
            var altura = UVC_HEIGHT
            val tentativas = listOf(
                Triple(640, 480, mjpeg), Triple(640, 480, yuyv),
                Triple(1280, 720, mjpeg), Triple(320, 240, yuyv)
            )
            var ok = false
            var ultimo = ""
            for ((w, h, modo) in tentativas) {
                try {
                    setSize.invoke(uvc, w, h, modo)
                    largura = w; altura = h; ok = true
                    break
                } catch (t: Throwable) {
                    ultimo = (t.cause ?: t).message ?: t.javaClass.simpleName
                }
            }
            if (!ok) throw IllegalStateException("tamanho recusado: $ultimo")
            // Superfície de mentira para o pipeline nativo andar.
            val textura = SurfaceTexture(43)
            textura.setDefaultBufferSize(largura, altura)
            val superficie = android.view.Surface(textura)
            uvcDiretaTextura = textura
            uvcDiretaSuperficie = superficie
            try {
                cUvc.getMethod("setPreviewDisplay", android.view.Surface::class.java).invoke(uvc, superficie)
            } catch (_: NoSuchMethodException) {
                cUvc.getMethod("setPreviewTexture", SurfaceTexture::class.java).invoke(uvc, textura)
            }
            // Quadros em NV21 pelo IFrameCallback, convertidos aqui.
            val cQuadro = Class.forName("com.serenegiant.usb.IFrameCallback")
            val nv21 = try { cUvc.getField("PIXEL_FORMAT_NV21").getInt(null) } catch (_: Throwable) { 5 }
            val w = largura
            val h = altura
            val retorno = java.lang.reflect.Proxy.newProxyInstance(
                cQuadro.classLoader, arrayOf(cQuadro)
            ) { _, metodo, args ->
                if (metodo.name == "onFrame" && args != null && args.isNotEmpty()) {
                    val buf = args[0] as? java.nio.ByteBuffer
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (buf != null && now - lastCameraFrameAt >= UVC_MIN_FRAME_INTERVAL_MS) {
                        val bytes = ByteArray(buf.remaining())
                        buf.get(bytes)
                        if (bytes.size >= w * h * 3 / 2) {
                            val rgba = nv21ToRgba(bytes, w, h)
                            synchronized(cameraFrameLock) {
                                latestRgbaFrame = rgba
                                cameraFrameWidth = w
                                cameraFrameHeight = h
                                lastCameraFrameAt = now
                                lastCameraFrameFormat = "UVC_DIRETA_NV21"
                                cameraFramesAccepted++
                            }
                            cameraStatus = "CÂMERA USB AO VIVO — ${w}x${h}"
                        } else {
                            cameraFramesRejected++
                        }
                    }
                }
                null
            }
            cUvc.getMethod("setFrameCallback", cQuadro, Int::class.javaPrimitiveType).invoke(uvc, retorno, nv21)
            cUvc.getMethod("startPreview").invoke(uvc)
            uvcDireta = uvc
            uvcDiretaFalhou = ""
            cameraStatus = "WEBCAM USB ABERTA DIRETO (${largura}x${altura}) — AGUARDANDO QUADROS"
            true
        } catch (t: Throwable) {
            val causa = (t as? java.lang.reflect.InvocationTargetException)?.targetException ?: t
            uvcDiretaFalhou = "${causa.javaClass.simpleName}: ${causa.message ?: ""}"
            cameraStatus = "UVC DIRETA FALHOU — $uvcDiretaFalhou"
            stopDirectUvc()
            false
        }
    }

    private fun stopDirectUvc() {
        val uvc = uvcDireta
        uvcDireta = null
        if (uvc != null) {
            try { uvc.javaClass.getMethod("stopPreview").invoke(uvc) } catch (_: Throwable) { }
            try { uvc.javaClass.getMethod("destroy").invoke(uvc) } catch (_: Throwable) { }
        }
        try { uvcDiretaSuperficie?.release() } catch (_: Throwable) { }
        try { uvcDiretaTextura?.release() } catch (_: Throwable) { }
        uvcDiretaSuperficie = null
        uvcDiretaTextura = null
    }

    /** Abre a UVC de verdade. CameraServer sozinho não publica webcams USB
     * em várias TV boxes; esta ponte entrega o RGBA diretamente ao Godot. */
    @UsedByGodot
    fun startUvcCamera(): Boolean {
        val host = activity ?: return fail("tela Android ainda não disponível")
        // 1º: a câmera do sistema (API clássica). Se ela existe, a UVC
        // direta NÃO é aberta: as duas brigariam pelo mesmo aparelho.
        if (systemCamera != null || (systemCameraTried && !systemCameraFailed)) return true
        if (cameraCountAt == 0L) {
            // Ainda sem a primeira contagem: ela está sendo feita em segundo
            // plano. O jogo chama de novo em instantes.
            systemCameraCount()
            cameraStatus = "PROCURANDO CÂMERA…"
            return true
        }
        if (startSystemCamera(host)) return true
        // 2º: a UVC direta, com a permissão USB já concedida a este plugin.
        if (uvcDireta != null) return true
        if (uvcDiretaFalhou.isEmpty()) {
            val webcam = try { uvcCameras().firstOrNull() } catch (_: Throwable) { null }
            if (webcam != null && usbManager.hasPermission(webcam)) {
                cameraWorker.execute { startDirectUvc(webcam) }
                return true
            }
            if (webcam != null) {
                // Sem permissão ainda: `requestUsbCameraAccess` pede e volta aqui.
                return true
            }
        }
        // Nada plugado: não há o que abrir. O jogo tenta de novo sozinho,
        // e a webcam é puxada assim que for conectada.
        if (uvcCameras().isEmpty()) {
            cameraStatus = "NENHUMA WEBCAM USB CONECTADA"
            return true
        }
        // 3º: o caminho antigo do AUSBC, de reserva.
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
        // Parar também zera as falhas: a webcam pode ter sido trocada ou
        // reconectada, e a próxima abertura merece tentar tudo de novo.
        systemCameraFailed = false
        uvcDiretaFalhou = ""
        cameraCountAt = 0L
        // Soltar a câmera pode demorar: sempre na thread de quem a abriu.
        val cameraThread = systemCameraThread
        if (cameraThread != null) Handler(cameraThread.looper).post { stopSystemCamera() } else stopSystemCamera()
        cameraWorker.execute { stopDirectUvc() }
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
        if (now - lastRenderedFrameRequestAt < UVC_RENDER_FALLBACK_INTERVAL_MS) return
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
        if (activeCamera != null || systemCamera != null || systemCameraTried || uvcDireta != null || uvcDiretaFalhou.isNotEmpty()) return cameraStatus
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
            val driver = drivers().firstOrNull { key(it) == portKey }
                ?: return fail("dispositivo USB nao esta mais conectado")
            if (!usbManager.hasPermission(driver.device)) {
                val host = activity
                    ?: return fail("tela Android ainda nao esta disponivel")
                val pedir = synchronized(lock) { serialPermissionRequested.add(driver.device.deviceId) }
                if (pedir) {
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    val intent = Intent(ACTION_USB_PERMISSION).setPackage(host.packageName)
                    usbManager.requestPermission(
                        driver.device,
                        PendingIntent.getBroadcast(host, driver.device.deviceId, intent, flags)
                    )
                    return fail("autorize o Arduino: marque USAR POR PADRAO e toque OK (so na 1a vez)")
                }
                return fail("autorize o Arduino: marque USAR POR PADRAO e toque OK (so na 1a vez)")
            }
            synchronized(lock) { serialPermissionRequested.remove(driver.device.deviceId) }
            val connection = usbManager.openDevice(driver.device)
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
