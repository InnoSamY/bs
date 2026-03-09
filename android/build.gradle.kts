buildscript {
    repositories {
        // 优先使用阿里云镜像
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/releases") }
        maven { url = uri("https://jitpack.io") }

        println("✅ buildscript 仓库配置完成")
    }
    dependencies {
        // 指定 Android Gradle 插件版本，与 settings.gradle.kts 保持一致
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        // 优先使用阿里云镜像
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/releases") }
        maven { url = uri("https://maven.aliyun.com/repository/apache-snapshots") }
        maven { url = uri("https://maven.aliyun.com/nexus/content/groups/public/") }
        maven { url = uri("https://jitpack.io") }

        // 注释掉官方源，避免绕开镜像
        // google()
        // mavenCentral()

        println("✅ 项目 ${project.name} 的 allprojects 仓库配置完成")
    }
}

// 🔥🔥🔥 关键修复：确保所有子项目都强制使用阿里云镜像
subprojects {
    // 在项目配置完成后，确保仓库配置正确
    afterEvaluate {
        // 确保这是一个 Android 项目
        if (plugins.hasPlugin("com.android.library") ||
            plugins.hasPlugin("com.android.application")) {

            // 重新设置仓库，确保镜像在最前面
            project.repositories {
                // 清空现有仓库（谨慎操作，但有必要）
                clear()

                // 将镜像放在最前面
                maven { url = uri("https://maven.aliyun.com/repository/google") }
                maven { url = uri("https://maven.aliyun.com/repository/public") }
                maven { url = uri("https://maven.aliyun.com/repository/central") }
                maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
                maven { url = uri("https://jitpack.io") }

                println("🔧 已为子项目 ${project.name} 强制配置阿里云镜像")
            }
        }
    }
}

// 🔥🔥🔥 特别针对 flutter_plugin_android_lifecycle 的早期干预
// 这个配置在项目加载时执行，确保依赖能正确下载
gradle.projectsLoaded {
    rootProject.subprojects.forEach { project ->
        // 针对所有可能触发 classpath 下载的子项目
        if (project.name.contains("lifecycle") ||
            project.name.contains("plugin") ||
            project.name == "flutter_plugin_android_lifecycle") {

            project.buildscript {
                repositories {
                    clear()
                    maven { url = uri("https://maven.aliyun.com/repository/google") }
                    maven { url = uri("https://maven.aliyun.com/repository/public") }
                    maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
                }
                println("🎯 特别为 ${project.name} 配置了 buildscript 镜像")
            }
        }
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
}

subprojects {
    project.evaluationDependsOn(":app")
}

// 强制所有子项目使用AGP 8.13.1版本
allprojects {
    configurations.all {
        resolutionStrategy {
            force("com.android.tools.build:gradle:8.13.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
