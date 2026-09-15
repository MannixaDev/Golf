## Throwaway harness: plays hole 1 with a "human-like robot golfer" that has
## realistic aim and power error, to verify that the deck, the shot resolver and
## the ball's flight/roll phases all agree with each other -- and to measure
## whether the hole is actually of a sane difficulty.
##
## Since Milestone 2 the robot must play out of a dealt hand, so this also
## exercises draw / play / discard / recycle.
extends SceneTree

## Nobody stops a ping-pong power meter exactly.
const HUMAN_POWER_ERROR := 0.06
## Nobody aims to the degree with a mouse.
const HUMAN_AIM_ERROR_DEG := 1.5
const CLUB_HAND := 4
const EXTRA_HAND := 2
const FOCUS_MAX := 3
const ROUNDS := 40

var hole: HoleData
var deck: Deck
var ball: Ball
var rng := RandomNumberGenerator.new()

var strokes := 0
var rounds := 0
var results: Array[int] = []
var round_done := false
var shot_origin := Vector2.ZERO
var verbose := false

## How often the player was near the green without a putter in hand -- the
## tension the card layer is supposed to create.
var stranded_hands := 0
var short_hands := 0
var support_played := 0
var pending: Array[CardEffect] = []
var sampler: SurfaceSampler = null
var lie_counts: Dictionary = {}
var water_balls := 0
var ob_balls := 0


func _initialize() -> void:
	rng.seed = 12345
	hole = load("res://resources/holes/hole_01.tres")

	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	deck = Deck.new(list.build())
	print("deck: %s, %d cards" % [list.display_name, deck.total_cards()])
	print("hole: %.1f yd, par %d" % [hole.hole_length_yards(), hole.par])

	ball = load("res://scenes/golf/ball.tscn").instantiate()
	root.add_child(ball)
	ball.configure(hole.pin_position, hole.cup_radius, hole.bounds)
	sampler = SurfaceSampler.new(hole)
	ball.sampler = sampler
	ball.holed_out.connect(_on_holed)
	ball.went_out_of_bounds.connect(_on_ob)
	ball.caught_by_hazard.connect(_on_caught)
	print("hazards: %d regions, wind %s" % [hole.hazards.size(), hole.wind_description()])
	_start_round()


func _start_round() -> void:
	strokes = 0
	ball.reset_to(hole.tee_position)
	deck.reset_for_hole()
	pending.clear()
	round_done = false


func _process(_delta: float) -> bool:
	if ball.is_moving():
		return false
	if round_done:
		round_done = false
		return _next_round()
	if strokes > 25:
		print("  ABANDONED after 25 strokes")
		results.append(99)
		round_done = true
		return false
	_play_shot()
	return false


func _next_round() -> bool:
	rounds += 1
	if rounds >= ROUNDS:
		var total := 0
		for r in results:
			total += r
		print("scores: ", results)
		print("average: %.2f  (par %d)" % [float(total) / results.size(), hole.par])
		print("short shots with no putter in hand: %d / %d" % [stranded_hands, short_hands])
		print("support cards played: %d" % support_played)
		print("balls in water: %d   out of bounds: %d" % [water_balls, ob_balls])
		var lies: Array = lie_counts.keys()
		lies.sort()
		var line: PackedStringArray = PackedStringArray()
		for name in lies:
			line.append("%s %d" % [name, lie_counts[name]])
		print("lies played from: ", ", ".join(line))
		return true
	_start_round()
	return false


func _play_shot() -> void:
	# Top the hand back up, exactly as HoleView does.
	deck.deal_up_to(CLUB_HAND, EXTRA_HAND)

	shot_origin = ball.position
	var lie := hole.surface_at(ball.position)
	lie_counts[lie.display_name] = lie_counts.get(lie.display_name, 0) + 1
	var focus := FOCUS_MAX
	pending.clear()

	# A human would not sit on unplayable clutter: spend spare focus on whatever
	# support cards are in hand, keeping one focus back for the stroke itself.
	# This also drags the real effect code through the loop every round.
	focus = _spend_support(focus)

	var remaining := hole.to_yards(shot_origin.distance_to(hole.pin_position))
	var slot := _pick_card(remaining)
	if slot < 0:
		print("  NO SHOT CARD IN HAND -- hand size %d" % deck.hand.size())
		round_done = true
		return

	var card: CardData = deck.hand[slot]
	if remaining < 25.0:
		short_hands += 1
		if not card.club.is_ground_shot:
			stranded_hands += 1

	var profile := _profile_for(card)
	var power := clampf(remaining / profile.max_reach_yards(), 0.02, 1.0)
	power = clampf(power + rng.randf_range(-HUMAN_POWER_ERROR, HUMAN_POWER_ERROR), 0.02, 1.0)

	var aim := (hole.pin_position - shot_origin).normalized()
	aim = aim.rotated(deg_to_rad(rng.randf_range(-HUMAN_AIM_ERROR_DEG, HUMAN_AIM_ERROR_DEG)))

	deck.play_from_hand(slot)
	strokes += 1
	var shot := ShotResolver.resolve(profile, power, aim, rng, hole.wind_vector())
	if verbose:
		print("  %d: %-8s pow %.2f  need %3.0f -> %3.0f yd" % [
			strokes, card.display_name, power, remaining, shot.total_yards()])
	ball.launch(shot, hole.pixels_per_yard)


## Play support cards out of hand while focus allows, applying their real
## effects. Returns the focus left for the stroke.
func _spend_support(focus: int) -> int:
	var index := 0
	while index < deck.hand.size() and focus > 1:
		var card: CardData = deck.hand[index]
		if card.is_shot() or card.cost > focus - 1:
			index += 1
			continue

		var ctx := EffectContext.new()
		ctx.ball_position = ball.position
		ctx.pin_position = hole.pin_position
		ctx.last_shot_origin = shot_origin
		ctx.strokes = strokes
		ctx.can_rewind = strokes > 0
		ctx.pixels_per_yard = hole.pixels_per_yard

		for effect in card.active_effects():
			effect.on_play(ctx)
			if ctx.is_rejected():
				break

		if ctx.is_rejected():
			# Cannot be used from here; leave it in hand and move on.
			index += 1
			continue

		focus -= card.cost
		pending.append_array(card.shot_modifiers())
		deck.play_from_hand(index)
		support_played += 1

		if ctx.move_ball_to != null:
			ball.reset_to(ctx.move_ball_to)
			shot_origin = ball.position
		if ctx.stroke_delta != 0:
			strokes = maxi(0, strokes + ctx.stroke_delta)
	return focus


func _profile_for(card: CardData) -> ShotProfile:
	var profile := ShotProfile.from_card(card)
	profile.apply_effects(pending)
	hole.surface_at(ball.position).apply_to(profile)
	return profile


## Shortest card in hand that can still cover the distance -- the same judgement
## a competent player makes, but limited to what was actually dealt.
func _pick_card(remaining: float) -> int:
	var best := -1
	var best_reach := INF
	var longest := -1
	var longest_reach := -1.0

	var lie := hole.surface_at(ball.position)
	for i in deck.hand.size():
		var card: CardData = deck.hand[i]
		if not card.is_shot():
			continue
		if lie.blocks_ground_shots and card.club != null and card.club.is_ground_shot:
			continue
		var reach := _profile_for(card).max_reach_yards()
		if reach > longest_reach:
			longest_reach = reach
			longest = i
		if reach >= remaining and reach < best_reach:
			best_reach = reach
			best = i

	# Nothing in hand reaches: take the longest thing dealt and advance.
	return best if best >= 0 else longest


func _on_holed() -> void:
	results.append(strokes)
	round_done = true


func _on_ob(_pos: Vector2) -> void:
	ob_balls += 1
	strokes += 1
	ball.reset_to(shot_origin)


## Same stroke-and-drop the hole applies, so scores stay comparable.
func _on_caught(pos: Vector2) -> void:
	water_balls += 1
	strokes += hole.surface_at(pos).penalty_strokes
	var back := (shot_origin - pos)
	var candidate := pos
	if back.length() > 1.0:
		var step := back.normalized() * 8.0
		for i in 60:
			candidate += step
			if candidate.distance_to(shot_origin) < 8.0:
				candidate = shot_origin
				break
			if not hole.surface_at(candidate).catches_ball and hole.bounds.has_point(candidate):
				break
	else:
		candidate = shot_origin
	ball.reset_to(candidate)
