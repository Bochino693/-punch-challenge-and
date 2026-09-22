param(
    # GERA UM APK SEM A PONTE NATIVA, PARA DESCOBRIR DE QUEM E A CULPA.
    #
    # "Instala mas nao abre" tem duas familias de causa: ou o jogo, ou o
    # plugin Android (camera UVC e Arduino). Elas se separam em uma
    # execucao: este APK nao carrega o plugin nenhum. Se ele ABRIR, a
    # culpa e do plugin e o problema esta cercado. Se ele TAMBEM nao
    # abrir, o plugin esta inocente e a busca e outra.
    #
    # Sai com outro nome, PunchChallenge-SemPlugin.apk, e pode conviver
    # com o normal: tem o mesmo pacote, entao instale um de cada vez.
    [switch]$SemPlugin,
    # Instala no aparelho ligado por adb assim que o APK ficar pronto.
    [switch]$Instalar,
    # VOLTA A GERAR O APK DE DEPURACAO.
    #
    # O padrao agora e RELEASE, e a diferenca e de velocidade, nao de
    # burocracia: o modelo debug do Godot carrega o interpretador de
    # GDScript instrumentado -- toda linha executada passa por
    # verificacao de ponto de parada e contabilidade de perfil. Este jogo
    # e quase todo GDScript e roda numa Amlogic; era a maior lentidao
    # que ainda estava de pe, e ninguem a tinha escolhido: o release
    # exige uma chave de assinatura, e faltava so a chave.
    #
    # Este script cria a chave sozinho, uma vez, fora do repositorio.
    # Use -Depuracao se precisar do APK antigo para comparar.
    [switch]$Depuracao
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$env:ANDROID_HOME = "C:\AndroidSdk"
$env:ANDROID_SDK_ROOT = "C:\AndroidSdk"
$ApkEsperado = Join-Path $PSScriptRoot "build\android\PunchChallenge.apk"
$ProjetoGodot = Join-Path $PSScriptRoot "project.godot"
$ProjetoOriginal = $null
$PresetsArquivo = Join-Path $PSScriptRoot "export_presets.cfg"
$PresetsOriginal = $null
$PluginGradle = Join-Path $PSScriptRoot "tools\android_usb_plugin\plugin\build.gradle.kts"

# Impede compilar silenciosamente uma copia antiga do projeto. Esse teste
# acontece antes do Gradle e informa exatamente qual pasta foi aberta.
if (-not (Test-Path -LiteralPath $PluginGradle)) {
    throw "Projeto incompleto: nao encontrei $PluginGradle"
}
$PluginTexto = Get-Content -LiteralPath $PluginGradle -Raw
if ($PluginTexto -match 'AndroidUSBCamera:libausbc:3\.3\.2') {
    throw "COPIA ANTIGA DETECTADA: esta pasta ainda usa UVC 3.3.2. Aplique a atualizacao 1.0.60 nesta mesma pasta. Pasta atual: $PSScriptRoot"
}
if ($PluginTexto -notmatch 'AndroidUSBCamera:libausbc:3\.2\.7') {
    throw "Dependencia UVC corrigida nao encontrada. Nao vou gerar um APK incompleto. Pasta atual: $PSScriptRoot"
}

# Trava de compatibilidade: estas APIs aparecem na documentacao de versoes
# posteriores, mas nao existem no AAR 3.2.7 efetivamente usado pelo projeto.
# Falha antes de gastar tempo no Gradle se alguma atualizacao as reintroduzir.
$FonteCamera = Join-Path $PSScriptRoot "tools\android_usb_plugin\plugin\src\main\java\com\lazersport\punch\usbserial\GodotAndroidPlugin.kt"
$CameraTexto = Get-Content -LiteralPath $FonteCamera -Raw
$ApisUvcIncompativeis = @(
    'setRenderMode(',
    'CameraRequest.RenderMode',
    'CameraRequest.AudioSource',
    'setRawPreviewData('
)
foreach ($ApiUvc in $ApisUvcIncompativeis) {
    if ($CameraTexto.Contains($ApiUvc)) {
        throw "API INCOMPATIVEL COM AUSBC 3.2.7 ENCONTRADA: $ApiUvc"
    }
}

# Apaga o resultado ANTES de qualquer compilacao. Assim uma falha no plugin
# jamais deixa o APK da execucao anterior parecendo ser o novo.
if (Test-Path $ApkEsperado) {
    Remove-Item -LiteralPath $ApkEsperado -Force
}

Write-Host "Projeto confirmado: Punch Challenge Android 1.0.61 / UVC 3.2.7 / TV Box" -ForegroundColor Green

if (-not (Test-Path "$env:ANDROID_HOME\platform-tools\adb.exe")) {
    throw "SDK Android invalido em C:\AndroidSdk. Falta platform-tools\adb.exe."
}

$Godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path

if (-not $Godot) {
    $Godot = Get-ChildItem `
        "$env:USERPROFILE\Downloads", `
        "$env:USERPROFILE\Documents" `
        -Recurse -File -Include "Godot_v4.6.1-stable_win64*.exe" `
        -ErrorAction SilentlyContinue |
        Sort-Object { if ($_.Name -like "*console*") { 0 } else { 1 } } |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot 4.6.1 nao encontrado. Abra o editor e execute este arquivo novamente."
}

# O modelo Android do projeto depende dos Export Templates globais. O Godot
# nao os baixa com --install-android-build-template; esse comando apenas copia
# o template global ja instalado. Instale automaticamente a versao EXATA.
$TemplateDir = Join-Path $env:APPDATA "Godot\export_templates\4.6.1.stable"
$AndroidDebugTemplate = Join-Path $TemplateDir "android_debug.apk"
$AndroidReleaseTemplate = Join-Path $TemplateDir "android_release.apk"
$AndroidSourceTemplate = Join-Path $TemplateDir "android_source.zip"
if (-not (Test-Path $AndroidDebugTemplate) -or
    -not (Test-Path $AndroidReleaseTemplate) -or
    -not (Test-Path $AndroidSourceTemplate)) {
    Write-Host "[0/3] Baixando Export Templates oficiais do Godot 4.6.1..." -ForegroundColor Cyan
    Write-Host "      Primeira vez: o download e grande e pode demorar." -ForegroundColor Yellow
    $TemplateUrl = "https://downloads.godotengine.org/?flavor=stable&platform=templates&slug=export_templates.tpz&version=4.6.1"
    $TempBase = Join-Path $env:TEMP "PunchChallenge-Godot-4.6.1"
    $TemplateZip = Join-Path $TempBase "export_templates_4.6.1.zip"
    $TemplateExtraido = Join-Path $TempBase "extraido"
    New-Item -ItemType Directory -Path $TempBase -Force | Out-Null
    Remove-Item -LiteralPath $TemplateZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $TemplateExtraido -Recurse -Force -ErrorAction SilentlyContinue

    & curl.exe -L --fail --retry 3 --output $TemplateZip $TemplateUrl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $TemplateZip)) {
        throw "Falha ao baixar Export Templates oficiais do Godot 4.6.1. Confira a internet e tente novamente."
    }
    Expand-Archive -LiteralPath $TemplateZip -DestinationPath $TemplateExtraido -Force
    $OrigemTemplates = Join-Path $TemplateExtraido "templates"
    if (-not (Test-Path (Join-Path $OrigemTemplates "android_debug.apk"))) {
        throw "O pacote oficial foi baixado, mas nao contem android_debug.apk."
    }
    New-Item -ItemType Directory -Path $TemplateDir -Force | Out-Null
    Copy-Item -Path (Join-Path $OrigemTemplates "*") -Destination $TemplateDir -Recurse -Force
    if (-not (Test-Path $AndroidDebugTemplate) -or
        -not (Test-Path $AndroidReleaseTemplate) -or
        -not (Test-Path $AndroidSourceTemplate)) {
        throw "Nao foi possivel instalar os modelos Android em $TemplateDir"
    }
    Write-Host "      Export Templates 4.6.1 instalados." -ForegroundColor Green
}

if (
    -not (Test-Path ".\android\build\build.gradle") -and
    -not (Test-Path ".\android\build.gradle")
) {
    Write-Host "[1/3] Extraindo modelo Android diretamente no projeto..." -ForegroundColor Cyan
    # Nao abre o editor: nesta maquina o Godot 4.6.1 cai com signal 11 depois
    # de importar os recursos. O botao do editor apenas extrai este mesmo ZIP.
    $AndroidBuildDir = Join-Path $PSScriptRoot "android\build"
    Remove-Item -LiteralPath $AndroidBuildDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $AndroidBuildDir -Force | Out-Null
    Expand-Archive -LiteralPath $AndroidSourceTemplate -DestinationPath $AndroidBuildDir -Force
    if (-not (Test-Path (Join-Path $AndroidBuildDir "build.gradle"))) {
        throw "android_source.zip foi extraido, mas android\build\build.gradle nao apareceu."
    }
    Write-Host "      Modelo Android instalado sem abrir o editor." -ForegroundColor Green
}

# O POM antigo do AUSBC aponta para dois artefatos opcionais que existiam no
# JCenter e nao sao usados pela captura UVC do jogo. A exclusao tambem precisa
# existir no modelo Android do projeto; caso contrario o plugin compila, mas a
# exportacao final volta a tentar baixa-los.
$AndroidBuildGradle = Join-Path $PSScriptRoot "android\build\build.gradle"
if (-not (Test-Path -LiteralPath $AndroidBuildGradle)) {
    throw "Modelo Android incompleto: nao encontrei $AndroidBuildGradle"
}
$MarcadorDependencias = "PUNCH_UVC_JCENTER_OPTIONALS_EXCLUDED_V2"
$AndroidGradleTexto = Get-Content -LiteralPath $AndroidBuildGradle -Raw
if ($AndroidGradleTexto -notmatch $MarcadorDependencias) {
    $BlocoExclusao = @'

// PUNCH_UVC_JCENTER_OPTIONALS_EXCLUDED_V2
// As dependencias remotas do Godot ficam no PROJETO RAIZ. A primeira regra
// corrige exatamente :standardDebugRuntimeClasspath.
configurations.configureEach {
    exclude group: "com.gyf.immersionbar", module: "immersionbar"
    exclude group: "com.zlc.glide", module: "webpdecoder"
}

// Mantem a mesma protecao caso uma versao futura mova as dependencias para
// app, asset packs ou outro subprojeto.
subprojects {
    configurations.configureEach {
        exclude group: "com.gyf.immersionbar", module: "immersionbar"
        exclude group: "com.zlc.glide", module: "webpdecoder"
    }
}
'@
    Add-Content -LiteralPath $AndroidBuildGradle -Value $BlocoExclusao -Encoding UTF8
    Write-Host "      Dependencias opcionais antigas do AUSBC desativadas." -ForegroundColor Green
}

try {

if ($SemPlugin) {
    Write-Host "[2/3] MODO DIAGNOSTICO: exportando SEM a ponte nativa." -ForegroundColor Yellow
    # Desligar o plugin de editor e o que tira o AAR e as dependencias do
    # AUSBC do APK. O jogo aguenta: ele so fala com a ponte quando
    # `Engine.has_singleton` confirma que ela existe.
    $ProjetoOriginal = Get-Content -LiteralPath $ProjetoGodot -Raw
    $ProjetoSemPlugin = $ProjetoOriginal -replace `
        'enabled=PackedStringArray\("PunchUsbSerial"\)', 'enabled=PackedStringArray()'
    if ($ProjetoSemPlugin -eq $ProjetoOriginal) {
        throw "Nao encontrei a linha do plugin em project.godot para desligar."
    }
    Set-Content -LiteralPath $ProjetoGodot -Value $ProjetoSemPlugin -Encoding UTF8 -NoNewline
} else {
    Write-Host "[2/3] Preparando plugin USB/UVC..." -ForegroundColor Cyan
    & ".\PREPARAR_PLUGIN_USB_ANDROID.bat"
    if ($LASTEXITCODE -ne 0) {
        throw "A compilacao do plugin USB falhou. O APK nao foi gerado."
    }

    $Aar = ".\addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar"
    if (-not (Test-Path $Aar)) {
        throw "Plugin USB nao foi criado: $Aar"
    }
}

$Modo = "debug"
if (-not $Depuracao) {
    # A CHAVE DE ASSINATURA NASCE AQUI, FORA DO REPOSITORIO.
    #
    # Ela vale para este gabinete e mais nada: o APK e instalado a mao na
    # TV box, nao publicado em loja nenhuma. Fica em %USERPROFILE% porque
    # uma chave versionada e uma chave publicada.
    #
    # Guarde esta pasta: um APK assinado por OUTRA chave nao instala por
    # cima deste -- o Android exige desinstalar antes.
    $ChaveDir = Join-Path $env:USERPROFILE ".punchchallenge"
    $Chave = Join-Path $ChaveDir "punch-release.keystore"
    $ChaveSenha = "punchchallenge"
    $ChaveUsuario = "punch"

    $Keytool = $null
    foreach ($Candidato in @(
        (Join-Path $env:JAVA_HOME "bin\keytool.exe"),
        "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
        "C:\Program Files\Eclipse Adoptium\jdk-17\bin\keytool.exe"
    )) {
        if ($Candidato -and (Test-Path -LiteralPath $Candidato)) { $Keytool = $Candidato; break }
    }
    if (-not $Keytool) {
        $NoCaminho = Get-Command keytool.exe -ErrorAction SilentlyContinue
        if ($NoCaminho) { $Keytool = $NoCaminho.Source }
    }
    if (-not $Keytool) {
        $Achado = Get-ChildItem "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Java" `
            -Recurse -Filter "keytool.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($Achado) { $Keytool = $Achado }
    }

    if (-not $Keytool) {
        Write-Host "AVISO: keytool nao encontrado (falta o JDK 17)." -ForegroundColor Yellow
        Write-Host "       Gerando o APK de depuracao, mais lento. Instale o JDK 17" -ForegroundColor Yellow
        Write-Host "       e rode de novo para ter o APK rapido." -ForegroundColor Yellow
    } else {
        if (-not (Test-Path -LiteralPath $Chave)) {
            Write-Host "      Criando a chave de assinatura do gabinete (so desta vez)..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $ChaveDir -Force | Out-Null
            & $Keytool -genkeypair -v -keystore $Chave -alias $ChaveUsuario `
                -keyalg RSA -keysize 2048 -validity 10950 `
                -storepass $ChaveSenha -keypass $ChaveSenha `
                -dname "CN=Punch Challenge, OU=Lazer e Sport, O=Lazer e Sport, L=Brasil, C=BR"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Chave)) {
                throw "Nao consegui criar a chave de assinatura em $Chave"
            }
        }
        $PresetsOriginal = Get-Content -LiteralPath $PresetsArquivo -Raw
        $ChaveParaGodot = $Chave -replace '\\', '/'
        $Assinatura = @"
keystore/release="$ChaveParaGodot"
keystore/release_user="$ChaveUsuario"
keystore/release_password="$ChaveSenha"
"@
        $SemAssinatura = ($PresetsOriginal -split "`r?`n" |
            Where-Object { $_ -notmatch '^keystore/release' }) -join "`r`n"
        Set-Content -LiteralPath $PresetsArquivo -Value ($SemAssinatura.TrimEnd() + "`r`n" + $Assinatura) -Encoding UTF8
        $Modo = "release"
    }
}

Write-Host "[3/3] Exportando APK ($Modo)..." -ForegroundColor Cyan
& ".\EXPORTAR_APK_ANDROID.bat" "$Godot" "$Modo"
if ($LASTEXITCODE -ne 0) {
    throw "A exportacao do Godot falhou."
}

$Apk = Get-Item $ApkEsperado -ErrorAction Stop
if ($Apk.Length -lt 1MB) {
    throw "APK incompleto: $($Apk.Length) bytes."
}

if ($SemPlugin) {
    $Destino = Join-Path $Apk.DirectoryName "PunchChallenge-SemPlugin.apk"
    Move-Item -LiteralPath $Apk.FullName -Destination $Destino -Force
    $Apk = Get-Item -LiteralPath $Destino
}

Write-Host ""
Write-Host "APK GERADO E CONFERIDO" -ForegroundColor Green
Write-Host "Arquivo: $($Apk.FullName)"
Write-Host "Tamanho: $([math]::Round($Apk.Length / 1MB, 2)) MB"
Write-Host "SHA256: $((Get-FileHash -LiteralPath $Apk.FullName -Algorithm SHA256).Hash)"
if ($SemPlugin) {
    Write-Host ""
    Write-Host "ESTE APK NAO TEM CAMERA NEM ARDUINO. Ele serve para UMA pergunta:" -ForegroundColor Yellow
    Write-Host "  ele ABRE na TV box?" -ForegroundColor Yellow
    Write-Host "  ABRE  -> a ponte nativa e a culpada, e o cerco fechou." -ForegroundColor Yellow
    Write-Host "  NAO ABRE -> a ponte esta inocente; o problema e do jogo ou do pacote." -ForegroundColor Yellow
}

if ($Instalar) {
    $Adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
    Write-Host ""
    Write-Host "Instalando no aparelho ligado por adb..." -ForegroundColor Cyan
    & $Adb install -r "$($Apk.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw "adb install falhou. Confira 'adb devices'."
    }
    Write-Host "Instalado." -ForegroundColor Green
    Write-Host "Para ver o motivo de um fechamento, deixe rodando noutra janela:" -ForegroundColor Cyan
    Write-Host "  $Adb logcat -v time AndroidRuntime:E godot:V *:S" -ForegroundColor Cyan
}

} finally {
    # project.godot volta ao que era SEMPRE, inclusive se a exportacao
    # falhar no meio: um diagnostico nao pode deixar o projeto sem o
    # plugin sem ninguem perceber.
    if ($null -ne $ProjetoOriginal) {
        Set-Content -LiteralPath $ProjetoGodot -Value $ProjetoOriginal -Encoding UTF8 -NoNewline
        Write-Host "project.godot restaurado com o plugin ligado." -ForegroundColor DarkGray
    }
    # A senha da chave nao fica no repositorio depois que a exportacao
    # termina, nem se ela falhar no meio.
    if ($null -ne $PresetsOriginal) {
        Set-Content -LiteralPath $PresetsArquivo -Value $PresetsOriginal -Encoding UTF8 -NoNewline
    }
}
