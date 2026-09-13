## Dev-only: photographs the screens whose layout no assertion can judge.
##
## Run *without* --headless. The things most likely to break a heads-up display
## are the ones no harness can see: an extra club in hand makes the fan wider, a
## shelf of equipment makes the bar longer, a ladder grows a rung, and all of
## them look fine in an assertion right up until they run off the screen.
extends SceneTree

const HOLE_SCREEN := preload("res://scenes/run/hole_screen.tscn")
const TOUR_SCREEN := preload("res://scenes/ui/tour_screen.tscn")
const SCORECARD_SCREEN := preload("res://scenes/ui/scorecard_screen.tscn")
const OUT := "user://hud.png"
## Long enough for the flyover to finish and the deal to settle.
const FRAMES := 260

var frames := 0
var _screen: Node
var _was_unlocked := 0


func _initialize() -> void:
	_screen = HOLE_SCREEN.instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	frames += 1
	if DisplayServer.get_name() == "headless":
		print("nothing to photograph: run this one with a window")
		return true

	if frames == 2:
		# A full shelf and a hand one card over, which is the combination that
		# has never been drawn before.
		var carried: Array[RelicSpec] = []
		for id in [&"fourteenth_club", &"range_token", &"green_book",
				&"shot_tracer", &"sponsors_bonus"]:
			var relic := RelicLibrary.by_id(id)
			if relic != null:
				carried.append(relic)
		_screen.setup(HoleGenerator.generate(31337, 2, 1),
			Deck.new(load("res://resources/decks/starting_deck.tres").build()))
		_screen.setup_run(carried, 0)
		_screen.begin()
	elif frames == FRAMES:
		var view: HoleView = _screen.get_node("HoleView")
		print("hand %d, focus %d, equipment %d"
			% [view.deck.hand.size(), view.focus, view.relics.size()])
		_grab(OUT)
		# And the ladder, with every rung unlocked so the longest version of the
		# list is the one that gets looked at.
		_screen.queue_free()
		TourLibrary.ensure_career_loaded()
		_was_unlocked = TourLibrary.unlocked_rung
		TourLibrary.unlocked_rung = TourLibrary.all().size() - 1
		_screen = TOUR_SCREEN.instantiate()
		root.add_child(_screen)
	elif frames == FRAMES + 40:
		_grab("user://ladder.png")
		# Put the career back: photographing the game must not promote you.
		TourLibrary.unlocked_rung = _was_unlocked
		_screen.queue_free()
		_screen = SCORECARD_SCREEN.instantiate()
		root.add_child(_screen)
	elif frames == FRAMES + 42:
		_screen.show_card(_finished_round(), TourLibrary.by_rung(2), true,
			TourLibrary.by_rung(3))
	elif frames >= FRAMES + 90:
		_grab("user://scorecard.png")
		return true
	return false


## Eighteen holes with something of everything on them, so the card is looked at
## in its longest form with every mark it can draw actually on it.
func _finished_round() -> RunState:
	var run := RunState.new()
	run.round_holes = 18
	run.leaderboard = Leaderboard.new(4242, -0.26)
	var pars := [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4]
	var shot := [4, 4, 4, 3, 5, 3, 7, 4, 4, 5, 2, 5, 4, 6, 3, 3, 4, 4]
	for i in pars.size():
		run.record_hole(int(shot[i]), int(pars[i]))
	run.add_winnings(430)
	return run


func _grab(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))
