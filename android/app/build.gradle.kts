import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (phone auth): apply the Google Services plugin only when the config
// file is present, so the app still builds before Firebase is set up. Drop
// android/app/google-services.json in to activate phone login on the next build.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.shiplore.consumer.shiplore"
    compileSdk = maxOf(flutter.compileSdkVersion, 35) // PayU SDK requires compileSdk 34+
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Matches the consumer app registered in the shiplore-live Firebase project
        // (google-services.json client com.shiplore.consumer). Namespace stays
        // com.shiplore.consumer.shiplore so MainActivity/R are unchanged.
        applicationId = "com.shiplore.consumer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23) // firebase_auth requires 23+ (google_maps needs 21+)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Google Maps API key injected at build time via:
        //   flutter build apk -Pmaps_api_key=AIzaSy...
        // or android/gradle.properties (gitignored). Empty = map tiles disabled.
        manifestPlaceholders["MAPS_API_KEY"] =
            (project.findProperty("maps_api_key") as String?) ?: ""
    }

    // Release signing: provide these four properties via environment variables or
    // android/key.properties (gitignored). Until the keystore is created, the
    // release build falls back to debug keys so local testing still works.
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        val keystoreProps = Properties().apply { load(keystoreFile.inputStream()) }
        signingConfigs {
            create("release") {
                storeFile     = file(keystoreProps["storeFile"]   as String)
                storePassword =       keystoreProps["storePassword"] as String
                keyAlias      =       keystoreProps["keyAlias"]       as String
                keyPassword   =       keystoreProps["keyPassword"]    as String
            }
        }
    }

    buildTypes {
        release {
            val hasSigning = keystoreFile.exists()
            signingConfig = if (hasSigning) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            // Enable R8 full-mode shrinking and obfuscation. Keeps rules in
            // proguard-rules.pro protect Firebase, PayU SDK, and Dio reflection.
            isMinifyEnabled    = true
            isShrinkResources  = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
