# Placeholders
## AI generated placeholder assets
assets/ui/splash.png

## Project-authored shaders
assets/terrain/terrain_shader.gdshader : written from scratch for this project.
The triplanar-weighting and world-hash-variation idioms follow the standard
zylann.voxel demo approach (upstream demos, MIT); no upstream code is copied —
per-voxel CUSTOM1 decoding is deliberately absent (F14 dead end).
The terrain shader now also samples PBR layer arrays (albedo, normal, ORME); the normal blend is the whiteout method (public technique).

## Purchased assets
animpic
Realer Than Real

## CC0
ambientCG: Ground037 (1K PNG, MILD_GREEN variant), Metal052C (1K PNG, IRON-ROUGH), Metal047B (1K PNG, COPPER-DIRTY); packed via tools/pbr/pbr_pack_cli.gd into assets/pbr/
