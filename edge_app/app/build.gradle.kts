plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.sabaygo.edge"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sabaygo.edge"
        minSdk = 29          // PowerManager.currentThermalStatus
        targetSdk = 35
        versionCode = 1
        versionName = "0.1-bench"
        ndk { abiFilters += "arm64-v8a" }   // the pilot phone; keeps the APK small
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // A compressed model cannot be memory-mapped from the APK.
    androidResources { noCompress += "tflite" }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val camerax = "1.6.2"
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")
    implementation("androidx.activity:activity-ktx:1.10.1")

    // LiteRT 2.x: the runtime matching litert-torch, which exports the model.
    // GPU is reached only through CompiledModel in 2.x, not the old GpuDelegate.
    implementation("com.google.ai.edge.litert:litert:2.3.0")
    implementation("com.google.ai.edge.litert:litert-gpu:2.3.0")
}
