import io.papermc.hangarpublishplugin.model.Platforms

plugins {
    java
    id("io.papermc.hangar-publish-plugin") version "0.1.2"
}

group = "dev.shane.minecraft"
version = providers.gradleProperty("pluginVersion").get()
description = "Paper plugin that allows player-built iron golems while blocking villager-spawned golems."

val paperApiVersion = providers.gradleProperty("paperApiVersion").get()
val paperApiDependencyVersion = providers.gradleProperty("paperApiDependencyVersion").get()
val hangarProjectId = providers.gradleProperty("hangarProjectId").get()

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    compileOnly("io.papermc.paper:paper-api:$paperApiDependencyVersion")
}

java {
    sourceCompatibility = JavaVersion.VERSION_25
    targetCompatibility = JavaVersion.VERSION_25
}

tasks {
    withType<JavaCompile>().configureEach {
        options.release.set(25)
    }

    processResources {
        val props = mapOf(
            "version" to project.version,
            "paperApiVersion" to paperApiVersion
        )
        inputs.properties(props)
        filteringCharset = "UTF-8"
        filesMatching("plugin.yml") {
            expand(props)
        }
    }

    jar {
        archiveBaseName.set("NoVillagerSpawnedGolems")
        archiveClassifier.set("paper-$paperApiVersion")
    }
}

hangarPublish {
    publications.register("plugin") {
        version.set(project.version as String)
        channel.set("Release")
        id.set(hangarProjectId)
        apiKey.set(providers.environmentVariable("HANGAR_API_TOKEN"))
        changelog.set("Release ${project.version} for Paper $paperApiVersion. Paper integration tests passed before publishing.")

        platforms {
            register(Platforms.PAPER) {
                jar.set(tasks.jar.flatMap { it.archiveFile })
                platformVersions.set(listOf(paperApiVersion))
            }
        }
    }
}
