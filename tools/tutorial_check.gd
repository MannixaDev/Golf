## Does the guided hole actually get to the end?
##
## A tutorial fails in one particular way: a step waits for something that can
## never happen and the panel sits there for ever, with the player assuming they
## have misunderstood rather than that the game is stuck. Nothing about that
## looks like a bug from the outside -- there is no error, no red, just a
## sentence that will not go away.
##
## So this walks the whole lesson, satisfying each step the way a player would,
## and fails if any of them cannot be satisfied at all.
extends SceneTree

const LESSON := "res://resources/tutorial/first_lesson.tres"
const BAG := "res://resources/tutorial/tutorial_deck.tres"

var failures := 0
var screen: HoleScreen = null
var director: TutorialDirector = null
var prompts: Array[String] = []
var done := false


func _initialize() -> void:
	var hole := HoleGenerator.generate(
		TutorialDirector.HOLE_SEED, TutorialDirector.HOLE_TIER, 1)
	var bag: DeckList = load(BAG)
	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(hole, Deck.new(bag.build()))
	root.add_child(screen)

	director = TutorialDirector.new()
	screen.add_child(director)
	director.prompt_changed.connect(func(text: String) -> void:
		if text != "":
			prompts.append(text))
	director.finished.connect(func() -> void: done = true)


func _process(_delta: float) -> bool:
	_check_the_hole_is_gentle()
	_check_the_bag_is_always_in_hand()
	_check_the_lesson_reaches_the_end()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## The first hole anybody plays should not be the one that teaches them about
## water. Asserted because the seed is a constant and a generator change could
## quietly turn it into something else entirely.
func _check_the_hole_is_gentle() -> void:
	print("=== the hole you learn on ===")
	var hole: HoleData = screen.get_node("HoleView").hole
	var water := 0
	for zone in hole.hazards:
		var surface := SurfaceLibrary.by_id(zone.surface_id)
		if surface != null and surface.catches_ball:
			water += 1
	print("  seed %d: par %d, %d yards, %d hazards, %d of them water, wind %.1f"
		% [TutorialDirector.HOLE_SEED, hole.par, int(hole.hole_length_yards()),
			hole.hazards.size(), water, hole.wind_yards_per_100])
	_expect(hole.par == 4, "the lesson talks about a par four")
	_expect(hole.hole_length_yards() < 380.0,
		"%d yards is too far to reach in two while being talked at"
			% int(hole.hole_length_yards()))
	_expect(water == 0, "the first hole anybody plays has water on it")
	_expect(is_zero_approx(hole.wind_yards_per_100),
		"the lesson never mentions wind, and this hole has some")


## The lesson names specific cards -- pick up the Driver, play Draw, play Double
## Cross -- so those cards have to be in hand when it says so. Six cards, four
## clubs and two techniques, means the whole bag is dealt every time.
func _check_the_bag_is_always_in_hand() -> void:
	print("")
	print("=== the bag the lesson talks about ===")
	var bag: DeckList = load(BAG)
	var deck := Deck.new(bag.build())
	var clubs := 0
	var extras := 0
	for card in deck.cards:
		if card.is_shot():
			clubs += 1
		else:
			extras += 1
	print("  %d cards: %d clubs, %d techniques" % [
		deck.cards.size(), clubs, extras])
	_expect(clubs <= 4, "%d clubs will not all fit a four club hand" % clubs)
	_expect(extras <= 2, "%d techniques will not all fit a two card hand" % extras)

	# Dealt a few times over, because "always" is the claim.
	for attempt in 30:
		deck.reset_for_hole()
		deck.deal_up_to(4, 2)
		var held: Array[StringName] = []
		for card in deck.hand:
			held.append(card.id)
		for wanted in [&"driver", &"putter", &"draw", &"double_cross"]:
			if not held.has(wanted):
				_expect(false, "%s was not dealt, and the lesson asks for it"
					% wanted)
				return
	print("  every card the lesson names is in hand, 30 deals out of 30")


## The walk. Each step is satisfied the way a player would satisfy it.
func _check_the_lesson_reaches_the_end() -> void:
	print("")
	print("=== the lesson runs to the end ===")
	var lesson: TutorialLesson = load(LESSON)
	var steps := lesson.playable_steps()
	_expect(not steps.is_empty(), "the lesson has no steps")

	var view: HoleView = screen.get_node("HoleView")
	screen.begin()
	director.setup(view, steps)

	# Linger holds a line on screen for a few seconds; a harness has no patience
	# and no frames to spare, so it is driven to zero rather than waited out.
	for step in steps:
		step.linger = 0.0

	var guard := 0
	while not done and guard < steps.size() * 3:
		guard += 1
		var before := prompts.size()
		_satisfy(view, director._current())
		if prompts.size() == before and not done:
			_expect(false, "stuck on step %d: %s"
				% [director._at + 1, str(director._current().text).left(48)])
			return
	print("  %d of %d steps shown, lesson %s" % [
		prompts.size(), steps.size(), "finished" if done else "STALLED"])
	_expect(done, "the lesson never reached its last line")


## Do whatever this step is waiting for.
func _satisfy(view: HoleView, step: TutorialStep) -> void:
	if step == null:
		return
	match step.wait:
		TutorialStep.Wait.CARD_SELECTED:
			_activate(view, step.card_id)
		TutorialStep.Wait.TECHNIQUE_PLAYED:
			_activate(view, step.card_id)
		TutorialStep.Wait.COMBINATION_LIVE:
			view._emit_modifiers()
		TutorialStep.Wait.STROKES_PLAYED:
			view.strokes = step.strokes
			view.strokes_changed.emit(view.strokes)
		TutorialStep.Wait.ON_THE_GREEN:
			view.lie_changed.emit(SurfaceLibrary.by_id(&"green"))
		TutorialStep.Wait.HOLED:
			view.hole_completed.emit(3, 4, true)


func _activate(view: HoleView, id: StringName) -> void:
	for i in view.deck.hand.size():
		if view.deck.hand[i].id == id:
			view.activate_card(i)
			return
	_expect(false, "%s is not in hand when the lesson asks for it" % id)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
