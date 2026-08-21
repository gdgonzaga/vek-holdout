extends SceneTree
## Placeholder terrain band-texture generator (terrain visuals, F14 fallback).
## Writes two seamless 256x256 PNGs into assets/terrain/textures/:
##   ground.png — dirt mottle (near-surface band)
##   rock.png   — gray stone (deep band)
## Prototype art until the art pass (AGENTS.md); deterministic (fixed seeds),
## so regeneration is idempotent. Run headless:
##   godot --headless --path . -s res://tools/terrain_texture_generator.gd
## Seamless via the classic 4-corner torus blend: each texel blends the four
## noise lookups of its position and its three wrapped copies, weighted by
## distance to the edges, so opposite texture edges match exactly.
##
## GPU-only usage: the terrain shader samples these as uniforms; nothing reads
## their pixels back, so the default (compressed) import is fine — unlike the
## heightmaps, which need Lossless (HOWTO-author-maps).

const SIZE := 256
const OUT_DIR := "res://assets/terrain/textures"
const GROUND_A := Color(0.40, 0.29, 0.18)
const GROUND_B := Color(0.56, 0.45, 0.31)
const ROCK_A := Color(0.43, 0.43, 0.46)
const ROCK_B := Color(0.63, 0.63, 0.66)


func _init() -> void:
	var dir := DirAccess.open("res://assets")
	dir.make_dir_recursive("terrain/textures")
	_write("ground.png", GROUND_A, GROUND_B, 20260821, 0.055)
	_write("rock.png", ROCK_A, ROCK_B, 20260822, 0.03)
	print("terrain textures written to %s (%dx%d)" % [OUT_DIR, SIZE, SIZE])
	quit()


func _write(file_name: String, a: Color, b: Color, noise_seed: int, freq: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = freq
	noise.fractal_octaves = 3
	var raw := func(px: float, py: float) -> float:
		return clampf(noise.get_noise_2d(px, py) * 0.5 + 0.5, 0.0, 1.0)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var f := float(SIZE)
	for y: int in SIZE:
		for x: int in SIZE:
			var fx := float(x)
			var fy := float(y)
			var v: float = (raw.call(fx, fy) * (f - fx) * (f - fy)
					+ raw.call(fx - f, fy) * fx * (f - fy)
					+ raw.call(fx, fy - f) * (f - fx) * fy
					+ raw.call(fx - f, fy - f) * fx * fy) / (f * f)
			img.set_pixel(x, y, a.lerp(b, v))
	img.save_png("%s/%s" % [OUT_DIR, file_name])
