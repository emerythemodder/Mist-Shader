# Mist

A path-traced shader pack for Iris. Light, shadows and reflections are traced through a voxel copy of the world around you, so torches cast real shadows, caves are lit by light bouncing off their walls, and water reflects what is actually there.

## Lighting
- Sun shadows traced to the sun's disk: sharp where things touch, soft where they fall far
- Torches, lanterns, lava and other light sources light the world with their own shadows and colour
- Bounced light from the sun, the sky and glowing blocks
- Ray-traced reflections on water, metal and polished blocks
- Volumetric clouds, cloud shadows, light shafts and biome fog

## Water
- Waves, refraction, absorption and caustics
- Ripples from you, players and mobs that bounce off walls and blocks
- Splashes simulated with MLS-MPM when you jump in, drawn as real water

## World
- Footprints in snow and sand that stay where they're made
- 3D snow and plants that bend out of your way
- Generated parallax and material response (gloss, metal, gems) for blocks without a resource pack
- Smooth terrain: natural ground without blocky corners (needs the Mist Iris Extension)

## Compatibility
- Minecraft 26.3, Iris 1.11.6 or newer, Sodium
- Voxy and Distant Horizons: distant terrain is lit, shadowed and fogged with the rest of the world
- Physics Mod ocean

## Mist Iris Extension (optional)
A small Iris add-on that unlocks smooth terrain and makes Mist's shadow pass cheaper by redrawing distant chunks in turns instead of every frame. Works with the normal Iris and Sodium. You can download it in the mod branch of this repo

## Performance
Mist is heavy. A recent mid-range or better GPU is recommended; lower RT Light Traces and render distance if you need more frames.
