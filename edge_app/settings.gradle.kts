pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

// AGP as mobile/android (Gradle cache shared). Kotlin is newer: LiteRT 2.3
// is compiled with Kotlin 2.4 metadata, which 2.2 cannot read.
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

rootProject.name = "sabaygo-edge"
include(":app")
