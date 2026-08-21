# Placeholders
## AI generated placeholder assets
assets/ui/splash.png

## Generated placeholder art (project tooling)
assets/terrain/textures/ground.png, rock.png : `tools/terrain_texture_generator.gd`
(seamless 4-corner-blend value noise, deterministic seeds — regenerate at will;
prototype stand-ins for the terrain shader's depth bands until the art pass)

## Project-authored shaders
assets/terrain/terrain_shader.gdshader : written from scratch for this project.
The triplanar-weighting and world-hash-variation idioms follow the standard
zylann.voxel demo approach (upstream demos, MIT); no upstream code is copied —
per-voxel CUSTOM1 decoding is deliberately absent (F14 dead end).

## Purchased assets
assets/ground.png : MT00614-Debris_Ground
assets/wood.png : MT00198-Old_Peeling_Wood