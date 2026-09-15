## Dev-only: writes a seamlessly tiling page background for the itch.io theme.
##
##   Godot_console.exe --headless --path . --script res://tools/page_background.gd
##
## itch tiles whatever you give it either side of the page column, so this has to
## repeat without a seam and has to stay quiet -- a page background that competes
## with the page is a worse background than a flat colour.
##
## It is the game's own turf, at the game's own deep green, built the same way
## TextureBank builds it: seamless simplex noise turned into a two-sided mask
## over a base colour. Larger than the in-game tile, because a 128 pixel repeat
## across a wide monitor reads as wallpaper rather than as ground.
##
## Takes a couple of minutes: it is half a million pixels touched one at a time
## from GDScript, which is slow and does not matter for something run once.
extends SceneTree

## Power of two, or the wrap shows as a grid.
const SIZE := 512
const OUT := "user://itch_background.png"

## Deep green, from the palette -- the colour the course fades into out of
## bounds, so the page surrounds the game in the same dark it does.
const BASE := Color("#101d14")


func _initialize() -> void:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(BASE)

	# Two passes at different scales, exactly as the course does it: broad slow
	# mottling to break up the flat, then a finer speckle on top. One alone is
	# either featureless or busy.
	_lay_grain(image, 0.020, 0.050, 5150)
	_lay_grain(image, 0.085, 0.028, 1337)

	var err := image.save_png(OUT)
	if err != OK:
		print("could not write %s: %d" % [OUT, err])
		return
	print("wrote %s  (%dx%d, tiles seamlessly)"
		% [ProjectSettings.globalize_path(OUT), SIZE, SIZE])
	print("itch: Edit theme -> Background image, and set repeat.")


## One layer of seamless noise, lightening where it is above the midpoint and
## darkening where it is below.
func _lay_grain(image: Image, frequency: float, strength: float,
		seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	var source := noise.get_seamless_image(SIZE, SIZE)

	for y in SIZE:
		for x in SIZE:
			# get_seamless_image comes back normalised around a 0.5 midpoint.
			var signed_value := (source.get_pixel(x, y).r - 0.5) * 2.0
			var amount := absf(signed_value) * strength
			var current := image.get_pixel(x, y)
			var target := Color(1, 1, 1) if signed_value >= 0.0 else Color(0, 0, 0)
			image.set_pixel(x, y, current.lerp(target, amount))
