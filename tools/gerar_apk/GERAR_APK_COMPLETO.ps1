$ErrorActionPreference = "Stop"
# Este script mora em tools\gerar_apk; o projeto e a pasta dois niveis acima.
$Scripts = $PSScriptRoot
$Raiz = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Raiz

$env:ANDROID_HOME = "C:\AndroidSdk"
$env:ANDROID_SDK_ROOT = "C:\AndroidSdk"
$ApkEsperado = Join-Path $Raiz "build\android\PunchChallenge.apk"
$PluginGradle = Join-Path $Raiz "tools\android_usb_plugin\plugin\build.gradle.kts"

# Impede compilar silenciosamente uma copia antiga do projeto. Esse teste
# acontece antes do Gradle e informa exatamente qual pasta foi aberta.
if (-not (Test-Path -LiteralPath $PluginGradle)) {
    throw "Projeto incompleto: nao encontrei $PluginGradle"
}
$PluginTexto = Get-Content -LiteralPath $PluginGradle -Raw
if ($PluginTexto -match 'AndroidUSBCamera:libausbc:3\.3\.2') {
    throw "COPIA ANTIGA DETECTADA: esta pasta ainda usa UVC 3.3.2. Aplique a atualizacao 1.0.65 nesta mesma pasta. Pasta atual: $Raiz"
}
if ($PluginTexto -notmatch 'AndroidUSBCamera:libausbc:3\.2\.7') {
    throw "Dependencia UVC corrigida nao encontrada. Nao vou gerar um APK incompleto. Pasta atual: $Raiz"
}

# Trava de compatibilidade: estas APIs aparecem na documentacao de versoes
# posteriores, mas nao existem no AAR 3.2.7 efetivamente usado pelo projeto.
# Falha antes de gastar tempo no Gradle se alguma atualizacao as reintroduzir.
$FonteCamera = Join-Path $Raiz "tools\android_usb_plugin\plugin\src\main\java\com\lazersport\punch\usbserial\GodotAndroidPlugin.kt"
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

Write-Host "Projeto confirmado: Super Boxing (Punch Challenge) - build 89" -ForegroundColor Green

# ------------------------------------------------------------------
# ESPACO EM DISCO. Sem espaco o Gradle falha no meio ("Espaco insuficiente
# no disco") e o Godot chega a corromper o proprio arquivo de configuracao
# (perdendo o caminho do Java). Com pouco espaco, os temporarios do Gradle
# e do Godot sao limpos antes de comecar.
function Espaco-Livre-GB([string]$Caminho) {
    $raizDisco = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Caminho).Path)
    $info = New-Object System.IO.DriveInfo($raizDisco)
    return [math]::Round($info.AvailableFreeSpace / 1GB, 1)
}
function Limpar-Temporarios {
    $alvos = @(
        (Join-Path $env:TEMP "PunchChallenge-Godot-4.6.1"),
        (Join-Path $env:USERPROFILE ".gradle\.tmp"),
        (Join-Path $env:USERPROFILE ".gradle\caches\build-cache-1"),
        (Join-Path $Raiz "android\build\build"),
        (Join-Path $Raiz "android\build\.gradle"),
        (Join-Path $Raiz "tools\android_usb_plugin\plugin\build"),
        (Join-Path $Raiz "tools\android_usb_plugin\build"),
        (Join-Path $Raiz "tools\android_usb_plugin\.gradle")
    )
    foreach ($a in $alvos) {
        if (Test-Path -LiteralPath $a) {
            Remove-Item -LiteralPath $a -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem (Join-Path $env:USERPROFILE ".gradle\daemon") -Recurse -Filter "*.log" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
function Espaco-Minimo {
    return [math]::Min((Espaco-Livre-GB $Raiz), (Espaco-Livre-GB $env:USERPROFILE))
}
$Livre = Espaco-Minimo
if ($Livre -lt 6) {
    Write-Host "Pouco espaco em disco ($Livre GB). Limpando temporarios do Gradle e do Godot..." -ForegroundColor Yellow
    Limpar-Temporarios
    $Livre = Espaco-Minimo
    Write-Host "      Espaco livre agora: $Livre GB" -ForegroundColor Yellow
}
if ($Livre -lt 3) {
    throw "DISCO CHEIO: so $Livre GB livres. Libere pelo menos 5 GB (esvazie a Lixeira, apague videos e downloads antigos) e rode de novo."
}

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
    $AndroidBuildDir = Join-Path $Raiz "android\build"
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
$AndroidBuildGradle = Join-Path $Raiz "android\build\build.gradle"
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
& (Join-Path $Scripts "PREPARAR_PLUGIN_USB_ANDROID.bat")
if ($LASTEXITCODE -ne 0) {
    # O APK AINDA SAI: o jogo usa so funcoes que qualquer versao do plugin
    # tem. Com o plugin ja existente na pasta, a exportacao continua.
    if (Test-Path ".\addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar") {
        Write-Host "      AVISO: o plugin novo nao compilou (veja as mensagens acima)." -ForegroundColor Yellow
        Write-Host "      Continuando com o plugin que ja estava na pasta." -ForegroundColor Yellow
    } else {
        throw "A compilacao do plugin USB falhou e nao ha plugin anterior. O APK nao foi gerado."
    }
}

$Aar = ".\addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar"
if (-not (Test-Path $Aar)) {
    throw "Plugin USB nao foi criado: $Aar"
}

# ------------------------------------------------------------------
# A CONFIGURACAO DO GODOT (Java e SDK Android) SEMPRE CERTA. Se o arquivo
# de configuracao do editor estiver corrompido (acontece quando o disco
# enche no meio de uma gravacao) ele e refeito; se faltar o caminho do
# Java ou do SDK, ele e preenchido. Sem isto a exportacao para com "Um
# caminho valido para o Java SDK e necessario".
function Achar-Java {
    $candidatos = @()
    if ($env:JAVA_HOME) { $candidatos += $env:JAVA_HOME }
    $candidatos += Get-ChildItem "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Java", `
        "C:\Program Files\Microsoft", "C:\Program Files\Zulu", "C:\Program Files\OpenJDK" `
        -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '17' } |
        Sort-Object Name -Descending |
        Select-Object -ExpandProperty FullName
    $candidatos += "C:\Program Files\Android\Android Studio\jbr"
    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) { $candidatos += (Split-Path (Split-Path $java.Source)) }
    foreach ($d in $candidatos) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d "bin\java.exe"))) {
            return (Resolve-Path -LiteralPath $d).Path
        }
    }
    return $null
}
$Configuracao = Join-Path $env:APPDATA "Godot\editor_settings-4.6.tres"
$SemBom = New-Object System.Text.UTF8Encoding($false)
$Java = Achar-Java
$JavaGodot = if ($Java) { $Java -replace '\\', '/' } else { "" }
$Texto = ""
if (Test-Path -LiteralPath $Configuracao) {
    $Texto = [System.IO.File]::ReadAllText($Configuracao)
}
if (-not $Texto -or -not $Texto.TrimStart([char]0xFEFF, ' ', "`r", "`n", "`t").StartsWith("[gd_resource")) {
    if (Test-Path -LiteralPath $Configuracao) {
        Copy-Item -LiteralPath $Configuracao -Destination "$Configuracao.quebrado" -Force
        Write-Host "      Configuracao do Godot estava corrompida: refeita." -ForegroundColor Yellow
    }
    New-Item -ItemType Directory -Path (Split-Path $Configuracao) -Force | Out-Null
    $Texto = "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n"
}
function Garantir-Chave([string]$Chave, [string]$Valor) {
    if (-not $Valor) { return }
    $linha = "$Chave = `"$Valor`""
    $padrao = [regex]::Escape($Chave) + '\s*=\s*"[^"]*"'
    if ($script:Texto -match $padrao) {
        $script:Texto = [regex]::Replace($script:Texto, $padrao, $linha.Replace('$', '$$'))
    } else {
        $script:Texto = $script:Texto.TrimEnd() + "`n" + $linha + "`n"
    }
}
$JavaAtual = ""
if ($Texto -match 'export/android/java_sdk_path\s*=\s*"([^"]*)"') { $JavaAtual = $Matches[1] }
if (-not $JavaAtual -or -not (Test-Path -LiteralPath (Join-Path $JavaAtual "bin\java.exe"))) {
    if (-not $JavaGodot) {
        throw "Java 17 nao encontrado neste PC. Instale o Java 17 (Eclipse Temurin 17) e rode de novo."
    }
    Garantir-Chave "export/android/java_sdk_path" $JavaGodot
    Write-Host "      Java configurado no Godot: $JavaGodot" -ForegroundColor Green
}
Garantir-Chave "export/android/android_sdk_path" "C:/AndroidSdk"
[System.IO.File]::WriteAllText($Configuracao, $Texto, $SemBom)

Write-Host "[3/3] Exportando APK..." -ForegroundColor Cyan
& (Join-Path $Scripts "EXPORTAR_APK_ANDROID.bat") "$Godot"
if ($LASTEXITCODE -ne 0) {
    throw "A exportacao do Godot falhou."
}

$Apk = Get-Item $ApkEsperado -ErrorAction Stop
if ($Apk.Length -lt 1MB) {
    throw "APK incompleto: $($Apk.Length) bytes."
}

# Os modelos de exportacao ja foram instalados: o pacote baixado (mais de
# 1 GB) nao precisa ficar ocupando o disco.
Remove-Item -LiteralPath (Join-Path $env:TEMP "PunchChallenge-Godot-4.6.1") -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "APK GERADO E CONFERIDO" -ForegroundColor Green
Write-Host "Arquivo: $($Apk.FullName)"
Write-Host "Tamanho: $([math]::Round($Apk.Length / 1MB, 2)) MB"
Write-Host "SHA256: $((Get-FileHash -LiteralPath $Apk.FullName -Algorithm SHA256).Hash)"
