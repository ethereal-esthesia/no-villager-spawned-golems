# no-villager-spawned-golems

A small Paper plugin that prevents villagers from spawning iron golems while
still allowing players to build iron golems normally.

## What It Does

The plugin listens for Bukkit/Paper `CreatureSpawnEvent`s and checks iron golem
spawn reasons.

Allowed:

- Player-built iron golems, reported by Paper as `BUILD_IRONGOLEM`

Blocked:

- Villager-spawned iron golems
- Command-spawned iron golems
- Spawn egg iron golems
- Any other iron golem spawn reason not explicitly allowed

Other mobs are ignored.

## Requirements

- Paper or a compatible Bukkit/Spigot-derived server
- Java 21+ for the plugin
- The Java version required by your Paper server build
- Minecraft/Paper API 1.21+

## Build

Use the included Gradle wrapper:

```bash
./gradlew build
```

The plugin jar will be written to:

```text
build/libs/NoVillagerSpawnedGolems-1.0.0.jar
```

## Paper Integration Test

The project includes a Paper integration test:

```bash
./scripts/paper-integration-test.sh
```

The test downloads the latest stable Paper server, installs the plugin, starts a
temporary local server, and verifies:

1. An iron golem created from block commands spawns successfully.
2. `/summon minecraft:iron_golem` does not leave an iron golem in the world.

GitHub Actions runs this test on every push, every pull request, manually, and
once per week.

## Releases

Release versions are pinned from `pluginVersion` in [gradle.properties](gradle.properties).

To publish from GitHub:

1. Update `pluginVersion`.
2. Push to `main`.
3. Run the `Release` workflow manually and type `release` when prompted.

The release workflow runs the Paper integration test first. If the tests pass,
it publishes a GitHub release tagged as `v<pluginVersion>` and attaches the
matching jar.

## Install

1. Stop your Minecraft server.
2. Copy the jar into the server's `plugins/` folder.
3. Start the server again.

On startup, the server log should include:

```text
[NoVillagerSpawnedGolems] Enabled. Allowing iron golem spawn reasons: [BUILD_IRONGOLEM]
```

## Configuration

There is no configuration file. The plugin has one fixed rule: only
player-built iron golems are allowed.

## License

This project is licensed under the GNU General Public License v3.0.
See [LICENSE](LICENSE).
