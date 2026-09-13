## Dev-only: boots the real game, walks it through every stop type on the route,
## asserts the run state actually changed, and writes PNGs of each screen.
##
## A screen swapped in this frame is not drawn until the next one, so a capture
## is always requested for the *following* tick. Grabbing straight after a swap
## silently photographs the screen you just replaced.
extends SceneTree

## Long enough for a dealt hand to finish sliding into place. At 30 every
## capture caught the cards mid-deal and the fan looked like a staircase.
const TICK_FRAMES := 70

var frames := 0
var main: Node
var stage := 0
var failures := 0
var _grab_next := ""
## The game opens on a splash now, so the walk has to get through the front end
## before there is a run to inspect. Kept as its own little machine rather than
## renumbering every stage below it.
var _boot_stage := 0
var _booted := false
## Carried across the turn, to prove the back nine inherits the run.
## The leaderboard has been seen at least once, so stepping past it silently is
## not the same as it never turning up.
var _saw_board := false
## And the workshop door was offered at least once, so declining it silently is
## not the same as it never appearing.
var _saw_door := false
var _turn_bag := 0
var _turn_purse := 0
## Bag size before the vice, so the walk can prove two clubs became one.
var _fusion_bag := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _grab(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = root.get_texture().get_image()
	image.save_png("user://" + file_name)


## Returns the condition so a caller can bail out rather than plough on into a
## screen that is not the one it expected and loop forever.
func _expect(condition: bool, what: String) -> bool:
	if condition:
		print("  ok: %s" % what)
	else:
		failures += 1
		print("  FAIL: %s" % what)
	return condition


## Force a particular kind of stop to be next, by rewriting the spec of a node
## that is currently reachable, then travelling to it.
func _visit(spec_id: StringName) -> void:
	var map: RunMap = main.map
	var options := map.available_ids()
	if options.is_empty():
		return
	var id: int = options[0]
	map.node_by_id(id).spec = MapGenerator.spec(spec_id)
	main._on_node_chosen(id)
	_decline_the_door()


## Travelling to a stop can land on the workshop offer instead of the stop
## itself, because the door is a roll. Declined here rather than a tick later in
## _process: the stage that calls _visit asserts on the screen in the very same
## breath, so a guard further up only ever catches it after the assertion has
## already failed. The fusion is driven deliberately at the end of the walk.
func _decline_the_door() -> void:
	if main._current_screen == null or not main._current_screen.has_meta(&"workshop"):
		return
	if not _saw_door:
		_saw_door = true
		_expect(true, "an ordinary stop can offer the workshop")
	main._current_screen.option_chosen.emit(0)


## Walk the route forward to the final column and return its node.
func _boss_node() -> int:
	var map: RunMap = main.map
	for guard in 20:
		var options := map.available_ids()
		if options.is_empty():
			return -1
		var id: int = options[0]
		if map.is_final(id):
			return id
		map.travel_to(id)
	return -1


func _upgraded_count() -> int:
	var count := 0
	for card in main.deck.cards:
		if card.upgraded:
			count += 1
	return count


## Splash, title, a look at the settings, then a nine. Every step asserted: this
## walk once reported ALL CHECKS PASSED against a game that had never started,
## because the errors from poking a null run are not fatal and every stage
## advanced regardless. A harness that cannot fail is worse than no harness.
func _boot() -> void:
	match _boot_stage:
		0:
			print("=== front end ===")
			if _expect(main._current_screen is SplashScreen,
					"the game opens on a splash"):
				_grab_next = "m9_splash.png"
		1:
			# Clicked rather than signalled, so the mouse path is the thing under
			# test. A Control swallows mouse events into _gui_input before
			# _unhandled_input ever sees them, and this splash once listened only
			# for keys -- on a game played entirely with the mouse.
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			main._current_screen._gui_input(click)
		2:
			if _expect(main._current_screen is TitleScreen,
					"clicking the splash leads to the title"):
				_grab_next = "m9_title.png"
		3:
			main._current_screen.tour_opened.emit()
		4:
			# The ladder is the only part of the game that outlives a run, so the
			# walk goes through it rather than round it.
			if _expect(main._current_screen is TourScreen,
					"the title opens the ladder"):
				_grab_next = "m14_ladder.png"
			_expect(TourLibrary.all().size() >= 3, "the ladder has rungs on it")
			_expect(TourLibrary.is_unlocked(TourLibrary.opening()),
				"the opening rung is always playable")
		5:
			main._current_screen.closed.emit()
			_expect(main._current_screen is TitleScreen,
				"the ladder returns to the title")
		6:
			main._current_screen.settings_opened.emit()
		7:
			if _expect(main._current_screen is SettingsScreen,
					"the title opens settings"):
				_grab_next = "m9_settings.png"
		8:
			main._current_screen.closed.emit()
			_expect(main._current_screen is TitleScreen, "settings returns to the title")
		9:
			main._current_screen.round_chosen.emit(MapGenerator.HOLES_PER_NINE)
			# Everything after this point reads main.run and main.map, so if the
			# round did not start there is nothing to test and saying so is the
			# only honest outcome.
			if not _expect(main.run != null and main.map != null,
					"choosing a round starts it"):
				print("")
				print("%d FLOW CHECK(S) FAILED" % failures)
				quit(1)
				return
			_expect(main.run.cut_line == RunState.DEFAULT_CUT,
				"a nine plays to the standard cut")
			_booted = true
			print("")
			print("=== stops ===")
	_boot_stage += 1


func _process(_delta: float) -> bool:
	frames += 1
	if frames < TICK_FRAMES:
		return false
	frames = 0

	if _grab_next != "":
		_grab(_grab_next)
		_grab_next = ""

	if not _booted:
		_boot()
		return false

	# The workshop door can now open at a pro shop, a range or a clubhouse, and
	# whether it does is a roll. The walk declines it and carries on to the stop
	# it actually came for; the fusion itself is driven deliberately at the end.
	if main._current_screen != null and main._current_screen.has_meta(&"workshop"):
		_decline_the_door()
		return false

	# The board appears after every hole, before the prize. Stepped past here
	# rather than by renumbering every stage below -- but noted the first time,
	# so a board that stopped appearing could not hide behind this.
	if main._current_screen is LeaderboardScreen:
		if not _saw_board:
			_saw_board = true
			_expect(true, "a finished hole shows the leaderboard")
			_grab_next = "m12_leaderboard.png"
			return false
		main._current_screen.continued.emit()
		return false

	match stage:
		0:
			_grab("m6_map.png")
			_visit(&"hole")
		1:
			var purse: int = main.run.winnings
			main._on_hole_finished(4, 4)
			_expect(main.run.winnings > purse, "a finished hole pays winnings")
			_expect(main._current_screen is LeaderboardScreen,
				"a finished hole goes to the board first")
		2:
			_expect(main._current_screen is CardPickerScreen,
				"the board leads on to the prize")
			var bag: int = main.deck.total_cards()
			main._current_screen.card_chosen.emit(0)
			_expect(main.deck.total_cards() == bag + 1, "taking a prize grows the bag")
			_visit(&"pro_shop")
			if _expect(main._current_screen is ShopScreen, "the pro shop opens a shop"):
				_grab_next = "m6_shop.png"
		3:
			# Top the purse up so both kinds of purchase can be exercised.
			main.run.add_winnings(500)
			main._current_screen.set_winnings(main.run.winnings)
			var purse: int = main.run.winnings
			var bag: int = main.deck.total_cards()
			main._current_screen.card_bought.emit(0)
			_expect(main.run.winnings < purse, "buying a card costs winnings")
			_expect(main.deck.total_cards() == bag + 1, "buying a card grows the bag")
			var relics: int = main.run.relics.size()
			main._current_screen.relic_bought.emit(0)
			_expect(main.run.relics.size() == relics + 1, "buying equipment carries it")
			main._current_screen.left.emit()
			_visit(&"driving_range")
			if _expect(main._current_screen is CardPickerScreen, "the range opens a picker"):
				_grab_next = "m6_range.png"
		4:
			var before := _upgraded_count()
			for i in main.deck.cards.size():
				if main.deck.cards[i].can_upgrade():
					main._current_screen.card_chosen.emit(i)
					break
			_expect(_upgraded_count() == before + 1, "the range upgrades a club")
			_visit(&"clubhouse")
			if _expect(main._current_screen is CardPickerScreen,
					"the clubhouse opens a picker"):
				_grab_next = "m6_clubhouse.png"
		5:
			var bag: int = main.deck.total_cards()
			main._current_screen.card_chosen.emit(0)
			_expect(main.deck.total_cards() == bag - 1, "the clubhouse thins the bag")
			var purse: int = main.run.winnings
			_visit(&"lost_and_found")
			_expect(main.run.winnings > purse, "lost and found pays out")
			_grab_next = "m6_found.png"
		6:
			main._current_screen.continued.emit()
			_visit(&"halfway_house")
			if _expect(main._current_screen is NoticeScreen,
					"the halfway house offers a choice"):
				_grab_next = "m6_halfway.png"
		7:
			# Resting claws back strokes you have dropped and stops at level: it
			# is a way back into a run, never a way to improve a good one. Both
			# halves are asserted, because the interesting half is the one that
			# does nothing -- that is the rule that stopped dodging golf paying.
			var before: int = main.run.score_to_par()
			var strokes: int = main.run.total_strokes
			main._current_screen.option_chosen.emit(0)
			if before > 0:
				_expect(main.run.total_strokes < strokes,
					"resting should claw back strokes when you are over par")
			else:
				_expect(main.run.total_strokes == strokes,
					"resting at %s should take nothing off the card"
						% main.run.score_text())
			_expect(main.run.score_to_par() >= mini(before, 0),
				"resting should never improve a card that is already level")
			_visit(&"caddie")
			_expect(main._current_screen is CardPickerScreen, "the caddie offers advice")
		8:
			main._current_screen.skipped.emit()
			_expect(main._current_screen is MapScreen, "declining returns to the route")
			_visit(&"event")
			if _expect(main._current_screen is NoticeScreen, "an event stop opens a scene"):
				_grab_next = "m7_event.png"
		9:
			var before: int = main.run.winnings + main.deck.total_cards()
			main._current_screen.option_chosen.emit(0)
			_expect(main._current_screen is NoticeScreen, "an event choice has a result")
			_grab_next = "m7_event_result.png"
		10:
			main._current_screen.continued.emit()
			# The closing hole plays under its own rules.
			var boss := _boss_node()
			if _expect(boss >= 0, "the route ends at a closing hole"):
				main._on_node_chosen(boss)
				_expect(main._current_screen is HoleScreen, "the closer opens a hole")
				var view: HoleView = main._current_screen.get_node("HoleView")
				_expect(view.rule_set != null, "the closing hole has special rules")
				if view.rule_set != null:
					print("  closing hole rules: %s" % view.rule_set.display_name)
				_grab_next = "m7_boss.png"
		11:
			# An eighteen is two nines with a turn between them, and until now
			# nothing had ever walked through that turn -- the walk above only
			# ever plays a nine. A crash at the halfway point of the longer mode
			# would be the worst possible place to find a bug.
			print("")
			print("=== the turn ===")
			main.start_run(MapGenerator.HOLES_PER_NINE * 2)
			_expect(main.run.cut_line == RunState.DEFAULT_CUT * 2,
				"an eighteen should play to twice the cut")
			_expect(main._nines_left == 2, "an eighteen should be two nines")
			_turn_bag = main.deck.total_cards()
			_turn_purse = main.run.winnings
			_visit(&"hole")
			_expect(main._current_screen is HoleScreen, "the back nine run opens on a hole")
		12:
			# One hole at a time from here. Finishing a hole now goes board, then
			# prize, then wherever the route leads -- three screen changes, and
			# packing them into one stage meant the walk was talking to whichever
			# screen happened to be up rather than the one it named.
			main._on_hole_finished(5, 4)
		13:
			if main._current_screen is CardPickerScreen:
				main._current_screen.skipped.emit()
		14:
			var closer := _boss_node()
			if _expect(closer >= 0, "the front nine ends somewhere"):
				main._on_node_chosen(closer)
		15:
			_expect(main._current_screen is HoleScreen, "the closing hole opens")
			main._on_hole_finished(4, 4)
		16:
			if main._current_screen is CardPickerScreen:
				main._current_screen.skipped.emit()
		17:
			if _expect(main._current_screen is NoticeScreen,
					"finishing the front nine reaches the turn"):
				_grab_next = "m11_turn.png"
			_expect(main._nines_left == 1, "one nine should be left after the turn")
		18:
			main._current_screen.continued.emit()
			_expect(main._current_screen is MapScreen, "the turn leads to a new route")
			# The whole point of a turn: you carry everything across it.
			_expect(main.deck.total_cards() >= _turn_bag,
				"the bag should survive the turn")
			_expect(main.run.winnings >= _turn_purse - 1,
				"winnings should survive the turn")
			_expect(main.run.holes_played > 0, "the card should survive the turn")
			print("  carried %d cards and %d winnings onto the back nine"
				% [main.deck.total_cards(), main.run.winnings])
		19:
			# The workshop. In play it is behind a roll at one of two stops, so
			# the walk opens the door itself rather than hoping for it -- what is
			# under test is the two-picker flow and the reveal, not the dice.
			print("")
			print("=== the workshop ===")
			_expect(ClubFusion.is_available(main.deck.cards),
				"a bag with a wood and an iron in it can fuse")
			_fusion_bag = main.deck.total_cards()
			main._choose_fusion_wood(func() -> void: main._after_stop())
			_expect(main._current_screen is CardPickerScreen,
				"the vice asks for something long")
		20:
			main._current_screen.card_chosen.emit(0)
			_expect(main._current_screen is CardPickerScreen,
				"the grinder asks for something honest")
		21:
			main._current_screen.card_chosen.emit(0)
			if _expect(main._current_screen is FusionScreen,
					"two clubs going in produces a reveal"):
				_grab_next = "m13_driron.png"
			_expect(main.deck.total_cards() == _fusion_bag - 1,
				"two clubs came out as one")
			_expect(ClubFusion.already_fused(main.deck.cards),
				"and the one is a Driron")
		22:
			main._current_screen.continued.emit()
			_expect(main._current_screen is MapScreen,
				"the reveal hands you back to the route")
		23:
			print("")
			print("ALL FLOW CHECKS PASSED" if failures == 0
				else "%d FLOW CHECK(S) FAILED" % failures)
			print("bag %d cards, %d winnings, %d equipment" % [
				main.deck.total_cards(), main.run.winnings, main.run.relics.size()])
			return true

	stage += 1
	return false
