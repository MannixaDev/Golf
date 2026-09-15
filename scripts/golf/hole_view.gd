## Orchestrates one playable hole: owns the rules (hands, strokes, penalties,
## holing out) and wires the aim controller to the ball.
##
## It knows nothing about the UI. Everything the HUD needs is published as a
## signal. It does not own the deck either -- the run layer injects one, so the
## same deck persists across holes later without this scene changing.
class_name HoleView
extends Node2D

signal hole_started(hole: HoleData)
signal strokes_changed(strokes: int)
signal distance_changed(yards_to_pin: float)
signal power_changed(power_pct: float)
## How high the selected shot would fly at the current swing, and whether that
## is under whatever is growing overhead. Published while the player is still
## deciding, because after the shot the number is only an excuse.
signal apex_changed(yards: float, blocked: bool)
## Passed straight through from the aim controller so the meter can draw itself.
signal swing_changed(phase: int, power: float, marker: float, band: float)
signal status_message(text: String)
signal hole_completed(strokes: int, par: int, holed: bool)

## `playable` is one bool per card. HoleView owns that judgement so the hand can
## never show a card as available that activate_card would then refuse.
signal hand_changed(hand: Array, selected: int, playable: Array,
		combining: Array)
signal piles_changed(draw_count: int, discard_count: int)
signal focus_changed(focus: int, focus_max: int)
## Names of the techniques currently attached to the next stroke.
signal modifiers_changed(names: Array, combinations: PackedStringArray)
signal lie_changed(surface: SurfaceType)
## Which way the green falls under the ball, and the read in words. Zero length
## anywhere but the putting surface.
signal slope_changed(fall: Vector2, note: String)
## The weather turned or the course was rearranged; the readouts need refreshing.
signal conditions_changed(hole: HoleData)
## The special rules this hole is played under, announced before the first stroke.
signal rules_announced(rule_set: CourseRuleSet)
## Whether the staged stroke can be worked either way, and which way it is set
## to. Almost always (false, 0): only a club built to do it offers the choice.
signal shape_changed(available: bool, shape: int, degrees: float)

@export var hole: HoleData
## Clubs held. What is actually dealt is `_bag.club_hand`: this, after the
## equipment and the course rules have had their say.
@export var club_hand: int = 4
## Techniques held, likewise. Kept at focus minus one, which is exactly how many
## you can afford to play once the shot card has taken its focus.
@export var extra_hand: int = 2
## If true, unplayed cards are binned after every shot. Off by default: a hole
## only lasts a few strokes, so burning five cards a stroke cycled the whole deck
## twice a hole and made it meaningless. Keeping the hand also fits golf -- it is
## your bag, and you keep a club until you actually use it.
@export var discard_hand_each_shot: bool = false
## Focus available each shot. Shot cards cost 1; techniques will spend the rest.
## Base focus, before equipment. Read `_bag.focus` rather than this.
@export var focus_max: int = 3
## If nothing in the opening hand reaches this share of the hole, something
## longer is dug out of the bag. Standing on a 500 yard tee holding three wedges
## is not an interesting decision, it is a hole lost before you have swung.
##
## Deliberately low. It rescues hopeless hands, it does not hand you the ideal
## club: on a long par 5 only a driver clears the bar, but on a par 4 a mid iron
## does, so playing one from the back of the bag is still a disadvantage you have
## to think your way out of.
@export var tee_reach_fraction: float = 0.45
## The same idea at the other end of the hole. The power meter sweeps 0 to 100
## and back, so there is a floor on how gently you can realistically hit a club:
## below about this share of its range you are trying to catch a bar that is
## barely off the peg. If nothing in hand can be dialled down to the shot in
## front of you, something shorter is dug out of the bag.
##
## Without this you could stand three feet from the cup holding two drivers and
## a 5 iron, and every single attempt would blade it clean across the green.
@export var min_power_fraction: float = 0.12
## Worst score you can take on a hole before you pick up and walk off. Golf has
## this rule for the same reason a roguelike needs it: one hole coming apart
## should cost you a hole, not the entire round.
@export var max_over_par: int = 5
## How long the camera spends walking the hole before the first shot.
@export var FLYOVER_SECONDS: float = 1.6

@onready var _course: CourseRenderer = $CourseRenderer
@onready var _aim: AimController = $AimController
@onready var _ball: Ball = $Ball
@onready var _camera: CourseCamera = $Camera2D
@onready var _effects: ShotEffects = $ShotEffects

## Set when the last putt fell in off the lip rather than being taken cleanly, so
## the result can say which it was.
var _toppled_in: bool = false

var deck: Deck = null
var strokes: int = 0
var focus: int = 0
var selected_index: int = -1
## Which way the player has asked the ball to bend: -1 draw, 0 straight, 1 fade.
## Reset every turn, because a shape is a decision about the shot in front of
## you and not a setting you leave on.
var shot_shape: int = 0
## The bag's rules for this hole, once equipment has adjusted them.
var _bag: BagRules = BagRules.new()
## Free techniques left this hole.
var _free_techniques: int = 0
## Techniques played this turn, folded into the next stroke and then cleared.
var pending_modifiers: Array[CardEffect] = []
## Card names behind those modifiers, for the HUD.
var pending_modifier_names: Array[String] = []
## The club played on the previous stroke of this hole, for cards that read the
## sequence rather than the stroke. Cleared with the hole.
var _last_club_id: StringName = &""

var _finished: bool = false
## False on the tee: there is no stroke to take back yet.
var _can_rewind: bool = false
## Where the current shot was played from, for stroke-and-distance penalties.
var _shot_origin: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _sampler: SurfaceSampler = null

## Equipment carried by the run. Injected, because a hole has no business owning
## anything that outlives it.
var relics: Array[RelicSpec] = []
## The run's score against par, for equipment that only helps when behind.
var run_score_to_par: int = 0
## Lost balls already rescued on this hole, so once-a-hole equipment can count.
var _recoveries_used: int = 0

## Special rules this hole plays under, if any. Injected like everything else
## that belongs to the run rather than to the hole scene.
var rule_set: CourseRuleSet = null
var _rule_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()

	if hole == null:
		push_error("HoleView: no HoleData assigned.")
		return

	_course.set_hole(hole)
	_ball.configure(hole.pin_position, hole.cup_pixels(), hole.bounds)
	_sampler = SurfaceSampler.new(hole)
	_ball.sampler = _sampler
	_camera.setup(_ball, hole)

	_aim.pixels_per_yard = hole.pixels_per_yard
	_aim.wind = hole.wind_vector()
	_aim.shot_requested.connect(_on_shot_requested)
	_aim.power_changed.connect(func(p: float) -> void:
		power_changed.emit(p)
		_emit_apex(p))
	_aim.swing_changed.connect(
		func(phase: int, power: float, marker: float, band: float) -> void:
			swing_changed.emit(phase, power, marker, band))

	_ball.came_to_rest.connect(_on_ball_came_to_rest)
	_ball.holed_out.connect(_on_ball_holed_out)
	_ball.went_out_of_bounds.connect(_on_ball_out_of_bounds)
	_ball.saved_from_trouble.connect(_on_ball_saved)
	_ball.caught_by_hazard.connect(_on_ball_caught)
	_ball.landed.connect(_on_ball_landed)
	_ball.struck_canopy.connect(_on_ball_struck_canopy)
	_ball.lipped_out.connect(_on_ball_lipped_out)
	_ball.hung_on_the_lip.connect(_on_ball_hung_on_the_lip)

	# Deliberately NOT starting here: children are ready before their parent, so
	# anything emitted now would fire before Main has connected the HUD. Main
	# injects the deck and calls start_hole() once the wiring is in place.


func _process(_delta: float) -> void:
	# The aim overlay lives at the ball, so it always fans out from the lie.
	_aim.position = _ball.position


func _unhandled_input(event: InputEvent) -> void:
	if _finished or deck == null or _ball.is_moving():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			select_card(-1)
			get_viewport().set_input_as_handled()
			return
		var slot: int = int(event.keycode) - int(KEY_1)
		if slot >= 0 and slot < deck.hand.size():
			activate_card(slot)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		select_card(-1)
		get_viewport().set_input_as_handled()


# --- Setup ----------------------------------------------------------------

## Injected by the run layer before start_hole().
func setup_deck(new_deck: Deck) -> void:
	deck = new_deck


## Also injected by the run layer: what the player is carrying, and how the card
## is going. Both belong to the run rather than to this hole.
func setup_run(carried: Array[RelicSpec], score_to_par: int) -> void:
	relics = carried
	run_score_to_par = score_to_par


## Special rules for this hole. Seeded from the hole so a boss behaves the same
## way each time you look at it, rather than rerolling on every redraw.
func setup_rules(rules: CourseRuleSet, rule_seed: int) -> void:
	rule_set = rules
	_rule_rng.seed = rule_seed


# --- Hole lifecycle -------------------------------------------------------

func start_hole() -> void:
	if deck == null:
		push_error("HoleView: start_hole() called with no deck.")
		return

	_finished = false
	strokes = 0
	_last_club_id = &""
	_shot_origin = hole.tee_position
	_can_rewind = false
	_recoveries_used = 0
	_clear_modifiers()
	_settle_bag()
	# The overlay flies the same arc against the same ground the ball will.
	_aim.sampler = _ball.sampler
	_ball.reset_to(hole.tee_position)
	_effects.clear()
	deck.reset_for_hole()

	if rule_set != null:
		var start_ctx := _rule_context()
		for rule in rule_set.rules:
			if rule != null:
				rule.on_hole_start(hole, start_ctx)
		_apply_rule_context(start_ctx)

	# A look down the hole before you play it. The camera only shows a slice of
	# the course now, so on a long par 5 the green is off screen when you stand
	# on the tee -- arriving without ever having seen it is disorienting in a way
	# that panning about manually does not really fix.
	var wait := _camera.flyover(FLYOVER_SECONDS)

	hole_started.emit(hole)
	rules_announced.emit(rule_set)
	strokes_changed.emit(strokes)
	_emit_distance()
	_emit_lie()
	_begin_shot_turn()
	# Aiming stays off until the camera has finished its walk, or the first shot
	# of every hole is played at a view that is still moving.
	_aim.enabled = false
	status_message.emit("Choose a shot from your hand.")
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
		if not _finished:
			_set_selection(selected_index)


## Top the hand back up and refresh focus, ready for the next stroke.
func _begin_shot_turn() -> void:
	if _finished:
		return
	if strokes >= hole.par + max_over_par:
		_pick_up()
		return
	if discard_hand_each_shot:
		deck.discard_hand()
	_run_stroke_rules()
	deck.deal_up_to(_bag.club_hand, _bag.extra_hand)
	_ensure_playable_hand()
	_ensure_tee_shot()
	_ensure_short_game()
	_emit_lie()
	focus = _bag.focus
	shot_shape = 0
	_set_selection(-1)
	focus_changed.emit(focus, _bag.focus)
	_emit_hand()
	_emit_piles()
	_emit_modifiers()


## Single entry point for the hand. Shot cards get picked up and aimed; anything
## else resolves straight away.
func activate_card(index: int) -> void:
	if _finished or deck == null or _ball.is_moving():
		return
	if index < 0 or index >= deck.hand.size():
		return

	var card: CardData = deck.hand[index]
	if card.effective_cost() > focus:
		status_message.emit("Not enough focus for %s." % card.title())
		return

	if card.is_shot():
		select_card(index)
		return

	# One focus is always held back for the stroke itself. Without this you could
	# spend the lot on techniques and then be unable to actually hit the ball.
	if card.effective_cost() > focus - 1:
		status_message.emit("Keep a focus back for the stroke itself.")
		return
	_play_support_card(index)


func select_card(index: int) -> void:
	if _finished or _ball.is_moving():
		return
	if index < -1 or index >= deck.hand.size():
		return
	if index >= 0 and not deck.hand[index].is_shot():
		return
	if index >= 0 and not _can_play_from_lie(deck.hand[index]):
		status_message.emit("You cannot play that from %s." % current_lie().display_name.to_lower())
		return

	_set_selection(index)
	_emit_hand()


## Techniques and utilities: spend focus, resolve, discard. No stroke is played.
func _play_support_card(index: int) -> void:
	var card: CardData = deck.hand[index]

	var ctx := EffectContext.new()
	ctx.ball_position = _ball.position
	ctx.pin_position = hole.pin_position
	ctx.last_shot_origin = _shot_origin
	ctx.strokes = strokes
	ctx.can_rewind = _can_rewind
	ctx.pixels_per_yard = hole.pixels_per_yard

	for effect in card.active_effects():
		if effect == null:
			continue
		effect.on_play(ctx)
		if ctx.is_rejected():
			break

	if ctx.is_rejected():
		# The card stays in hand and no focus is spent.
		status_message.emit(ctx.rejection_reason())
		return

	focus -= _cost_of(card)
	var modifiers := card.shot_modifiers()
	if not modifiers.is_empty():
		pending_modifiers.append_array(modifiers)
		pending_modifier_names.append(card.title())
	deck.play_from_hand(index)
	# Support cards replace themselves, so spending focus digs through the bag
	# rather than thinning your options.
	deck.deal_up_to(_bag.club_hand, _bag.extra_hand)

	# Keep the player's shot selection pointing at the same card.
	if selected_index == index:
		_set_selection(-1)
	elif selected_index > index:
		_set_selection(selected_index - 1)
	else:
		_set_selection(selected_index)

	if ctx.move_ball_to != null:
		_ball.reset_to(ctx.move_ball_to)
		_emit_distance()
	if ctx.stroke_delta != 0:
		strokes = maxi(0, strokes + ctx.stroke_delta)
		strokes_changed.emit(strokes)
	if ctx.consume_rewind:
		_can_rewind = false

	_ensure_playable_hand()
	focus_changed.emit(focus, _bag.focus)
	_emit_hand()
	_emit_piles()
	_emit_modifiers()
	status_message.emit(ctx.message if ctx.message != "" else "%s played." % card.title())


## A hand of nothing but techniques cannot play a stroke, and the hand only
## refills once a stroke has been played -- so without this the hole deadlocks.
## Rummage until there is something to hit with.
func _ensure_playable_hand() -> void:
	for attempt in 3:
		if _hand_has_shot():
			if attempt > 0:
				status_message.emit("Nothing you can play from here. A quick rummage in the bag.")
			return
		deck.discard_hand()
		deck.deal_up_to(_bag.club_hand, _bag.extra_hand)


## Only ever fires on the tee shot. Later in the hole a short hand is a real
## situation you play your way out of; on the tee it is just bad luck.
func _ensure_tee_shot() -> void:
	if strokes > 0:
		return

	var needed := hole.hole_length_yards() * tee_reach_fraction
	var weakest := -1
	var weakest_reach := INF
	for i in deck.hand.size():
		var card: CardData = deck.hand[i]
		if not card.is_shot():
			continue
		var reach := ShotProfile.from_card(card).max_reach_yards()
		if reach >= needed:
			return  # something in hand is long enough already
		if reach < weakest_reach:
			weakest_reach = reach
			weakest = i

	# Nothing reaches. Find the longest club still in the bag and swap it for the
	# least useful thing being held.
	var longest := -1
	var longest_reach := -1.0
	for i in deck.draw_pile.size():
		var card: CardData = deck.draw_pile[i]
		if not card.is_shot():
			continue
		var reach := ShotProfile.from_card(card).max_reach_yards()
		if reach > longest_reach:
			longest_reach = reach
			longest = i

	if longest < 0 or weakest < 0 or longest_reach <= weakest_reach:
		return
	if deck.swap_from_draw_pile(weakest, longest):
		status_message.emit("You dig out something longer.")


## The tee rule in reverse: if every club in hand would fly the green even when
## feathered, reach into the bag for something you can actually hit softly.
##
## It self-gates on distance rather than on being "near the green", because the
## test is already the right one everywhere: from 400 yards a driver clears the
## bar comfortably, so nothing happens. It only fires when you are genuinely
## stuck, and it hands you the shortest club you own, never the best one.
func _ensure_short_game() -> void:
	var needed := _yards_to_pin()
	var longest := -1
	var longest_reach := -1.0
	var shortest_held := INF

	for i in deck.hand.size():
		var card: CardData = deck.hand[i]
		if not _can_play_from_lie(card):
			continue
		var reach := ShotProfile.from_card(card).max_reach_yards()
		shortest_held = minf(shortest_held, reach)
		if reach > longest_reach:
			longest_reach = reach
			longest = i

	# Something in hand can be played gently enough to stay on this hole.
	if shortest_held * min_power_fraction <= needed:
		return

	var shortest := _shortest_in_draw_pile()
	# Your three putters are all in the played pile. It is your own bag, so you
	# are allowed to go back through it rather than be stranded by shuffle order.
	if shortest < 0 and not deck.discard_pile.is_empty():
		deck.recycle_discard_into_draw()
		shortest = _shortest_in_draw_pile()
	if shortest < 0 or longest < 0:
		return

	var shortest_reach := ShotProfile.from_card(deck.draw_pile[shortest]).max_reach_yards()
	if shortest_reach >= shortest_held:
		return
	if deck.swap_from_draw_pile(longest, shortest):
		status_message.emit("You reach for something softer.")


## Index of the gentlest club left in the bag that this lie allows, or -1.
func _shortest_in_draw_pile() -> int:
	var shortest := -1
	var shortest_reach := INF
	for i in deck.draw_pile.size():
		var card: CardData = deck.draw_pile[i]
		if not _can_play_from_lie(card):
			continue
		var reach := ShotProfile.from_card(card).max_reach_yards()
		if reach < shortest_reach:
			shortest_reach = reach
			shortest = i
	return shortest


## You have made a mess of this one. Take the maximum and walk to the next tee.
func _pick_up() -> void:
	_finished = true
	_set_selection(-1)
	_aim.enabled = false
	strokes = hole.par + max_over_par
	strokes_changed.emit(strokes)
	status_message.emit("You pick it up. Take the %d and move on." % strokes)
	hole_completed.emit(strokes, hole.par, false)


func _hand_has_shot() -> bool:
	for card in deck.hand:
		if _can_play_from_lie(card):
			return true
	return false


## Sand is the case that matters: you cannot putt your way out of a bunker, so a
## hand of nothing but putters has to count as unplayable.
func _can_play_from_lie(card: CardData) -> bool:
	if not card.is_shot():
		return false
	if current_lie().blocks_ground_shots and card.club != null and card.club.is_ground_shot:
		return false
	return true


## The read, published whenever the ball settles somewhere new.
func _emit_slope() -> void:
	var fall := hole.slope_at(_ball.position)
	var from := _ball.position
	# Off the green there is no slope under the ball at all -- slope_at is zero
	# by design. A green read is therefore the green's own fall, taken at the
	# pin, which is the information that actually changes which side of the flag
	# you go at from two hundred yards.
	if fall == Vector2.ZERO and has_insight(InsightRelic.GREEN_READ):
		fall = hole.slope_at(hole.pin_position)
	# Described along the line you are actually playing, which is still from the
	# ball: the read is the green's, the direction is yours.
	slope_changed.emit(fall, hole.slope_note_of(fall, from, hole.pin_position))


func current_lie() -> SurfaceType:
	if hole == null:
		return SurfaceLibrary.fallback()
	return hole.surface_at(_ball.position)


func selected_card() -> CardData:
	if selected_index < 0 or selected_index >= deck.hand.size():
		return null
	return deck.hand[selected_index]


func _set_selection(index: int) -> void:
	selected_index = index
	var card := selected_card()
	if card == null:
		_aim.shot_profile = null
		_aim.enabled = false
		shape_changed.emit(false, 0, 0.0)
		return
	var profile := _build_profile(card)
	if profile.conceal_shape and has_insight(InsightRelic.SHOT_SHAPE):
		profile.conceal_shape = false
	_aim.shot_profile = profile
	_aim.enabled = true
	shape_changed.emit(profile.shape_deg > 0.0, shot_shape, profile.shape_deg)


## Draw, straight or fade, chosen before the swing. Rebuilds the staged profile
## so the aiming overlay redraws with the bend the player has just asked for --
## the whole point of shaping a shot yourself rather than being handed one is
## that you can see where it finishes.
func set_shot_shape(shape: int) -> void:
	var wanted := clampi(shape, -1, 1)
	if wanted == shot_shape:
		return
	shot_shape = wanted
	if selected_index >= 0:
		Sfx.play(&"select", -6.0)
	_set_selection(selected_index)


## The card, then the techniques played this turn, then the equipment, then the
## lie. Equipment comes before the lie on purpose: a sand wedge or an angry
## caddie works by resisting the ground, which only means anything if the ground
## has not been applied yet.
func _build_profile(card: CardData, extra: Array = []) -> ShotProfile:
	# The bag goes on before anything is folded in, so a technique held over from
	# earlier this turn can still scale itself on what you are carrying.
	var profile := ShotProfile.from_card(card, BagStats.of(deck.cards))
	# Before anything is folded in, because the lie goes on after the effects and
	# a card asking whether it is in trouble has to be able to hear yes.
	profile.set_situation(strokes + 1, hole.par, current_lie().modifies_play(),
		_last_club_id)
	# `extra` is a card being considered rather than played, so the hand can be
	# asked what would happen without anything being spent.
	var folded: Array = pending_modifiers.duplicate()
	folded.append_array(extra)
	profile.apply_effects(folded)
	_apply_relics(profile)
	current_lie().apply_to(profile)
	# The course speaks last: a distraction should be able to ruin a shot that
	# everything else has just made perfect.
	_apply_rules_to_profile(profile)
	# And the shape the player asked for on top of all of it, because a club you
	# can work is worked whatever the ground and the weather are doing. It adds
	# to any bend already on the stroke rather than replacing it: shaping a Draw
	# further left is a real thing to want.
	if profile.shape_deg > 0.0 and shot_shape != 0:
		profile.curve_deg += float(shot_shape) * profile.shape_deg
	return profile


## The course gets its say before every stroke: the weather turns, the
## groundskeeper moves things, someone coughs.
func _run_stroke_rules() -> void:
	if rule_set == null:
		return
	var ctx := _rule_context()
	for rule in rule_set.rules:
		if rule != null:
			rule.before_stroke(hole, ctx)
	_apply_rule_context(ctx)


func _rule_context() -> CourseRuleContext:
	var ctx := CourseRuleContext.new()
	ctx.stroke_number = strokes + 1
	ctx.strokes_taken = strokes
	ctx.rng = _rule_rng
	return ctx


## Rules only ever ask; the hole is what actually changes and tells anyone who
## needs to know.
func _apply_rule_context(ctx: CourseRuleContext) -> void:
	if ctx.course_changed:
		_course.set_hole(hole)
	if ctx.conditions_changed or ctx.course_changed:
		_aim.wind = hole.wind_vector()
		conditions_changed.emit(hole)
	for message in ctx.messages:
		status_message.emit(message)


func _apply_rules_to_profile(profile: ShotProfile) -> void:
	if rule_set == null:
		return
	var ctx := _rule_context()
	for rule in rule_set.rules:
		if rule != null:
			rule.modify_profile(profile, ctx)


## Settle what a turn looks like this hole, once, before anything is dealt.
## Done here rather than per stroke so a relic cannot change the hand out from
## under a player mid-hole.
func _settle_bag() -> void:
	_bag = BagRules.new(club_hand, focus_max, extra_hand)
	var ctx := _relic_context()
	for relic in relics:
		for effect in relic.effects:
			if effect != null:
				effect.modify_bag(_bag, ctx)
	# The course speaks after the equipment, and through the same object, so a
	# relic that hands you a card and a hole that takes one away cancel out
	# rather than one of them quietly winning.
	if rule_set != null:
		for rule in rule_set.rules:
			if rule is BagRestrictionRule:
				(rule as BagRestrictionRule).modify_bag(_bag)
	_bag.clamped()
	_free_techniques = _bag.free_techniques


## What this card would cost if it were played right now. Asked without
## charging for it, because the hand has to grey out on the same number the
## stroke will actually pay -- otherwise a free technique is refused for a cost
## it was never going to charge.
func _price_of(card: CardData) -> int:
	if card.is_shot() or _free_techniques <= 0:
		return card.effective_cost()
	return 0


## The same number, charged. A free technique is spent here rather than
## discounted on the card, so the card's printed cost never lies and the
## allowance is visibly used up.
func _cost_of(card: CardData) -> int:
	var price := _price_of(card)
	if price == 0 and not card.is_shot() and _free_techniques > 0:
		_free_techniques -= 1
		status_message.emit("%s, on the house. %d left this hole."
			% [card.title(), _free_techniques])
	return price


## Does anything in the bag grant this? Asked by name, so a new one is a
## constant and a branch where it is shown.
func has_insight(insight: StringName) -> bool:
	for relic in relics:
		for effect in relic.effects:
			if effect != null and effect.grants(insight):
				return true
	return false


func _apply_relics(profile: ShotProfile) -> void:
	if relics.is_empty():
		return
	var ctx := _relic_context()
	for relic in relics:
		for effect in relic.effects:
			if effect != null:
				effect.modify_profile(profile, ctx)


func _relic_context() -> RelicContext:
	var ctx := RelicContext.new()
	ctx.stroke_number = strokes + 1
	ctx.strokes_taken = strokes
	ctx.par = hole.par
	ctx.run_score_to_par = run_score_to_par
	ctx.lie = current_lie()
	ctx.recoveries_used = _recoveries_used
	return ctx


## Ask the bag whether anything saves this one. Returns true if a penalty should
## not be charged.
func _try_relic_rescue() -> bool:
	var ctx := _relic_context()
	for relic in relics:
		for effect in relic.effects:
			if effect != null and effect.try_rescue_ball(ctx):
				_recoveries_used += 1
				status_message.emit("%s saves you. No penalty." % relic.display_name)
				return true
	return false


# --- Shot flow ------------------------------------------------------------

func _on_shot_requested(direction: Vector2, power_pct: float,
		offline_deg: float = 0.0) -> void:
	if _finished or _ball.is_moving():
		return
	var card := selected_card()
	if card == null:
		return

	var profile := _build_profile(card)

	focus -= card.effective_cost()
	deck.play_from_hand(selected_index)
	_set_selection(-1)
	focus_changed.emit(focus, _bag.focus)
	_emit_hand()
	_emit_piles()

	_shot_origin = _ball.position
	_can_rewind = true
	strokes += 1
	strokes_changed.emit(strokes)

	# Techniques are spent by the stroke they shaped.
	_clear_modifiers()
	# Remembered for the next stroke, so a card can ask whether you are still
	# holding the club you just hit.
	if profile.source_card != null:
		_last_club_id = profile.source_card.id

	var shot := ShotResolver.resolve(profile, power_pct, direction, _rng,
		hole.wind_vector(), offline_deg)
	Sfx.play_strike(profile, power_pct)
	# A full driver should land with some weight; a tap-in should not.
	_camera.kick(lerpf(1.0, 7.0, clampf(power_pct, 0.0, 1.0))
		* clampf(profile.carry_yards_max / 250.0, 0.25, 1.0))
	_aim.enabled = false
	_camera.reset_look()
	# Before launch, not after: a tap-in putt has no carry and comes to rest
	# synchronously inside launch(), which would begin the next turn first.
	status_message.emit(_describe_shot(shot))
	if not is_zero_approx(shot.timing_error_deg):
		# Said out loud, because a shot that leaves the club offline needs to be
		# obviously your doing rather than the game's.
		status_message.emit("%s  %s" % [
			_describe_shot(shot),
			"Pushed it." if shot.timing_error_deg > 0.0 else "Pulled it."])
	_ball.launch(shot, hole.pixels_per_yard)


## Into the trees. No stroke penalty -- being under a tree with no shot is
## punishment enough, and stacking a penalty on top of a lost position is how a
## hazard stops being interesting and starts being unfair.
func _on_ball_struck_canopy(pos: Vector2) -> void:
	Sfx.play(&"land_soft", 2.0, 0.14)
	_effects.impact(pos, 0.5, hole.surface_at(pos))
	_camera.kick(2.0)
	status_message.emit("Into the trees. It drops straight down.")


## Too much pace, and the hole says so. Worth announcing because it is the one
## miss the player can actually learn from: the line was good and the speed was
## not, which is information a ball trickling to a stop four feet away never
## gives you.
func _on_ball_lipped_out(pos: Vector2) -> void:
	Sfx.play(&"putt", -3.0, 0.5)
	_effects.rim(pos, 1.0)
	_camera.kick(1.4)
	status_message.emit("Lipped out. Too much pace.")


## Hung on the edge, and the green took it. The best moment in golf, so it gets
## the same celebration as any other putt -- only the wording changes, and it is
## remembered rather than said here, because the holed-out message lands a moment
## later and would simply talk over it.
func _on_ball_hung_on_the_lip(pos: Vector2) -> void:
	_toppled_in = true
	_effects.rim(pos, 0.6)


func _on_ball_landed(pos: Vector2, impact: float) -> void:
	var surface := hole.surface_at(pos)
	Sfx.play_landing(surface)
	_effects.impact(pos, impact, surface)


func _on_ball_came_to_rest(_pos: Vector2) -> void:
	_emit_distance()
	if _finished:
		return
	_begin_shot_turn()


func _on_ball_holed_out() -> void:
	_finished = true
	_set_selection(-1)
	_emit_distance()
	_emit_lie()
	Sfx.play(&"holed")
	_effects.celebrate(hole.pin_position)
	_camera.kick(3.0)
	status_message.emit("It hangs on the edge... and drops!" if _toppled_in
		else "In the hole!")
	_toppled_in = false
	hole_completed.emit(strokes, hole.par, true)


## Water and friends: a penalty stroke, then a drop back down the line of play.
func _on_ball_caught(pos: Vector2) -> void:
	var surface := hole.surface_at(pos)
	var rescued := _try_relic_rescue()
	if not rescued:
		strokes += surface.penalty_strokes
		strokes_changed.emit(strokes)

	_ball.reset_to(_drop_position(pos))
	_emit_distance()
	_begin_shot_turn()
	if not rescued:
		status_message.emit("%s! %d penalty stroke. Dropping behind." % [
			surface.display_name, surface.penalty_strokes])


## Walk back down the line the ball came in on until there is somewhere legal to
## play from, which is roughly what the rules ask you to do.
func _drop_position(entry: Vector2) -> Vector2:
	var back := (_shot_origin - entry)
	if back.length() < 1.0:
		return _shot_origin
	var step := back.normalized() * 8.0
	var candidate := entry
	for i in 60:
		candidate += step
		if candidate.distance_to(_shot_origin) < 8.0:
			break
		var surface := hole.surface_at(candidate)
		if not surface.catches_ball and hole.bounds.has_point(candidate):
			return candidate
	return _shot_origin


func _on_ball_saved(_pos = null) -> void:
	status_message.emit("Fished out. No penalty, no questions.")


func _on_ball_out_of_bounds(_pos: Vector2) -> void:
	# Stroke and distance: the shot already counted, add a penalty and replay
	# from where it was struck.
	var rescued := _try_relic_rescue()
	if not rescued:
		strokes += 1
		strokes_changed.emit(strokes)
	_ball.reset_to(_shot_origin)
	_emit_distance()
	_begin_shot_turn()
	if not rescued:
		status_message.emit("Out of bounds! One penalty stroke, playing again from there.")


# --- Helpers --------------------------------------------------------------

## What the selected club would do at this swing, measured against whatever is
## over the ball's head right now. The lie is the right thing to test: the case
## that matters is standing under a tree, where going over is not an option and
## the answer is to keep it low.
func _emit_apex(power: float) -> void:
	var card := selected_card()
	if card == null:
		apex_changed.emit(0.0, false)
		return
	var profile := _build_profile(card)
	var apex := profile.apex_yards(power)
	apex_changed.emit(apex, current_lie().blocks_at_height(apex))


func _yards_to_pin() -> float:
	return hole.to_yards(_ball.position.distance_to(hole.pin_position))


func _emit_distance() -> void:
	distance_changed.emit(_yards_to_pin())


func _emit_hand() -> void:
	var playable: Array = []
	var combining: Array = []
	for card in deck.hand:
		playable.append(can_play(card))
		combining.append(would_combine(card))
	hand_changed.emit(deck.hand, selected_index, playable, combining)


## The club the staged shot is being built on: whichever is selected, and failing
## that the first one in hand, so a technique can be judged before a club has
## been picked. Most conditions do not depend on the club at all.
func _staging_club() -> CardData:
	var chosen := selected_card()
	if chosen != null and chosen.is_shot():
		return chosen
	for card in deck.hand:
		if card != null and card.is_shot():
			return card
	return null


## Combinations live on the stroke as it stands.
func live_combinations() -> PackedStringArray:
	var club := _staging_club()
	if club == null or hole == null:
		return PackedStringArray()
	return _build_profile(club).fired_combos


## Would playing this card right now set off a combination?
##
## Asked of every card in hand, every time the hand changes, so a pair is visible
## *before* the focus is spent. A combination the player can only discover by
## spending focus and comparing numbers afterwards is not a decision, and the
## decision is the whole of what makes it a combo rather than a bonus.
func would_combine(card: CardData) -> bool:
	if card == null or card.is_shot() or hole == null:
		return false
	if not can_play(card):
		return false
	var club := _staging_club()
	if club == null:
		return false
	var without := _build_profile(club).fired_combos.size()
	var with_it := _build_profile(club, card.shot_modifiers()).fired_combos.size()
	return with_it > without


## The single source of truth for whether a card can be played right now.
## activate_card() applies exactly these rules, so the hand always tells the
## truth about what will happen if you click.
func can_play(card: CardData) -> bool:
	var price := _price_of(card)
	if price > focus:
		return false
	if card.is_shot():
		return _can_play_from_lie(card)
	# Support cards must leave a focus behind for the stroke itself.
	return price <= focus - 1


func _emit_piles() -> void:
	piles_changed.emit(deck.draw_pile.size(), deck.discard_pile.size())


func _clear_modifiers() -> void:
	pending_modifiers.clear()
	pending_modifier_names.clear()
	_emit_modifiers()


func _emit_lie() -> void:
	lie_changed.emit(current_lie())
	_emit_slope()


func _emit_modifiers() -> void:
	modifiers_changed.emit(pending_modifier_names.duplicate(),
		live_combinations())


func _describe_shot(shot: ShotResult) -> String:
	var shape := "straight"
	if absf(shot.aim_error_deg) > 2.5:
		shape = "pushed right" if shot.aim_error_deg > 0.0 else "pulled left"
	return "%s, %d yards, %s." % [
		shot.profile.display_name, roundi(shot.total_yards()), shape]


## Golf's name for a score relative to par.
static func score_name(strokes_taken: int, par: int) -> String:
	if strokes_taken == 1:
		return "Hole in One"
	var diff := strokes_taken - par
	match diff:
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		3: return "Triple Bogey"
	return "%+d" % diff
