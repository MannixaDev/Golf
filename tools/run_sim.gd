## Plays whole runs with the human-like robot golfer, over procedurally
## generated holes.
##
## Two questions this answers, neither of which a screenshot can:
##   1. Are generated holes playable at every difficulty tier?
##   2. Is the cut line survivable but not free?
##
## The ball is stepped by hand rather than waiting on engine frames, so a few
## hundred holes take seconds instead of minutes.
extends SceneTree

const HUMAN_POWER_ERROR := 0.06
const HUMAN_AIM_ERROR_DEG := 1.5
const HAND_SIZE := 5
const FOCUS_MAX := 3
## A hole this long has gone wrong; stop rather than loop forever.
const MAX_STROKES := 20
## Mirrors HoleView.max_over_par. Kept as its own constant because this file
## never builds a HoleView to ask.
const PICK_UP_OVER_PAR := 5
## Milliseconds of scatter on the robot's timing press. See _timing_error.
const TIMING_SIGMA := 45.0
const STEP := 1.0 / 60.0

const TIER_SAMPLES := 70
const RUNS := 40

var rng := RandomNumberGenerator.new()
var deck_list: DeckList
var ball: Ball

# State for the hole being played.
var hole: HoleData
var deck: Deck
var strokes := 0
var shot_origin := Vector2.ZERO
var pending: Array[CardEffect] = []
var holed := false
var abandoned := 0
## Shots that finished beyond the white stakes, and holes played, so the rate
## can be read rather than inferred from the scores.
var ob_count := 0
var holes_played := 0


func _initialize() -> void:
	rng.seed = 20240107
	deck_list = load("res://resources/decks/starting_deck.tres")
	ball = load("res://scenes/golf/ball.tscn").instantiate()
	root.add_child(ball)
	ball.holed_out.connect(func() -> void: holed = true)
	ball.went_out_of_bounds.connect(_on_ob)
	ball.caught_by_hazard.connect(_on_caught)

	_report_tiers()
	_report_runs()
	quit()


## A deck that shuffles from this run's seed rather than from the clock.
##
## Without this the whole harness was unreproducible: Deck randomizes itself on
## construction, so running the same code twice gave -7.5 and -7.1, and fifteen
## balls out of bounds and then six. Every before-and-after this tool has ever
## been used for was two draws from the same distribution.
func _deck() -> Deck:
	var built := Deck.new(deck_list.build())
	built.shuffle_from(rng.randi())
	return built


# --- Reports --------------------------------------------------------------

func _report_tiers() -> void:
	print("=== generated holes, %d per tier ===" % TIER_SAMPLES)
	for tier in 5:
		var total := 0
		var worst := -99
		var pars: Dictionary = {}
		for i in TIER_SAMPLES:
			var generated := HoleGenerator.generate(rng.randi(), tier, i + 1)
			var score := _play_hole(generated, _deck()) - generated.par
			total += score
			worst = maxi(worst, score)
			pars[generated.par] = int(pars.get(generated.par, 0)) + 1
		print("  tier %d: average %+.2f to par, worst %+d" % [
			tier, float(total) / TIER_SAMPLES, worst])
	if abandoned > 0:
		# Named for what actually stops the hole, which is the pick-up rule, not
		# the safety limit -- the old wording pointed at the wrong number and
		# made a working rule look like a runaway.
		print("  holes picked up at par + %d: %d of %d (%.1f%%)" % [
			PICK_UP_OVER_PAR, abandoned, holes_played,
			100.0 * abandoned / maxf(holes_played, 1)])
	if holes_played > 0:
		print("  shots out of bounds: %d over %d holes (%.2f a hole)" % [
			ob_count, holes_played, float(ob_count) / holes_played])


func _report_runs() -> void:
	print("")
	print("=== whole runs, cut at +%d, %d attempts ===" % [RunState.DEFAULT_CUT, RUNS])
	var cut := 0
	var total_score := 0
	var total_holes := 0
	var best := 99

	for attempt in RUNS:
		var run := RunState.new()
		var run_deck := _deck()
		var map := MapGenerator.generate(rng.randi())

		# Walk a route the way a player would, playing every hole it passes.
		var guard := 0
		while not map.available_ids().is_empty() and guard < 40:
			var options := map.available_ids()
			var id: int = options[rng.randi_range(0, options.size() - 1)]
			var node := map.node_by_id(id)
			map.travel_to(id)
			guard += 1
			if not node.plays_hole():
				continue
			var generated := HoleGenerator.generate(
				node.hole_seed, node.difficulty(), run.holes_played + 1)
			run.record_hole(_play_hole(generated, run_deck), generated.par)
			if run.finished:
				break

		if run.finished and not run.won:
			cut += 1
		total_score += run.score_to_par()
		total_holes += run.holes_played
		best = mini(best, run.score_to_par())

	print("  runs completed: %d of %d" % [RUNS - cut, RUNS])
	print("  missed the cut: %d (%.0f%%)" % [cut, 100.0 * cut / RUNS])
	print("  average card: %+.1f over %.1f holes, best %+d" % [
		float(total_score) / RUNS, float(total_holes) / RUNS, best])


# --- Playing one hole -----------------------------------------------------

func _play_hole(new_hole: HoleData, new_deck: Deck) -> int:
	hole = new_hole
	deck = new_deck
	deck.reset_for_hole()
	ball.configure(hole.pin_position, hole.cup_radius, hole.bounds)
	ball.sampler = SurfaceSampler.new(hole)
	ball.reset_to(hole.tee_position)
	strokes = 0
	holes_played += 1
	pending.clear()
	holed = false

	# The player picks up at par + HoleView.max_over_par, so the sim has to as
	# well or its per-hole worst case is a score nobody can actually be charged.
	# This harness re-implements the hole loop rather than driving HoleView, which
	# makes it fast and makes it quietly capable of disagreeing with the game --
	# so anywhere it can, it should copy the rule rather than invent one.
	var pick_up_at := hole.par + PICK_UP_OVER_PAR

	while not holed and strokes < mini(MAX_STROKES, pick_up_at):
		if not _play_stroke():
			break
		var guard := 0
		while ball.is_moving() and guard < 20000:
			ball._physics_process(STEP)
			guard += 1

	if not holed:
		abandoned += 1
		return mini(MAX_STROKES, pick_up_at)
	return strokes


## Playing the ball out to the high side, the way anybody stood over a putt does.
##
## The robot aimed straight at the cup on every putt, which was fine while greens
## were flat and became the same mistake as aiming at the flag on a dogleg the
## moment they were not: it was reporting the scores of somebody who never reads
## a green. That cost it four strokes a round, none of which was the game being
## hard.
##
## The break works out linear in distance -- a putt that just reaches travels for
## a time proportional to the root of the distance, and falls sideways with the
## square of that time -- so one constant covers every length of putt. It is the
## number tools/green_check.gd measures, divided by the ten yards it measures it
## over, and the robot reads it imperfectly.
const BREAK_PER_YARD := 0.193


func _read_the_break(target: Vector2) -> Vector2:
	if not hole.on_green(shot_origin):
		return target
	var fall := hole.slope_at(shot_origin)
	if fall == Vector2.ZERO:
		return target

	var line := target - shot_origin
	var length := line.length()
	if length < 1.0:
		return target
	var across := Vector2(-line.y, line.x).normalized()
	var sideways := fall.dot(across)
	var read := BREAK_PER_YARD * rng.randf_range(0.68, 1.18)
	return target - across * sideways * read * length


## Where the robot is actually trying to hit it.
##
## It used to aim at the flag on every stroke from every lie, which was harmless
## while holes ran in straight lines and became nonsense the moment they curved:
## on a dogleg, aiming at the pin means firing straight over the corner, and the
## simulation was reporting the scores of somebody who does that every single
## time. It walks the line of play now, the way a person does -- down the fairway
## until the green is in range, then at the flag.
func _target_for(reach_px: float) -> Vector2:
	var to_pin := shot_origin.distance_to(hole.pin_position)
	if to_pin <= reach_px or hole.spine.size() < 2:
		return hole.pin_position

	# Nearest point on the line of play, then walk forward by one shot.
	var nearest := 0
	var closest := INF
	for i in hole.spine.size():
		var away: float = shot_origin.distance_to(hole.spine[i])
		if away < closest:
			closest = away
			nearest = i

	var walked := 0.0
	var index := nearest
	while index < hole.spine.size() - 1 and walked < reach_px:
		walked += hole.spine[index].distance_to(hole.spine[index + 1])
		index += 1
	return hole.spine[index]


## The robot's thumb.
##
## Every shot used to resolve as a pure strike, which was fine while timing did
## not exist and became a lie the moment it did -- the simulation would have been
## reporting the scores of a player who never mistimes anything. So it presses
## the button with a human amount of error and takes what it gets.
##
## Modelled as a press time rather than as an outcome, so it goes through exactly
## the arithmetic the real swing does. The deviation is deliberately kind: a
## practised player is around 40ms, and a generous witness that still shows the
## game is too easy is a much stronger statement than a harsh one.
func _timing_error(profile: ShotProfile, power: float) -> float:
	var span := maxf(power, 0.08)
	var band := AimController.BASE_TOLERANCE * profile.sweet_spot_scale() * span
	var late := absf(rng.randfn(0.0, TIMING_SIGMA / 1000.0))
	var marker := late * span / AimController.TIMING_TIME
	if marker <= band:
		return 0.0
	var over := (marker - band) / maxf(span - band, 0.001)
	var shaped: float = pow(clampf(over, 0.0, 1.0), 1.4)
	return shaped * profile.offline_deg() * (1.0 if rng.randf() < 0.5 else -1.0)


## Returns false if the robot genuinely could not find anything to hit.
func _play_stroke() -> bool:
	deck.draw_up_to(HAND_SIZE)
	shot_origin = ball.position
	_spend_support(FOCUS_MAX)

	var remaining := hole.to_yards(shot_origin.distance_to(hole.pin_position))
	var slot := _pick_card(remaining)
	if slot < 0:
		# Nothing legal in hand: rummage, exactly as HoleView does.
		deck.discard_hand()
		deck.draw_up_to(HAND_SIZE)
		slot = _pick_card(remaining)
		if slot < 0:
			return false

	var card: CardData = deck.hand[slot]
	var profile := _profile_for(card)
	var power := clampf(remaining / profile.max_reach_yards(), 0.02, 1.0)
	power = clampf(power + rng.randf_range(-HUMAN_POWER_ERROR, HUMAN_POWER_ERROR), 0.02, 1.0)

	var target := _target_for(profile.max_reach_yards() * hole.pixels_per_yard)
	var aim := (_read_the_break(target) - shot_origin).normalized()
	aim = aim.rotated(deg_to_rad(rng.randf_range(-HUMAN_AIM_ERROR_DEG, HUMAN_AIM_ERROR_DEG)))

	deck.play_from_hand(slot)
	strokes += 1
	ball.launch(ShotResolver.resolve(profile, power, aim, rng, hole.wind_vector(),
			_timing_error(profile, power)),
		hole.pixels_per_yard)
	return true


func _spend_support(focus: int) -> void:
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
			index += 1
			continue

		focus -= card.cost
		pending.append_array(card.shot_modifiers())
		deck.play_from_hand(index)
		if ctx.move_ball_to != null:
			ball.reset_to(ctx.move_ball_to)
		if ctx.stroke_delta != 0:
			strokes = maxi(0, strokes + ctx.stroke_delta)


func _profile_for(card: CardData) -> ShotProfile:
	var profile := ShotProfile.from_card(card)
	profile.apply_effects(pending)
	hole.surface_at(ball.position).apply_to(profile)
	return profile


func _pick_card(remaining: float) -> int:
	var lie := hole.surface_at(ball.position)
	var best := -1
	var best_reach := INF
	var longest := -1
	var longest_reach := -1.0

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
	return best if best >= 0 else longest


func _on_ob(_pos: Vector2) -> void:
	strokes += 1
	ob_count += 1
	ball.reset_to(shot_origin)


func _on_caught(pos: Vector2) -> void:
	strokes += hole.surface_at(pos).penalty_strokes
	var back := shot_origin - pos
	var candidate := shot_origin
	if back.length() > 1.0:
		var step := back.normalized() * 8.0
		var probe := pos
		for i in 60:
			probe += step
			if probe.distance_to(shot_origin) < 8.0:
				break
			if not hole.surface_at(probe).catches_ball and hole.bounds.has_point(probe):
				candidate = probe
				break
	ball.reset_to(candidate)
