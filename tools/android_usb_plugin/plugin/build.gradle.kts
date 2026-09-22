import com.android.build.gradle.internal.tasks.factory.dependsOn
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// O AUSBC 3.2.7 ainda publica duas dependencias opcionais no antigo JCenter.
// A ponte do Punch Challenge usa apenas captura UVC/NV21, portanto nenhuma
// delas e necessaria. Excluir globalmente evita falha de resolucao no Gradle.
configurations.configureEach {
    exclude(group = "com.gyf.immersionbar", module = "immersionbar")
    exclude(group = "com.zlc.glide", module = "webpdecoder")
}

// TODO: Update value to your plugin's name.
val pluginName = "PunchUsbSerial"

// TODO: Update value to match your plugin's package name.
val pluginPackageName = "com.lazersport.punch.usbserial"

android {
    namespace = pluginPackageName
    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 24

        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

dependencies {
    implementation("org.godotengine:godot:4.6.1.stable")
    implementation("com.github.mik3y:usb-serial-for-android:3.11.0")
    implementation("com.github.jiangdongguo.AndroidUSBCamera:libausbc:3.2.7")
    implementation("com.github.jiangdongguo.AndroidUSBCamera:libuvc:3.2.7")
}
