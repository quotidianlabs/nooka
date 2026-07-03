import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("ru.cian.rustore-publish-gradle-plugin")
}

// Release signing is read from android/key.properties (gitignored). When that
// file is absent (CI without secrets, fresh clones), the release build falls
// back to the debug key so `flutter run --release` still works. CI release
// builds reconstruct key.properties from org secrets (see docs/release.md), and
// the workflow hard-fails if the keystore secret is missing — it never silently
// ships a debug-signed release.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.github.quotidianlabs.nooka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.quotidianlabs.nooka"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No upload keystore present: debug-sign so the build still runs.
                signingConfigs.getByName("debug")
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

// RuStore publishing (cianru plugin). Inert unless `publishRustoreRelease` is
// invoked with a credentials file present — see .github/workflows/release.yml.
rustorePublish {
    instances {
        create("release") {
            credentialsPath = "$rootDir/rustore-credentials.json"
            buildFormat = ru.cian.rustore.publish.BuildFormat.APK
            // Flutter writes the universal APK here (repo-root/build/...).
            buildFile = "$rootDir/../build/app/outputs/flutter-apk/app-release.apk"
            publishType = ru.cian.rustore.publish.PublishType.INSTANTLY
            developerContacts = ru.cian.rustore.publish.DeveloperContacts(
                email = "me@shiriev.ru",
                website = "https://github.com/quotidianlabs/nooka",
                vkCommunity = null,
            )
            releaseNotes = listOf(
                ru.cian.rustore.publish.ReleaseNote(
                    lang = "ru-RU",
                    filePath = "$rootDir/app/rustore-release-notes-ru.txt",
                ),
            )
        }
    }
}
