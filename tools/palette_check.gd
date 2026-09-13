## Asserts the palette's value ladder, in greyscale.
##
## The original course was picked one colour at a time and ended up with a dozen
## greens sitting at nearly the same brightness. Everything was distinguishable
## by hue and almost nothing by value, so the hole turned into a flat wash the
## moment you stopped concentrating.
##
## This measures perceived brightness rather than trusting the hex codes to look
## different, and fails if two surfaces that need to read apart have drifted
## together. It is the same discipline the rest of the project uses for balance:
## measure it, do not eyeball it.
extends SceneTree

## Relative luminance weights. Green dominates because human vision says so; this
## is why two colours can look completely different and still be the same grey.
const R_WEIGHT := 0.2126
const G_WEIGHT := 0.7152
const B_WEIGHT := 0.0722

## Neighbouring rungs must differ by at least this much brightness. Below about
## 0.04 the eye stops separating them reliably at a glance.
const MIN_STEP := 0.045
## The fairway against the rough is held to a much higher bar than that. See
## _check_the_big_two.
const BIG_AREA_STEP := 0.24

var failures := 0


func _initialize() -> void:
	print("=== the value ladder ===")

	# In the order they must appear, darkest first. Water is deliberately absent:
	# it sits inside this range and is allowed to, because it separates by hue.
	var ladder := [
		["scrub", Palette.SCRUB],
		["rough", Palette.ROUGH],
		["first cut", Palette.FIRST_CUT],
		["fairway", Palette.FAIRWAY],
		["stripe", Palette.FAIRWAY_STRIPE],
		["green", Palette.GREEN],
		["sand", Palette.SAND],
	]

	var previous := -1.0
	var previous_name := ""
	for rung in ladder:
		var name: String = rung[0]
		var value := _luminance(rung[1])
		var step := value - previous if previous >= 0.0 else 0.0
		print("  %-10s %.3f%s" % [
			name, value, "" if previous < 0.0 else "   +%.3f" % step])
		if previous >= 0.0:
			_expect(step >= MIN_STEP,
				"%s and %s are the same grey (%.3f apart, need %.3f)" % [
					previous_name, name, step, MIN_STEP])
		previous = value
		previous_name = name

	_check_the_big_two()
	_check_water_separates_by_hue()
	_check_trouble_reads_against_its_ground()
	_check_surfaces_match_the_palette()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## The fairway and the rough are the two largest areas on screen by a wide
## margin, and the whole hole reads through the boundary between them. A step
## that is merely "different enough" for two small shapes is nowhere near enough
## here -- an earlier pass passed the ladder check with half this gap and turned
## the entire hole into one flat wash of green.
func _check_the_big_two() -> void:
	print("")
	print("=== the fairway reads against the rough ===")

	var gap := _luminance(Palette.FAIRWAY) - _luminance(Palette.ROUGH)
	print("  fairway stands %.3f above the rough (need %.3f)" % [gap, BIG_AREA_STEP])
	_expect(gap >= BIG_AREA_STEP, "the fairway does not read against the rough")


## Water is allowed to share a brightness with the turf around it, but then it
## has to earn its separation somewhere else.
func _check_water_separates_by_hue() -> void:
	print("")
	print("=== water reads as water ===")

	var water := Palette.WATER_DEEP
	var value := _luminance(water)
	print("  water sits at %.3f, between first cut and rough" % value)

	# Blueness: how far the blue channel runs ahead of the green one. Turf has
	# this deeply negative, water must have it clearly positive.
	var water_blue := water.b - water.g
	print("  water blue-over-green: %+.3f" % water_blue)
	_expect(water_blue > 0.05, "water should be unmistakably blue")

	for pair in [["rough", Palette.ROUGH], ["first cut", Palette.FIRST_CUT],
			["scrub", Palette.SCRUB]]:
		var turf: Color = pair[1]
		var turf_blue := turf.b - turf.g
		_expect(turf_blue < -0.05, "%s should be unmistakably not blue" % pair[0])


## Sand in the rough, sand on a green, a ball on any of it: the things you have
## to spot must stand off whatever they are sitting on.
func _check_trouble_reads_against_its_ground() -> void:
	print("")
	print("=== things stand off their background ===")

	var pairs := [
		["sand on fairway", Palette.SAND, Palette.FAIRWAY],
		["sand on rough", Palette.SAND, Palette.ROUGH],
		["water on rough", Palette.WATER_DEEP, Palette.ROUGH],
		["scrub on rough", Palette.SCRUB, Palette.ROUGH],
		["ball on green", Palette.BALL, Palette.GREEN],
		["ball on fairway", Palette.BALL, Palette.FAIRWAY],
	]
	for pair in pairs:
		var gap := _separation(pair[1], pair[2])
		print("  %-18s %.3f apart" % [pair[0], gap])
		_expect(gap >= MIN_STEP * 2.0,
			"%s does not stand out enough" % pair[0])


## How far apart two colours look, counting brightness *and* hue.
##
## A luminance-only measure fails water: a pond is deliberately the same
## brightness as the rough around it and separates entirely by being blue, so a
## brightness test calls it invisible when it is the most obvious thing on the
## hole. Two things may separate on either axis, but they must separate on one.
##
## The second axis is blue-versus-yellow, which is the one that matters here:
## everything on a golf course is either grass or sand except the water.
func _separation(a: Color, b: Color) -> float:
	var d_value := _luminance(a) - _luminance(b)
	var d_blue := _blue_yellow(a) - _blue_yellow(b)
	return sqrt(d_value * d_value + d_blue * d_blue)


func _blue_yellow(colour: Color) -> float:
	return colour.b - (colour.r + colour.g) * 0.5


## Surfaces are data, so their colours live in `.tres` files rather than in the
## palette script. That is the right place for them, but it means the two can
## drift. This is the tie: change a surface without changing the palette and the
## build fails, so the palette stays the single source of truth in practice and
## not just in the comments.
func _check_surfaces_match_the_palette() -> void:
	print("")
	print("=== surface data agrees with the palette ===")

	var expected := {
		&"bunker": Palette.SAND,
		&"deep_rough": Palette.SCRUB,
		&"divot": Palette.EARTH,
		&"fairway": Palette.FAIRWAY,
		&"green": Palette.GREEN,
		&"rough": Palette.ROUGH,
		&"tee": Palette.TEE,
		&"water": Palette.WATER_DEEP,
		&"wet_patch": Palette.MARSH,
	}

	for id in expected:
		var surface := SurfaceLibrary.by_id(id)
		if surface == null:
			_expect(false, "no surface called %s" % id)
			continue
		var want: Color = expected[id]
		var matches := _same(surface.colour, want)
		print("  %-11s %s %s" % [id, surface.colour.to_html(false),
			"" if matches else "!= palette " + want.to_html(false)])
		_expect(matches, "%s has drifted from the palette" % id)


## Colours survive a round trip through a .tres as three-decimal floats, so an
## exact comparison would fail on rounding alone.
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 \
		and absf(a.b - b.b) < 0.004


func _luminance(colour: Color) -> float:
	return R_WEIGHT * colour.r + G_WEIGHT * colour.g + B_WEIGHT * colour.b


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
