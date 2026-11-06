import org.jetbrains.kotlin.gradle.plugin.getKotlinPluginVersion

// The Hailbell Flutter plugin for Android: the native SDK (vendor/hailbell, copied from sdk/android by
// tool/sync_native.sh) plus the Flutter glue in src/main/kotlin.
group = "com.hailbell.flutter"
version = "1.0.1"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// AGP 9 compiles Kotlin by itself. Apps still on AGP 8 need the Kotlin plugin applied here.
if (com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt() < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hailbell.flutter"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin", "vendor/hailbell/java")
            res.srcDirs("vendor/hailbell/res")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }
}

// The chat screen is Jetpack Compose, so the Compose compiler plugin must run, at exactly the app's
// Kotlin version. Adding it here with the version Gradle actually loaded saves every app from
// declaring the Compose Gradle plugin itself. Kotlin 2.0 or later is required.
val appKotlinVersion = project.getKotlinPluginVersion()
dependencies {
    add("kotlinCompilerPluginClasspath", "org.jetbrains.kotlin:kotlin-compose-compiler-plugin-embeddable:$appKotlinVersion")

    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.google.android.play:review:2.0.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
