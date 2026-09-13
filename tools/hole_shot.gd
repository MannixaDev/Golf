## Dev-only: render one hole of each length so the camera framing can be judged
## by eye at both extremes.
##
## The scale rework made holes different sizes in world pixels for the first
## time, which means the camera now has a shortest case and a longest case that
## behave differently. A screenshot of whichever hole happened to come up tells
## you about neither.
extends SceneTree

## par, tier, and a seed that reliably produces that par.
const CASES := [
	["short", 3, 0],
	["mid", 4, 2],
	["long", 5, 4],
]
const TICK_FRAMES := 60

var frames := 0
var main: Node
var stage := 0
var _grab_next := ""


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _grab(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = root.get_texture().get_image()
	image.save_png("user://" + file_name)
	print("saved: " + file_name)


## Keep generating until a hole of the wanted par turns up, so each capture is
## actually the case it claims to be.
func _hole_of_par(par: int, tier: int) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for attempt in 400:
		var hole := HoleGenerator.generate(rng.randi(), tier, 1)
		if hole.par == par:
			return hole
	return HoleGenerator.generate(1, tier, 1)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < TICK_FRAMES:
		return false
	frames = 0

	if _grab_next != "":
		_grab(_grab_next)
		_grab_next = ""

	if stage >= CASES.size():
		quit(0)
		return true

	var case: Array = CASES[stage]
	var hole := _hole_of_par(int(case[1]), int(case[2]))
	var screen: HoleScreen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(hole, Deck.new(load("res://resources/decks/starting_deck.tres").build()))
	main._swap_screen(screen)
	screen.begin()
	print("  %-6s par %d, %.0f yd, world %.0f x %.0f px" % [
		case[0], hole.par, hole.hole_length_yards(),
		hole.bounds.size.x, hole.bounds.size.y])
	_grab_next = "m10_hole_%s.png" % case[0]

	stage += 1
	return false
