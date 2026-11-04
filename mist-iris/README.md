# Mist Iris Extension

Iris add-on for the Mist shader pack (Minecraft 26.3, Iris 1.11.6+, Sodium 0.9.x).

- `at_neighbors` vertex attribute for terrain (used by smooth terrain)
- entity/block tracking uniforms
- cheaper shadow pass for Mist: near chunk columns every frame, far ones in turns

## Building

Put the Iris jar you play with in `libs/` (name set by `iris_jar` in `gradle.properties`), then:

    ./gradlew build

The jar ends up in `build/libs/`.
