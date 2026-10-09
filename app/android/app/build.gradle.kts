import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val imageHubVersions = Properties().apply {
    rootProject.file("imagehub-versions.properties").inputStream().use { load(it) }
}
val imageHubReleaseKeyStore = System.getenv("IMAGEHUB_ANDROID_KEYSTORE_PATH")
val imageHubReleaseAlias = System.getenv("IMAGEHUB_ANDROID_KEY_ALIAS")
val imageHubStorePassword = System.getenv("IMAGEHUB_ANDROID_STORE_PASSWORD")
val imageHubKeyPassword = System.getenv("IMAGEHUB_ANDROID_KEY_PASSWORD")
val imageHubReleaseSigningReady = listOf(
    imageHubReleaseKeyStore, imageHubReleaseAlias, imageHubStorePassword, imageHubKeyPassword
).all { !it.isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) } &&
    !imageHubReleaseSigningReady) {
    throw GradleException("ImageHub release requires the dedicated release signing key. Use tool/package_release.ps1; debug-signing fallback is disabled.")
}

android {
    namespace = "io.imagehost.imagehost"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this project's application and local-storage identity stable.
        applicationId = "io.imagehost.imagehost"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Android has its own version; release packaging builds one ARM64 APK.
        versionCode = imageHubVersions.getProperty("platform.build").toInt()
        versionName = imageHubVersions.getProperty("platform.version")
        manifestPlaceholders["imageHubKernelVersion"] =
            imageHubVersions.getProperty("kernel.version") + "+" +
            imageHubVersions.getProperty("kernel.revision")
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (imageHubReleaseSigningReady) {
            create("imageHubRelease") {
                storeFile = file(imageHubReleaseKeyStore!!)
                keyAlias = imageHubReleaseAlias
                storePassword = imageHubStorePassword
                keyPassword = imageHubKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (imageHubReleaseSigningReady) {
                signingConfig = signingConfigs.getByName("imageHubRelease")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

