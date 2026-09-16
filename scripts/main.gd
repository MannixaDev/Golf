## The run layer. Owns everything that outlives a single hole -- the deck, the
## route, the card, the purse and the equipment -- and swaps screens in and out.
##
## Screens know nothing about each other. Each one is handed what it needs, does
## its job, and reports back with a signal.
extends Node

const MAP_SCREEN := preload("res://scenes/run/map_screen.tscn")
const HOLE_SCREEN := preload("res://scenes/run/hole_screen.tscn")
const NOTICE_SCREEN := preload("res://scenes/run/notice_screen.tscn")
const PICKER_SCREEN := preload("res://scenes/ui/card_picker_screen.tscn")
const SHOP_SCREEN := preload("res://scenes/ui/shop_screen.tscn")
const SPLASH_SCREEN := preload("res://scenes/ui/splash_screen.tscn")
const TITLE_SCREEN := preload("res://scenes/ui/title_screen.tscn")
const SETTINGS_SCREEN := preload("res://scenes/ui/settings_screen.tscn")
const TOUR_SCREEN := preload("res://scenes/ui/tour_screen.tscn")
const SCORECARD_SCREEN := preload("res://scenes/ui/scorecard_screen.tscn")
const LEADERBOARD_SCREEN := preload("res://scenes/ui/leaderboard_screen.tscn")
const FUSION_SCREEN := preload("res://scenes/ui/fusion_screen.tscn")

## Cards on the shop shelf, and what they cost by rarity.
const SHOP_CARDS := 3
const SHOP_RELICS := 2
const CARD_PRICE := {
	CardData.Rarity.COMMON: 38,
	CardData.Rarity.UNCOMMON: 62,
	CardData.Rarity.RARE: 92,
}
const REMOVAL_PRICE := 45
## What the pro asks for a putter when you have none. Deliberately cheap: this
## is a way out of an unrecoverable bag, not a purchase to agonise over.
const PUTTER_RESCUE_PRICE := 25
## What the halfway house takes off your card -- but only while you are over par.
##
## It used to heal unconditionally, which quietly made resting the best way to
## *improve* a good round rather than to rescue a bad one. Score against par is
## both this game's score and its health bar, so anything that heals also flatters
## the card unless it is capped at level. Now it is a way back, not a way ahead.
const REST_STROKES := 2
## Fading out is kept shorter than fading in: waiting to leave a screen feels
## like lag, arriving at one does not.
const FADE_OUT := 0.13
const FADE_IN := 0.20

@export var starting_deck: DeckList

@onready var _screens: Node = $Screens
@onready var _fade: ColorRect = %Fade

var _fade_tween: Tween

var deck: Deck
var run: RunState
var map: RunMap
var rng := RandomNumberGenerator.new()

var _current_screen: Node = null
var _pending_node: MapNode = null
var _hole_number: int = 0
## Holes in the round the player picked, and how many nines are left to walk.
## An eighteen is two nines rather than one enormous map: the route has to stay
## readable, and turning at the halfway point is what golf actually does.
var _round_holes: int = MapGenerator.HOLES_PER_NINE
var _nines_left: int = 1
var _nine_index: int = 0
## Stock is rolled once per shop visit and held, so leaving something and coming
## back to it is a decision rather than a reroll.
var _shop_cards: Array = []
var _shop_prices: Array = []
var _shop_relics: Array[RelicSpec] = []
## What the equipment made of this shop, rolled once when the player arrives.
var _stock: ShopStock = ShopStock.new()
## Free removals taken on this visit, so a relic that grants them cannot be
## milked by walking in and out of the picker.
var _removals_used: int = 0
## Sold state, kept out here because the removal picker tears the shop screen
## down and builds a new one on the way back.
var _shop_card_sold: Array[bool] = []
var _shop_relic_sold: Array[bool] = []
## Events already seen this run, so one run does not tell the same joke twice.
var _events_seen: Array = []
## The rung being played. Every round has one; it defaults to the gentle one.
var _tour: TourSpec = TourLibrary.opening()
## Workbench stops walked into this run that did not open the door. Carried so
## the odds climb rather than resetting, which is what stops a run from rolling
## badly three times and never showing the workshop at all.
var _workshop_misses: int = 0


## Watched at the very top of the tree, so a finger anywhere -- a menu, a card,
## the course -- is enough to know what kind of device this is. _input rather
## than _unhandled_input: a tap consumed by a button still tells us the truth.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		Settings.note_touch()


func _ready() -> void:
	Settings.ensure_loaded()
	Settings.apply_window()
	_show_splash()


# --- Front end ------------------------------------------------------------

func _show_splash() -> void:
	var screen: SplashScreen = SPLASH_SCREEN.instantiate()
	_swap_screen(screen)
	screen.continued.connect(_show_title)


func _show_title() -> void:
	var screen: TitleScreen = TITLE_SCREEN.instantiate()
	_swap_screen(screen)
	# The quick buttons play whatever rung you last earned, so the ladder never
	# stands between you and a round you just want to play.
	screen.round_chosen.connect(func(holes: int) -> void:
		start_run(holes, TourLibrary.by_rung(TourLibrary.unlocked_rung)))
	screen.lesson_opened.connect(_play_lesson)
	screen.tour_opened.connect(_show_tours)
	screen.settings_opened.connect(_show_settings)


## The guided hole.
##
## Deliberately outside the run machinery: no RunState, no leaderboard, no cut,
## no map. It is one hole with a fixed seed and a six card bag, and somebody
## talking over the top of it. Nothing that happens here is recorded, so a player
## can take the lesson twice without it costing them a career.
func _play_lesson() -> void:
	var lesson: TutorialLesson = load("res://resources/tutorial/first_lesson.tres")
	var hole := HoleGenerator.generate(
		TutorialDirector.HOLE_SEED, TutorialDirector.HOLE_TIER, 1)
	var bag: DeckList = load("res://resources/decks/tutorial_deck.tres")

	var screen: HoleScreen = HOLE_SCREEN.instantiate()
	screen.setup(hole, Deck.new(bag.build()))
	_swap_screen(screen)

	var director := TutorialDirector.new()
	screen.add_child(director)
	director.setup(screen.get_node("HoleView"), lesson.playable_steps())
	director.prompt_changed.connect(screen.set_lesson)
	director.finished.connect(func() -> void: Settings.note_learned())
	# However the hole ends -- holed out, picked up, or given up on -- the lesson
	# hands you back to the menu rather than into a run you did not ask for.
	screen.finished.connect(func(_strokes: int, _par: int) -> void:
		Settings.note_learned()
		_show_title())
	screen.begin()


func _show_tours() -> void:
	var screen: TourScreen = TOUR_SCREEN.instantiate()
	_swap_screen(screen)
	screen.tour_chosen.connect(func(tour: TourSpec, holes: int) -> void:
		start_run(holes, tour))
	screen.closed.connect(_show_title)


func _show_settings() -> void:
	var screen: SettingsScreen = SETTINGS_SCREEN.instantiate()
	_swap_screen(screen)
	screen.closed.connect(_show_title)


# --- Run lifecycle --------------------------------------------------------

func start_run(holes: int = MapGenerator.HOLES_PER_NINE,
		tour: TourSpec = null) -> void:
	rng.randomize()
	_tour = tour if tour != null else TourLibrary.opening()
	deck = _build_deck()
	run = RunState.new()
	_round_holes = maxi(holes, MapGenerator.HOLES_PER_NINE)
	run.round_holes = _round_holes
	run.tour = _tour
	run.leaderboard = Leaderboard.new(rng.randi(), _tour.field_skill_delta)
	# A longer round has to allow a longer card, or an eighteen is simply a nine
	# you are twice as likely to be thrown off.
	run.cut_line = RunState.DEFAULT_CUT * _round_holes / MapGenerator.HOLES_PER_NINE
	_nines_left = maxi(1, _round_holes / MapGenerator.HOLES_PER_NINE)
	_nine_index = 0
	_hole_number = 0
	_pending_node = null
	_events_seen.clear()
	_workshop_misses = 0
	_begin_nine()


## Lay out the next nine and walk onto it. The deck, the card, the purse and the
## equipment all carry over -- only the route is new.
func _begin_nine() -> void:
	map = MapGenerator.generate(rng.randi(), MapGenerator.HOLES_PER_NINE)
	_pending_node = null
	_show_map()


func _build_deck() -> Deck:
	if starting_deck == null:
		push_error("Main: no starting DeckList assigned.")
		return Deck.new()
	return Deck.new(starting_deck.build())


# --- Screens --------------------------------------------------------------

## Fade down, change the screen underneath, fade back up.
##
## This used to swap first and only fade in, which meant every transition began
## with the old screen vanishing on a frame -- the swap itself was still a cut,
## and the fade only softened the arrival. Callers do not have to care: they
## still call this once and carry on, and the screen changes when the veil is
## down.
func _swap_screen(screen: Node) -> void:
	var previous := _current_screen
	_current_screen = screen

	# Added straight away, and hidden. Every caller configures the screen on the
	# line after this one, and a node outside the tree has not run _ready, so
	# deferring the add would hand them a screen with every @onready still null.
	screen.visible = false
	_screens.add_child(screen)

	if _fade == null:
		_reveal(screen, previous)
		return

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()

	var down := _fade_tween.tween_property(_fade, "color:a", 1.0, FADE_OUT)
	down.set_trans(Tween.TRANS_CUBIC)
	down.set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_reveal.bind(screen, previous))
	var up := _fade_tween.tween_property(_fade, "color:a", 0.0, FADE_IN)
	up.set_trans(Tween.TRANS_CUBIC)
	up.set_ease(Tween.EASE_OUT)


## Behind the veil: drop the old screen and uncover the new one.
func _reveal(screen: Node, previous: Node) -> void:
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	if is_instance_valid(screen):
		screen.visible = true


## A nine is just "the nine"; an eighteen turns at the halfway point and the
## header should say which half you are walking.
func _course_name() -> String:
	if _round_holes <= MapGenerator.HOLES_PER_NINE:
		return "THE NINE"
	return "THE FRONT NINE" if _nine_index == 0 else "THE BACK NINE"


func _show_map() -> void:
	var screen: MapScreen = MAP_SCREEN.instantiate()
	_swap_screen(screen)
	screen.course_name = _course_name()
	screen.setup(map, run, deck)
	screen.node_chosen.connect(_on_node_chosen)


func _on_node_chosen(id: int) -> void:
	var node := map.node_by_id(id)
	if node == null or not map.travel_to(id):
		return
	_pending_node = node

	if node.plays_hole():
		_play_hole(node)
	else:
		_visit_stop(node)


func _play_hole(node: MapNode) -> void:
	_hole_number += 1

	# Elite and closing holes play under special rules, which get to reshape the
	# hole before it is generated as well as behave during it.
	# The tour leans on every hole, so a stop that was ordinary on the opening
	# rung is a tough one further up without the route having to change shape.
	var difficulty := node.difficulty() + _tour.difficulty_delta
	var rules := CourseRuleLibrary.pick(difficulty, node.hole_seed)
	var hole := HoleGenerator.generate(
		node.hole_seed, difficulty, _hole_number, rules)

	var screen: HoleScreen = HOLE_SCREEN.instantiate()
	screen.setup(hole, deck)
	screen.setup_run(run.relics, run.score_to_par())
	screen.setup_rules(rules, node.hole_seed)
	_swap_screen(screen)
	screen.finished.connect(_on_hole_finished)
	screen.begin()


func _on_hole_finished(strokes: int, par: int) -> void:
	run.record_hole(strokes, par)

	if run.finished:
		_show_run_end(false)
		return

	var base := _pending_node.difficulty() if _pending_node != null else 1
	var difficulty := base + _tour.difficulty_delta
	var reward := HoleReward.new(strokes, par,
		roundi(RewardTable.winnings_for(strokes, par, difficulty)
			* _tour.winnings_multiplier))
	_apply_scoring_relics(reward)
	run.add_winnings(reward.winnings)
	if reward.strokes_back > 0:
		# Through rest(), so it is capped at level and reaches the board, rather
		# than being a second way to edit the card that behaves differently.
		run.rest(reward.strokes_back)
	# The board first: a good hole is four names going past you, and that lands
	# better before the prize than after it.
	_show_leaderboard(func() -> void:
		_offer_card_reward(strokes, par, reward, difficulty))


## Let the equipment say what the hole was worth. Runs after the score is known
## and before anything is banked.
func _apply_scoring_relics(reward: HoleReward) -> void:
	if run.relics.is_empty():
		return
	var ctx := RelicContext.new()
	ctx.strokes_taken = reward.strokes
	ctx.par = reward.par
	ctx.run_score_to_par = run.score_to_par()
	for relic in run.relics:
		for effect in relic.effects:
			if effect != null:
				effect.on_hole_scored(reward, ctx)


# --- Rewards --------------------------------------------------------------

func _offer_card_reward(strokes: int, par: int, reward: HoleReward,
		difficulty: int) -> void:
	var offer := RewardTable.card_offer(rng, difficulty)
	if offer.is_empty():
		_after_stop()
		return

	# Equipment that fired says so, or a relic that pays you is a relic you
	# never notice you are carrying.
	var line := "%d in winnings. Take a card for the bag." % reward.winnings
	if not reward.notes.is_empty():
		line = "%d in winnings (%s). Take a card for the bag." % [
			reward.winnings, "  ".join(reward.notes)]

	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards(
		RunState.score_name(strokes, par),
		line,
		offer,
		"Take nothing")
	screen.card_chosen.connect(func(index: int) -> void:
		deck.add_card(offer[index])
		_after_stop())
	screen.skipped.connect(_after_stop)


# --- Stops ----------------------------------------------------------------

func _visit_stop(node: MapNode) -> void:
	match node.spec.id:
		&"pro_shop":
			_maybe_workshop(node, "Browse the shelves  ·  the usual",
				func() -> void: _open_shop())
		&"driving_range":
			_maybe_workshop(node, "Groove one club  ·  the usual",
				func() -> void: _open_upgrade(node))
		&"clubhouse":
			_maybe_workshop(node, "Leave one club at home  ·  the usual",
				func() -> void: _open_removal(node))
		&"lost_and_found":
			_open_lost_and_found(node)
		&"halfway_house":
			_open_halfway_house(node)
		&"caddie":
			_open_caddie(node)
		&"event":
			_open_event(node)
		_:
			_show_placeholder(node)


func _open_upgrade(node: MapNode) -> void:
	var cards := deck.cards
	var disabled: Array = []
	var any := false
	for card in cards:
		var locked := not card.can_upgrade()
		disabled.append(locked)
		any = any or not locked

	if not any:
		_show_notice(node, "Every club in the bag is already grooved.")
		return

	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards(node.display_name(),
		"Groove one club until it is genuinely better.",
		cards, "Hit a few and leave", disabled)
	screen.card_chosen.connect(func(index: int) -> void:
		cards[index].upgrade()
		_after_stop())
	screen.skipped.connect(_after_stop)


func _open_removal(node: MapNode) -> void:
	if deck.total_cards() <= 1:
		_show_notice(node, "There is barely a bag left to thin out.")
		return

	var cards := deck.cards
	# Your last putter is greyed out rather than merely discouraged. Choosing to
	# go without one is not a strategy the game supports, because it cannot sell
	# you a replacement.
	var locked: Array = []
	for card in cards:
		locked.append(deck.is_last_putter(card))

	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards(node.display_name(),
		"Leave one club at home. You will not miss it.",
		cards, "Keep the lot", locked)
	screen.card_chosen.connect(func(index: int) -> void:
		deck.remove_card(cards[index])
		_after_stop())
	screen.skipped.connect(_after_stop)


# --- The workshop ---------------------------------------------------------

## Sometimes there is a second door.
##
## It hangs off the two stops where you are already stood there with a club in
## your hands, and nothing on the map ever marks it: the whole appeal is walking
## into an ordinary clubhouse and finding it open. Turning it down costs you
## nothing, so the stop is never worse for having offered.
func _maybe_workshop(node: MapNode, usual_label: String, usual: Callable) -> void:
	if not ClubFusion.is_available(deck.cards):
		usual.call()
		return
	if rng.randf() >= ClubFusion.chance(_workshop_misses):
		# Locked today. The next one is likelier, and the one after that is
		# near certain: a run that could make a Driron should get to try.
		_workshop_misses += 1
		usual.call()
		return
	_workshop_misses = 0
	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	# Marked so a harness can recognise this particular notice and step past it.
	# The walk through the stops cannot predict whether the door is open, and
	# without a marker it was asserting against whichever screen happened to be
	# up -- the same false-pass this project has already been bitten by once.
	screen.set_meta(&"workshop", true)
	_swap_screen(screen)
	screen.show_choice(node.display_name(),
		"Nobody is behind the counter. Behind it, though, is a door you have "
		+ "never seen open, and through it a bench, a vice, and a grinder that "
		+ "is still warm.",
		[usual_label,
		 "Take two clubs through the door  ·  see what comes back"],
		node.spec.colour)
	screen.option_chosen.connect(func(index: int) -> void:
		if index == 0:
			usual.call()
		else:
			_choose_fusion_wood(usual))


## Two pickers in sequence: the long half, then the honest one. Both are shown
## as ordinary card choices, so what you are giving up is laid out in front of
## you rather than described in a sentence. Backing out of either one drops you
## into what the stop was always going to be.
func _choose_fusion_wood(usual: Callable) -> void:
	var woods := ClubFusion.woods(deck.cards)
	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards("The vice",
		"Something long goes in first. It is not coming out again.",
		woods, "Think better of it")
	screen.card_chosen.connect(func(index: int) -> void:
		_choose_fusion_iron(woods[index], usual))
	screen.skipped.connect(func() -> void: usual.call())


func _choose_fusion_iron(wood: CardData, usual: Callable) -> void:
	var irons := ClubFusion.irons(deck.cards)
	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards("The grinder",
		"And something honest to weld it to. %s is already in pieces."
			% wood.title(),
		irons, "Walk away")
	screen.card_chosen.connect(func(index: int) -> void:
		_finish_fusion(wood, irons[index]))
	screen.skipped.connect(func() -> void: usual.call())


func _finish_fusion(wood: CardData, iron: CardData) -> void:
	var made := ClubFusion.fuse(wood, iron)
	if made == null:
		_after_stop()
		return
	deck.remove_card(wood)
	deck.remove_card(iron)
	deck.add_card(made)

	var screen: FusionScreen = FUSION_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_fusion(made, wood, iron)
	screen.continued.connect(_after_stop)


func _open_lost_and_found(node: MapNode) -> void:
	var found := rng.randi_range(28, 52)
	run.add_winnings(found)

	# Occasionally somebody has left something rather better behind.
	var relic: RelicSpec = null
	if rng.randf() < 0.4:
		relic = RelicLibrary.offer(rng, run.relics)
		if relic != null:
			run.add_relic(relic)

	var body := "You pocket %d in loose change." % found
	if relic != null:
		body += "  Tucked underneath: %s. %s" % [relic.display_name, relic.effect_text()]
	_show_notice(node, body)


func _open_halfway_house(node: MapNode) -> void:
	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_choice(node.display_name(),
		node.spec.description,
		[_rest_label(),
		 "Hit balls out the back  ·  groove one club"],
		node.spec.colour)
	screen.option_chosen.connect(func(index: int) -> void:
		if index == 0:
			run.rest(REST_STROKES)
			_after_stop()
		else:
			_open_upgrade(node))


## Said plainly, so the choice is never a trick. Resting claws back strokes you
## have actually dropped; playing well already is not something a bacon roll can
## improve on, and the label says so rather than letting you waste the stop.
func _rest_label() -> String:
	var recoverable := mini(REST_STROKES, maxi(run.score_to_par(), 0))
	if recoverable <= 0:
		return "Sit down and rethink  ·  nothing to claw back at %s" % run.score_text()
	return "Sit down and rethink  ·  take %d %s off your card" % [
		recoverable, "stroke" if recoverable == 1 else "strokes"]


func _open_caddie(node: MapNode) -> void:
	var offer := RewardTable.card_offer(rng, 2, 2)
	if offer.is_empty():
		_show_notice(node, "She has nothing for you today.")
		return

	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards(node.display_name(),
		"She has watched you play. Take her advice, or do not.",
		offer, "Thanks anyway")
	screen.card_chosen.connect(func(index: int) -> void:
		deck.add_card(offer[index])
		_after_stop())
	screen.skipped.connect(_after_stop)


# --- Events ---------------------------------------------------------------

func _open_event(node: MapNode) -> void:
	var event := EventLibrary.pick(rng, run.holes_played, _events_seen)
	if event == null:
		_show_notice(node, "Nothing happens. Somehow that is worse.")
		return
	_events_seen.append(event.id)

	var choices := event.available_outcomes(run.winnings)
	if choices.is_empty():
		_show_notice(node, event.body)
		return

	var labels: Array = []
	for outcome in choices:
		labels.append(outcome.label)

	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_choice(event.title, event.body, labels, event.colour)
	screen.option_chosen.connect(func(index: int) -> void:
		_resolve_outcome(event, choices[index]))


## Everything an event can do to a run, in one place, so writing a new event is
## writing prose and numbers rather than another branch in here.
func _resolve_outcome(event: EventSpec, outcome: EventOutcome) -> void:
	var notes: PackedStringArray = PackedStringArray()
	if outcome.result_text != "":
		notes.append(outcome.result_text)

	if outcome.winnings_delta != 0:
		run.add_winnings(outcome.winnings_delta)
		notes.append("%s %d in winnings." % [
			"Gained" if outcome.winnings_delta > 0 else "Lost",
			absi(outcome.winnings_delta)])

	if outcome.strokes_delta != 0:
		run.total_strokes = maxi(0, run.total_strokes + outcome.strokes_delta)
		run.changed.emit()
		notes.append("%+d on your card." % outcome.strokes_delta)

	if outcome.add_card_id != &"":
		var card := CardLibrary.copy(outcome.add_card_id)
		if card != null:
			deck.add_card(card)
			notes.append("%s goes in the bag." % card.title())

	if outcome.removes_random_card and deck.total_cards() > 1:
		# Anything but the last putter. Nothing in the game can sell you another
		# -- it is a starter card and the pools only hold commons and uncommons
		# -- so a random draw taking it ends the run four holes before it stops.
		var takeable: Array[CardData] = []
		for card in deck.cards:
			if not deck.is_last_putter(card):
				takeable.append(card)
		if not takeable.is_empty():
			var dropped: CardData = takeable[rng.randi_range(0, takeable.size() - 1)]
			deck.remove_card(dropped)
			notes.append("%s leaves the bag." % dropped.title())

	if outcome.upgrades_random_card:
		var upgradeable: Array[CardData] = []
		for card in deck.cards:
			if card.can_upgrade():
				upgradeable.append(card)
		if upgradeable.is_empty():
			notes.append("Nothing left in the bag to improve.")
		else:
			var picked: CardData = upgradeable[rng.randi_range(0, upgradeable.size() - 1)]
			picked.upgrade()
			notes.append("%s is now sharper." % picked.title())

	if outcome.grants_relic:
		var relic := RelicLibrary.offer(rng, run.relics)
		if relic == null:
			notes.append("You already own everything worth owning.")
		else:
			run.add_relic(relic)
			notes.append("%s: %s" % [relic.display_name, relic.effect_text()])

	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_notice(event.title, " ".join(notes), "", "Back to the route",
		event.colour)
	screen.continued.connect(_after_stop)


# --- Shop -----------------------------------------------------------------

## What the equipment has to say about the shelf, before anything is stocked.
##
## Mirrors _apply_scoring_relics: build a context, hand one mutable object round
## the bag, play by what comes back. A relic that widens the shelf and one that
## discounts it both apply.
func _shop_stock() -> ShopStock:
	var stock := ShopStock.new(SHOP_CARDS, SHOP_RELICS)
	if run.relics.is_empty():
		return stock.clamped()
	var ctx := RelicContext.new()
	ctx.run_score_to_par = run.score_to_par()
	for relic in run.relics:
		for effect in relic.effects:
			if effect != null:
				effect.modify_shop(stock, ctx)
	return stock.clamped()


## Arriving at the shop. Rolls the shelf once, for this visit.
func _open_shop() -> void:
	_stock = _shop_stock()
	_removals_used = 0
	_shop_cards = RewardTable.card_offer(rng, 2, _stock.card_slots,
		_stock.guaranteed_uncommons)
	# A bag with nothing to putt with cannot be rescued by the ordinary stock:
	# the putter is a starter card and the pools hold none. So the pro keeps one
	# under the counter, cheap, for exactly this. It is the only way back.
	if deck.putters() == 0:
		var spare := CardLibrary.copy(&"putter")
		if spare != null:
			_shop_cards.insert(0, spare)
	_shop_prices = []
	for card in _shop_cards:
		_shop_prices.append(_stock.price_of(int(CARD_PRICE.get(card.rarity, 45))))
	# Set after the discount and never through it: the putter under the counter
	# is a rescue rather than a purchase, and taking a quarter off a mercy is not
	# a thing anybody needs.
	if deck.putters() == 0 and not _shop_cards.is_empty():
		_shop_prices[0] = PUTTER_RESCUE_PRICE

	# Built as a typed array on purpose: concatenating a typed and an untyped
	# array yields an untyped one, which the library then refuses.
	_shop_relics.clear()
	for i in _stock.relic_slots:
		var already: Array[RelicSpec] = run.relics.duplicate()
		already.append_array(_shop_relics)
		var relic := RelicLibrary.offer(rng, already)
		if relic != null:
			_shop_relics.append(relic)

	_shop_card_sold.clear()
	_shop_card_sold.resize(_shop_cards.size())
	_shop_relic_sold.clear()
	_shop_relic_sold.resize(_shop_relics.size())
	_show_shop()


## Putting the rolled shelf on screen. Separate from rolling it because the
## removal picker leaves the shop and comes back, and coming back used to call
## _open_shop -- which restocked.
##
## That was a free reroll of the entire shelf, available as often as you liked:
## open the removal picker, change your mind, and every card and both pieces of
## equipment were different, with nothing spent. What is on the shelf is supposed
## to be the decision the shop poses, and it was not a decision at all.
func _show_shop() -> void:
	var screen: ShopScreen = SHOP_SCREEN.instantiate()
	_swap_screen(screen)
	var removal := _stock.removal_price(REMOVAL_PRICE, _removals_used)
	var relic_prices: Array = []
	for relic in _shop_relics:
		relic_prices.append(_stock.price_of(relic.price))
	screen.show_stock(_shop_cards, _shop_prices, _shop_relics, relic_prices,
		removal, run.winnings)
	# What was already bought stays bought across the trip to the picker.
	for i in _shop_card_sold.size():
		if _shop_card_sold[i]:
			screen.mark_card_sold(i)
	for i in _shop_relic_sold.size():
		if _shop_relic_sold[i]:
			screen.mark_relic_sold(i)

	screen.card_bought.connect(func(index: int) -> void:
		if _shop_card_sold[index]:
			return
		if run.spend(int(_shop_prices[index])):
			deck.add_card(_shop_cards[index])
			_shop_card_sold[index] = true
			screen.mark_card_sold(index)
			screen.set_winnings(run.winnings))

	screen.relic_bought.connect(func(index: int) -> void:
		if _shop_relic_sold[index]:
			return
		var relic: RelicSpec = _shop_relics[index]
		if run.spend(_stock.price_of(relic.price)):
			run.add_relic(relic)
			_shop_relic_sold[index] = true
			screen.mark_relic_sold(index)
			screen.set_winnings(run.winnings))

	screen.removal_bought.connect(func() -> void:
		if removal <= 0 or run.can_afford(removal):
			_open_paid_removal(removal))

	screen.left.connect(_after_stop)


func _open_paid_removal(price: int) -> void:
	var cards := deck.cards
	var screen: CardPickerScreen = PICKER_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_cards("Leave a club at home",
		"Free. Choose carefully." if price <= 0
			else "Costs %d. Choose carefully." % price,
		cards, "Changed my mind")
	screen.card_chosen.connect(func(index: int) -> void:
		if price <= 0 or run.spend(price):
			deck.remove_card(cards[index])
			if price <= 0:
				_removals_used += 1
		_show_shop())
	screen.skipped.connect(_show_shop)




# --- Plumbing -------------------------------------------------------------

func _show_notice(node: MapNode, body: String) -> void:
	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_notice(node.display_name(), body, "", "Back to the route",
		node.spec.colour)
	screen.continued.connect(_after_stop)


func _show_placeholder(node: MapNode) -> void:
	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_placeholder(node)
	screen.continued.connect(_after_stop)


## Where every stop leads: the end of the run, or back to the route.
func _after_stop() -> void:
	if run.finished or run.score_to_par() > run.cut_line:
		_show_run_end(false)
		return
	if _pending_node != null and map.is_final(_pending_node.id):
		_nines_left -= 1
		if _nines_left > 0:
			_nine_index += 1
			_show_turn()
			return
		run.finish_run(true)
		_show_run_end(true)
		return
	_show_map()


## The turn. Half a round in, with the card you have built, before the back nine
## is laid out in front of you.
func _show_turn() -> void:
	var screen: NoticeScreen = NOTICE_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_notice(
		"The turn",
		"Front nine done. %s" % run.summary(),
		"Same bag, same card, new nine. %d to spare against the cut."
			% run.strokes_remaining(),
		"Walk to the tenth tee",
		Color(0.561, 0.8, 0.42))
	screen.continued.connect(_begin_nine)


func _show_leaderboard(after: Callable) -> void:
	var screen: LeaderboardScreen = LEADERBOARD_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_board(run.leaderboard, run.holes_played, _round_holes,
		run.cut_hole(), run.cut_place())
	screen.continued.connect(after)


func _show_run_end(won: bool) -> void:
	var place := run.leaderboard.player_place() if run.leaderboard != null else 0
	var opened := TourLibrary.record_result(_tour, place, won)
	var next := TourLibrary.by_rung(_tour.rung + 1)
	if not opened or next == null or next.rung != _tour.rung + 1:
		next = null

	# The card rather than a sentence. A round of golf ends with somebody
	# handing you one, and the ladder is what finally made the ending matter.
	var screen: ScorecardScreen = SCORECARD_SCREEN.instantiate()
	_swap_screen(screen)
	screen.show_card(run, _tour, won, next)
	screen.continued.connect(_show_title)
