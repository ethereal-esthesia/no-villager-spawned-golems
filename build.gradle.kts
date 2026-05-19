plugins {
    java
}

group = "dev.shane.minecraft"
version = providers.gradleProperty("pluginVersion").get()
description = "Paper plugin that allows player-built iron golems while blocking villager-spawned golems."

val paperApiVersion = providers.gradleProperty("paperApiVersion").get()
val paperApiDependencyVersion = providers.gradleProperty("paperApiDependencyVersion").get()

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
