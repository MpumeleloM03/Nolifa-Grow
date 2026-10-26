plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nolifagrow.nolifa_grow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Two builds from one code base: Nolifa Grow for everyone (flavor "nolifa"),
    // and a farmers-only edition (flavor "grow"). Both carry the Nolifa Grow name and leaf logo.
    flavorDimensions += "app"
    productFlavors {
        create("nolifa") {
            dimension = "app"
            applicationId = "com.nolifa.app"
            resValue("string", "app_name", "Nolifa Grow")
        }
        create("grow") {
            dimension = "app"
            applicationId = "com.nolifagrow.nolifa_grow"
            resValue("string", "app_name", "Nolifa Grow")
        }
    }

    defaultConfig {
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = "nolifa-key"
            keyPassword = "NolifaGrow!"
            storeFile = file("nolifa-release-key.jks")
            storePassword = "NolifaGrow!"
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key until the real release key is added.
            signingConfig = if (file("nolifa-release-key.jks").exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}