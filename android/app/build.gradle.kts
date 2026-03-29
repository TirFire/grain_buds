import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 💡 1. 修复语法：使用 Kotlin 方式加载密钥
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // 调试用：如果没找到文件，打包时会在控制台打印路径，帮你确认位置
    println("⚠️ 警告: 未找到 key.properties，请检查路径: ${keystorePropertiesFile.absolutePath}")
}

android {
    namespace = "com.example.GrainBuds" //
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // 💡 修复过时警告：直接指定版本
        jvmTarget = "17" 
    }

    defaultConfig {
        applicationId = "com.example.GrainBuds" //
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    // 💡 2. 修复签名配置：使用 Kotlin DSL 语法
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // 💡 3. 核心修复：指向上面创建的 release 签名
            signingConfig = signingConfigs.getByName("release")
            
            // 💡 4. 修复变量名：Kotlin 中属性名带 is 前缀
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
