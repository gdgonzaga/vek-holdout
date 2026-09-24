# Authoring PBR Textures

> Covers turning a downloaded material (ambientCG, Realer Than Real) into a `PbrTextureSet`, what happens when a source map is missing, and how terrain, blocks and furniture consume the result. Architecture: [Voxel / World](architecture/voxel-world.md), [Data Schemas](architecture/data-schemas.md).

## 1. What a set is

`data/pbr/<id>.tres` (`PbrTextureSet`) holds three maps under `assets/pbr/<id>/`:

| Map | Format | Notes |
|---|---|---|
| `albedo.png` | RGB, sRGB | Alpha is dropped so every albedo compresses to the same VRAM format. |
| `normal.png` | RGB, OpenGL (Y+) | Imported as a two-channel normal map; Z is rebuilt in the shader. |
| `orme.png` | RGBA, linear | Occlusion (R), Roughness (G), Metallic (B), Extra (A, reserved, always 0). |

The terrain stacks its sets into `Texture2DArray`s, which need one size and format per layer: the packer resizes everything to `--size` (default 1024) and emits fixed pixel formats. Blocks and furniture do not use arrays, so their sets may use any size.

## 2. Getting textures from ambientCG

1. Download the 1K PNG variant.
2. Keep only what the packer reads: `_Color`, `_NormalGL`, `_Roughness`, and `_AmbientOcclusion` / `_Metalness` when present. Delete `_NormalDX`, `_Displacement` and preview files before committing (they cost about 4 MB each and nothing reads them).
3. Pack: `godot --headless --path . -s res://tools/pbr/pbr_pack_cli.gd -- <download_folder> <id>`, then `godot --headless --path . --import`.
4. Assign `res://data/pbr/<id>.tres` to a def's `pbr` in the inspector.
5. Record the ambientCG id, variant and resolution in `docs/art.md`. The packed files replace the separate downloads in git, and the ambientCG id lets you re-download.

`<id>` is lower snake_case (`ground037`, `iron_rough`). A single image instead of a folder is packed as an albedo-only set.

## 3. When a map is missing

The packer fills gaps with neutral values, so a packed set is always complete and the shader never checks for missing maps:

| Source map | If absent | Effect |
|---|---|---|
| Color / albedo | Error: no set is produced | Required. |
| NormalGL | NormalDX is used with green flipped; else a flat normal | No bump lighting. |
| Roughness | 1.0 (fully rough) | Matches the terrain's pre-PBR look. |
| AmbientOcclusion | 1.0 (no occlusion) | Barely visible at 1K triplanar anyway. |
| Metalness | 0.0 (non-metal) | Correct for dirt and rock. |
| Displacement, Opacity, Emission | Ignored | No parallax; Extra (A) is always 0. |

If a source is already ORME-packed (Realer Than Real ships `orme.PNG`), it is resized and used as is, with Extra forced to 0. The CLI prints which maps it defaulted.

Priority if a download is incomplete: Normal, then Roughness, then AO, then Metalness.

## 4. Realer Than Real and other non-ambientCG sources

Files are recognised by the last `_`-separated token of their name (`basecolor`, `normal`, `roughness`, `orme`, ...). Their normal-map convention is not stated: if bumps look inverted under a low sun, re-pack with `--flip-normal-y`. Sources above 1024 (their 4K sets) are downscaled, which also shrinks the repo.

## 5. Terrain specifics

- `TerrainMaterialDef.tiles_per_meter` is the triplanar repeat (0.25 = one tile per 4 m). Set it from the material's real-world size on ambientCG.
- The terrain shader takes normal and ORME from the band and from the dominant ore layer per pixel, and stops sampling them beyond `detail_fade_end` (160 m; fade starts at 80 m). `normal_strength` (default 1.0) scales bump depth and `metallic_scale` (default 0.5) scales metallic; all four are shader uniforms with defaults, not per-material data. A metallic ore renders dark unless the map has a sky or reflection probe to reflect.
- A layer whose imported size or format does not match the neutral set is replaced by neutral and reported as `TerrainTextureArrays: '<id>' <map> map does not match ...` at map load. Fix it by re-packing with the CLI (never by hand-importing).

## 6. Blocks and furniture

`BuildableDef.pbr` feeds `PbrMaterialFactory`: a `StandardMaterial3D` normally, or the per-block variation shader when `texture_variation` is on (see [Authoring Blocks](HOWTO-author-blocks.md)). A set with only an albedo is fine.

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `TerrainTextureArrays: ... does not match the shared layer layout` | The set's maps were not produced by the CLI or its `.import` was changed. Re-run the CLI and `--import`. |
| Bumps look inverted | Source is DirectX or unknown: re-pack with `--flip-normal-y`. |
| Terrain too glossy | The set's roughness map is missing (neutral is 1.0, so this is unlikely) or the source roughness is really low. |
| `pbr_pack_cli: no albedo map found` | The folder has no `_Color`, `basecolor` or `albedo` image. |
