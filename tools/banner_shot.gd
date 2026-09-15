## Dev-only: renders wide, HUD-less course plates for the itch.io page banner.
##
## Run *without* --headless, and wide:
##   Godot_console.exe --resolution 2560x800 --path . --script res://tools/banner_shot.gd
##
## The project stretches on "expand", so a wider window genuinely shows more of
## the course rather than letterboxing it -- which is the whole reason these are
## rendered rather than drawn. The art in this game is the course; a banner
## should be a photograph of it, not an illustration of something else.
##
## Writes several candidates because which hole looks good is a matter of taste
## and cannot be asserted. Pick one and composite the logo onto it.
extends SceneTree

const HOLE_SCREEN := preload("res://scenes/run/hole_screen.tscn")
## Seeds worth photographing, chosen for having something to look at: water, a
## stand of trees, bunkers with a green behind them.
## Seeds worth photographing, chosen for having something to look at: water, a
## stand of trees, bunkers with a green behind them. `from_pin` frames the shot
## relative to the flag rather than the middle of the hole, because the green end
## is the pretty end -- and `zoom` above one crops into the course so it fills
## the banner instead of floating in a field of out-of-bounds.
const CANDIDATES := [
	{"seed": 909, "tier": 4, "zoom": 1.85, "from_pin": Vector2(-520.0, 0.0)},
	{"seed": 909, "tier": 4, "zoom": 1.55, "from_pin": Vector2(-620.0, 20.0)},
	{"seed": 909, "tier": 4, "zoom": 2.30, "from_pin": Vector2(-330.0, 10.0)},
	{"seed": 909, "tier": 4, "zoom": 1.55, "from_pin": Vector2(-260.0, 0.0)},
]

var _index := 0
var _frames := 0
var _screen: Node = null


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("nothing to photograph: run this one with a window")
		return
	_next_hole()


func _process(_delta: float) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	_frames += 1
	# A few frames for the course to build its textures and the camera to settle.
	if _frames < 12:
		return false

	_grab("user://banner_%d.png" % _index)
	_index += 1
	_frames = 0
	if _index >= CANDIDATES.size():
		return true
	_next_hole()
	return false


func _next_hole() -> void:
	if _screen != null:
		_screen.queue_free()
	var spec: Dictionary = CANDIDATES[_index]
	var hole := HoleGenerator.generate(int(spec["seed"]), int(spec["tier"]), 1)

	_screen = HOLE_SCREEN.instantiate()
	_screen.setup(hole, Deck.new(
		load("res://resources/decks/starting_deck.tres").build()))
	root.add_child(_screen)

	# No heads-up display: this is a picture of a golf course.
	var ui := _screen.get_node_or_null("UI")
	if ui != null:
		ui.hide()

	var view: HoleView = _screen.get_node("HoleView")
	var camera: Camera2D = view.get_node("Camera2D")
	# The camera chases the ball and eases towards it every frame, so it has to
	# be switched off before being told where to stand.
	camera.set_process(false)
	camera.set_physics_process(false)

	# root is the window and is its own viewport, but get_viewport() on it is
	# still null during _initialize -- so ask the window for its rect instead,
	# which is valid from the first line.
	var size := root.get_visible_rect().size
	var fit := size.y / maxf(hole.bounds.size.y, 1.0)
	camera.zoom = Vector2.ONE * fit * float(spec["zoom"])
	camera.position = hole.pin_position + (spec["from_pin"] as Vector2)
	camera.force_update_scroll()

	print("candidate %d: seed %d tier %d, %s, %d yards, %d hazards" % [
		_index, int(spec["seed"]), int(spec["tier"]),
		"woodland" if hole.woodland else "open",
		int(hole.hole_length_yards()), hole.hazards.size()])


func _grab(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("  wrote %s" % ProjectSettings.globalize_path(path))
