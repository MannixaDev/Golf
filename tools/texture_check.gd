## Asserts the generated textures are actually textures.
##
## A procedural texture that silently comes out blank does not throw anything --
## it just draws nothing, and the course quietly goes back to looking like flat
## fills. That is a hard bug to spot by eye, because "slightly less texture than
## intended" and "no texture at all" look the same in a screenshot until you put
## them side by side.
extends SceneTree

var failures := 0


func _initialize() -> void:
	print("=== generated textures ===")

	TextureBank.clear_cache()
	_check_grain("turf grain", TextureBank.turf_grain(), 0.02)
	_check_grain("sand grain", TextureBank.sand_grain(), 0.03)
	_check_grain("turf mottle", TextureBank.turf_mottle(), 0.01)
	_check_gradient("soft shadow", TextureBank.soft_shadow())
	_check_gradient("soft light", TextureBank.soft_light())
	_check_caching()
	_check_seamless()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## Grain must vary. A texture whose pixels are all the same is a flat fill with
## extra steps, and that is exactly the failure this is here to catch.
func _check_grain(label: String, texture: Texture2D, min_spread: float) -> void:
	if texture == null:
		_expect(false, "%s did not generate" % label)
		return
	var image := texture.get_image()
	var lowest := 2.0
	var highest := -1.0
	var total := 0.0
	var light := 0
	var dark := 0

	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			lowest = minf(lowest, pixel.a)
			highest = maxf(highest, pixel.a)
			total += pixel.a
			if pixel.a > 0.02:
				if pixel.r > 0.5:
					light += 1
				else:
					dark += 1

	var mean := total / float(image.get_width() * image.get_height())
	print("  %-12s %dx%d  alpha %.3f..%.3f  mean %.3f  %d light / %d dark" % [
		label, image.get_width(), image.get_height(), lowest, highest, mean,
		light, dark])

	_expect(highest - lowest >= min_spread, "%s has no variation in it" % label)
	_expect(mean > 0.005, "%s is effectively transparent" % label)
	# Loud grain reads as static, not as ground, and shifts the surface's
	# brightness enough to collapse the palette's value ladder. Held hard.
	_expect(highest <= 0.22,
		"%s is too strong: grain must not compete with the colour under it" % label)
	# Both directions, or grass gets lighter or darker overall rather than mottled.
	_expect(light > 0 and dark > 0,
		"%s should speckle both lighter and darker" % label)


func _check_gradient(label: String, texture: Texture2D) -> void:
	if texture == null:
		_expect(false, "%s did not generate" % label)
		return
	var image := texture.get_image()
	var size := image.get_width()
	var middle := image.get_pixel(size / 2, size / 2).a
	var corner := image.get_pixel(1, 1).a
	var edge := image.get_pixel(size / 2, 0).a

	print("  %-12s centre %.3f  edge %.3f  corner %.3f" % [
		label, middle, edge, corner])
	_expect(middle > 0.8, "%s should be solid in the middle" % label)
	_expect(edge < 0.05, "%s should have faded out by its rim" % label)
	_expect(corner < 0.01, "%s should be gone in the corners" % label)


## Generation is not cheap, and the renderer asks for these on every redraw.
func _check_caching() -> void:
	print("")
	print("=== built once ===")
	TextureBank.clear_cache()
	var first := TextureBank.turf_grain()
	var second := TextureBank.turf_grain()
	print("  same instance returned twice: %s" % (first == second))
	_expect(first == second, "textures should be cached, not rebuilt per call")


## The grain tiles across the whole hole, so a discontinuity at the seam would
## show up as a grid over the course.
func _check_seamless() -> void:
	print("")
	print("=== tiles without a seam ===")
	var image := TextureBank.turf_grain().get_image()
	var size := image.get_width()
	var worst := 0.0

	for i in size:
		# The right edge has to meet the left edge, and the bottom the top.
		worst = maxf(worst, absf(
			image.get_pixel(size - 1, i).a - image.get_pixel(0, i).a))
		worst = maxf(worst, absf(
			image.get_pixel(i, size - 1).a - image.get_pixel(i, 0).a))

	print("  worst jump across a seam: %.3f" % worst)
	_expect(worst < 0.22, "the grain shows a visible seam where it repeats")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
