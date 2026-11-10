plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.util.Base64
import java.net.URI
import java.util.Locale
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.motriiq.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.motriiq.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("isolatedTest") {
            dimension = "environment"
            applicationIdSuffix = ".isolatedtest"
        }
    }

    buildTypes {
        release {
            // Release signing with dedicated keystore
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null

            // Enable R8 minification and resource shrinking for smaller app size
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

fun decodeDartDefines(): List<String> =
    (project.findProperty("dart-defines") as? String)
        .orEmpty().split(",").mapNotNull {
            runCatching {
                String(Base64.getDecoder().decode(it), Charsets.UTF_8)
            }.getOrNull()
        }

fun validatePlayBackendUrl(dartDefines: List<String>) {
    val backendDefines = dartDefines.filter { it.startsWith("BACKEND_URL=") }
    if (backendDefines.size != 1) {
        throw GradleException("Play release requires exactly one --dart-define=BACKEND_URL=https://... value.")
    }

    val backendUrl = backendDefines.single().substringAfter("=")
    val uri = runCatching { URI(backendUrl) }.getOrNull()
    val host = uri?.host?.lowercase(Locale.ROOT)
    if (uri == null ||
        uri.scheme?.lowercase(Locale.ROOT) != "https" ||
        uri.userInfo != null ||
        host.isNullOrBlank() ||
        host == "localhost" ||
        host.endsWith(".localhost") ||
        host == "10.0.2.2" ||
        host.matches(Regex("""127(?:\.\d{1,3}){3}""")) ||
        host == "::1" ||
        host == "[::1]" ||
        host.contains("your") ||
        host.contains("example") ||
        host.endsWith(".invalid")
    ) {
        throw GradleException("Play release BACKEND_URL must be a public HTTPS backend URL, not a local or example address.")
    }
}

// Debug builds work without private signing files; store builds must be signed.
gradle.taskGraph.whenReady {
    val dartDefines = decodeDartDefines()
    val isPlayStoreBuild = "PLAY_STORE_BUILD=true" in dartDefines
    val releaseTasks = allTasks.filter {
        it.name.contains("Release") &&
            (it.name.startsWith("assemble") ||
                it.name.startsWith("bundle") ||
                it.name.startsWith("package"))
    }

    if (allTasks.any { it.name == "bundleRelease" }) {
        if (!isPlayStoreBuild) {
            throw GradleException("Play bundles require --dart-define=PLAY_STORE_BUILD=true to disable unsupported paid features.")
        }
    }
    if (isPlayStoreBuild && releaseTasks.isNotEmpty()) {
        validatePlayBackendUrl(dartDefines)
    }
    if (!hasReleaseSigning && allTasks.any {
        it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package"))
    }) {
        throw GradleException("Release signing is missing. Copy android/key.properties.example to android/key.properties and configure your upload key.")
    }
}
