allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Some plugins (e.g. payu_checkoutpro_flutter) still compile against an older
    // Android SDK; raise any Android module below the app's compileSdk (36) so their
    // newer transitive androidx deps (which require 34+) resolve — without lowering
    // modules already on 36 (e.g. sqflite needs API 36). Registered here, before
    // evaluationDependsOn triggers evaluation, so afterEvaluate is still allowed.
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            val current = androidExt.compileSdkVersion?.substringAfter("android-")?.toIntOrNull() ?: 0
            if (current < 36) androidExt.compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
