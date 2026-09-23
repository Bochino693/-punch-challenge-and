$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$env:ANDROID_HOME = "C:\AndroidSdk"
$env:ANDROID_SDK_ROOT = "C:\AndroidSdk"
$ApkEsperado = Join-Path $PSScriptRoot "build\android\PunchChallenge.apk"
$PluginGradle = Join-Path $PSScriptRoot "tools\android_usb_plugin\plugin\build.gradle.kts"

# Impede compilar silenciosamente uma copia antiga do projeto. Esse teste
# acontece antes do Gradle e informa exatamente qual pasta foi aberta.
if (-not (Test-Path -LiteralPath $PluginGradle)) {
    throw "Projeto incompleto: nao encontrei $PluginGradle"
}
$PluginTexto = Get-Content -LiteralPath $PluginGradle -Raw
if ($PluginTexto -match 'AndroidUSBCamera:libausbc:3\.3\.2') {
    throw "COPIA ANTIGA DETECTADA: esta pasta ainda usa UVC 3.3.2. Aplique a atualizacao 1.0.65 nesta mesma pasta. Pasta atual: $PSScriptRoot"
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

Write-Host "Projeto confirmado: Punch Challenge Android 1.0.73 / REFINADO" -ForegroundColor Green

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

Write-Host "[2/3] Preparando plugin USB/UVC..." -ForegroundColor Cyan
& ".\PREPARAR_PLUGIN_USB_ANDROID.bat"
if ($LASTEXITCODE -ne 0) {
    throw "A compilacao do plugin USB falhou. O APK nao foi gerado."
}

$Aar = ".\addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar"
if (-not (Test-Path $Aar)) {
    throw "Plugin USB nao foi criado: $Aar"
}

Write-Host "[3/3] Exportando APK..." -ForegroundColor Cyan
& ".\EXPORTAR_APK_ANDROID.bat" "$Godot"
if ($LASTEXITCODE -ne 0) {
    throw "A exportacao do Godot falhou."
}

$Apk = Get-Item $ApkEsperado -ErrorAction Stop
if ($Apk.Length -lt 1MB) {
    throw "APK incompleto: $($Apk.Length) bytes."
}

Write-Host ""
Write-Host "APK GERADO E CONFERIDO" -ForegroundColor Green
Write-Host "Arquivo: $($Apk.FullName)"
Write-Host "Tamanho: $([math]::Round($Apk.Length / 1MB, 2)) MB"
Write-Host "SHA256: $((Get-FileHash -LiteralPath $Apk.FullName -Algorithm SHA256).Hash)"
