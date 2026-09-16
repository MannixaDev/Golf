## Dev-only: photographs the screens whose layout no assertion can judge.
##
## Run *without* --headless. The things most likely to break a heads-up display
## are the ones no harness can see: an extra club in hand makes the fan wider, a
## shelf of equipment makes the bar longer, a ladder grows a rung, and all of
## them look fine in an assertion right up until they run off the screen.
extends SceneTree

const HOLE_SCREEN := preload("res://scenes/run/hole_screen.tscn")
const TOUR_SCREEN := preload("res://scenes/ui/tour_screen.tscn")
const SPLASH_SCREEN := preload("res://scenes/ui/splash_screen.tscn")
const SCORECARD_SCREEN := preload("res://scenes/ui/scorecard_screen.tscn")
const OUT := "user://hud.png"
## Long enough for the flyover to finish and the deal to settle.
const FRAMES := 260

var frames := 0
var _screen: Node
var _was_unlocked := 0


func _initialize() -> void:
	# Deliberately not added here. HoleView wires the renderer to its hole in
	# _ready, so a screen that joins the tree before setup() draws the scene's
	# placeholder hole for ever after -- which is how these photographs came to
	# show a flag and cup belonging to a completely different golf hole.
	_screen = HOLE_SCREEN.instantiate()


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
		# A woodland hole specifically, since that is the thing being looked at.
		var hole := HoleGenerator.generate(31337, 2, 1)
		for attempt in 200:
			if hole.woodland:
				break
			hole = HoleGenerator.generate(31337 + attempt, 2, 1)
		print("woodland: %s" % hole.woodland)
		# A bag that can actually combine, because the whole point of the
		# conditional cards is whether the player can see one coming -- and no
		# assertion anywhere can answer that.
		var bag: Array[CardData] = load("res://resources/decks/starting_deck.tres").build()
		for extra in [&"draw", &"follow_through", &"double_cross", &"up_and_down"]:
			var got := CardLibrary.copy(extra)
			if got != null:
				bag.append(got)
		_screen.setup(hole, Deck.new(bag))
		root.add_child(_screen)
		_screen.setup_run(carried, 0)
		_screen.begin()
	elif frames == 6:
		# Stood on the green, because the flag and the ball are sized against it
		# and neither can be judged from the tee.
		var view: HoleView = _screen.get_node("HoleView")
		view._ball.reset_to(view.hole.pin_position
			+ Vector2(-view.hole.green_extent() * 0.7, 0.0))
		var camera: Camera2D = view.get_node("Camera2D")
		camera.position = view.hole.pin_position
		camera.zoom = Vector2(2.2, 2.2)
	elif frames == FRAMES - 30:
		# Staged late, once the hole has actually begun: anything done during the
		# flyover is wiped when the first turn starts, and the hand is still
		# sliding up from below the screen.
		var view: HoleView = _screen.get_node("HoleView")
		_play_by_id(view, &"draw")
		if _card_by_id(view, &"double_cross") == null:
			view.deck.hand.append(CardLibrary.copy(&"double_cross"))
		var candidate := _card_by_id(view, &"double_cross")
		print("in hand, double cross would combine: %s" % view.would_combine(candidate))
		_select_a_club(view)
	elif frames == FRAMES - 10:
		# Armed but not spent: the card that answers the Draw is in hand wearing
		# the gold. This is the state the whole feature exists for.
		_grab("user://combo_armed.png")
		var view: HoleView = _screen.get_node("HoleView")
		_play_by_id(view, &"double_cross")
		_select_a_club(view)
		print("combining: %s" % str(view.live_combinations()))
	elif frames == FRAMES:
		var view: HoleView = _screen.get_node("HoleView")
		print("hand %d, focus %d, equipment %d"
			% [view.deck.hand.size(), view.focus, view.relics.size()])
		_grab(OUT)
		# Then right down on the hole, at the zoom the camera actually reaches
		# when you are putting, with the ball where a missed short one finishes.
		#
		# This picture is the one that would have caught the ball being drawn
		# wider than the entire cup: no assertion was ever going to notice that
		# a miss looked holed, and nothing here had ever been photographed from
		# closer than the whole green.
		var camera: Camera2D = view.get_node("Camera2D")
		camera.position = view.hole.pin_position
		camera.zoom = Vector2(5.2, 5.2)
		# Just outside the hole: the exact rest the bug report was about.
		view._ball.reset_to(view.hole.pin_position
			+ Vector2(2.2, 1.2).normalized() * view.hole.cup_pixels() * 1.9)
	elif frames == FRAMES + 40:
		var view: HoleView = _screen.get_node("HoleView")
		var camera: Camera2D = view.get_node("Camera2D")
		print("cup %s r %.2f, ball %s r %.2f, camera %s zoom %.2f" % [
			view.hole.pin_position, view.hole.cup_pixels(),
			view._ball.position, view._ball.drawn_radius(),
			camera.position, camera.zoom.x])
		_grab("user://cup.png")
	elif frames == FRAMES + 46:
		# And the ladder, with every rung unlocked so the longest version of the
		# list is the one that gets looked at.
		_screen.queue_free()
		TourLibrary.ensure_career_loaded()
		_was_unlocked = TourLibrary.unlocked_rung
		TourLibrary.unlocked_rung = TourLibrary.all().size() - 1
		_screen = TOUR_SCREEN.instantiate()
		root.add_child(_screen)
	elif frames == FRAMES + 86:
		_grab("user://ladder.png")
		# Put the career back: photographing the game must not promote you.
		TourLibrary.unlocked_rung = _was_unlocked
		_screen.queue_free()
		_screen = SCORECARD_SCREEN.instantiate()
		root.add_child(_screen)
	elif frames == FRAMES + 88:
		_screen.show_card(_finished_round(), TourLibrary.by_rung(2), true,
			TourLibrary.by_rung(3))
	elif frames == FRAMES + 136:
		_grab("user://scorecard.png")
		_screen.queue_free()
		_screen = SPLASH_SCREEN.instantiate()
		root.add_child(_screen)
	elif frames == FRAMES + 150:
		# The guided hole, at the step that does the most work: a technique on the
		# stroke, a card gone gold, and the lesson explaining why. No assertion
		# can tell whether a panel of prose over a golf hole is readable.
		_screen.queue_free()
		var lesson: TutorialLesson = load("res://resources/tutorial/first_lesson.tres")
		var hole := HoleGenerator.generate(
			TutorialDirector.HOLE_SEED, TutorialDirector.HOLE_TIER, 1)
		var bag: DeckList = load("res://resources/decks/tutorial_deck.tres")
		_screen = HOLE_SCREEN.instantiate()
		_screen.setup(hole, Deck.new(bag.build()))
		root.add_child(_screen)
		_screen.begin()
		var view: HoleView = _screen.get_node("HoleView")
		_play_by_id(view, &"draw")
		_select_a_club(view)
		_screen.set_lesson(lesson.playable_steps()[4].text)
	elif frames == FRAMES + 182:
		_grab("user://lesson.png")
	elif frames >= FRAMES + 200:
		_grab("user://splash.png")
		return true
	return false


## Pick up the first club in hand, so the swing panel and the staged profile are
## both live for the photograph.
func _select_a_club(view: HoleView) -> void:
	for i in view.deck.hand.size():
		if view.deck.hand[i].is_shot():
			view.activate_card(i)
			return


## A card in hand, by id. Hands hold copies, so identity comparison never works.
func _card_by_id(view: HoleView, id: StringName) -> CardData:
	for card in view.deck.hand:
		if card != null and card.id == id:
			return card
	return null


## Play a named card out of hand, putting one there if the deal did not.
func _play_by_id(view: HoleView, id: StringName) -> void:
	if _card_by_id(view, id) == null:
		var forced := CardLibrary.copy(id)
		if forced == null:
			return
		view.deck.hand.append(forced)
	for i in view.deck.hand.size():
		if view.deck.hand[i].id == id:
			view.activate_card(i)
			return


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
