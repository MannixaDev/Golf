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

## How good the golfer at the controls is.
##
## The robot used to be one player: 1.5 degrees of aim, six per cent on the
## power, and the shortest club in hand that still reaches, chosen correctly
## every single time. That is a tour professional with a caddie, and it shot -7.0
## and never missed a cut in forty attempts -- which said nothing whatever about
## whether the game can be lost, because it only ever measured the ceiling.
##
## A cut nobody can miss is not a cut, and "is this too easy" is the one question
## the project has been arguing about rather than measuring. So skill is a
## parameter now and the run report is a table across it.
class Golfer:
	var label: String
	var aim_error_deg: float
	var power_error: float
	## Milliseconds of scatter on the timing press.
	var timing_sigma: float
	## Chance of playing the wrong club -- one too much or one too little. The
	## other three are execution; this is judgement, and it is the mistake that
	## actually costs an amateur their card.
	var wrong_club: float

	func _init(name: String, aim: float, power: float, timing: float,
			club: float) -> void:
		label = name
		aim_error_deg = aim
		power_error = power
		timing_sigma = timing
		wrong_club = club


## The band the tier report is measured at, so those numbers stay comparable with
## every reading taken before skill was a parameter.
static func tour() -> Golfer:
	return Golfer.new("tour pro", 1.5, 0.06, 45.0, 0.0)


## Four golfers, from the one the sim has always been to somebody who plays a few
## times a year. Deliberately spread wide: the interesting question is not where
## the average lands but whether anybody at all is under pressure.
static func field() -> Array:
	return [
		tour(),
		Golfer.new("scratch", 2.6, 0.09, 65.0, 0.05),
		Golfer.new("club player", 4.2, 0.13, 95.0, 0.16),
		Golfer.new("weekend golfer", 6.8, 0.20, 140.0, 0.30),
	]

const HAND_SIZE := 5
const FOCUS_MAX := 3
## A hole this long has gone wrong; stop rather than loop forever.
const MAX_STROKES := 20
## Mirrors HoleView.max_over_par. Kept as its own constant because this file
## never builds a HoleView to ask.
const PICK_UP_OVER_PAR := 5
const STEP := 1.0 / 60.0

const TIER_SAMPLES := 70
const RUNS := 40

var rng := RandomNumberGenerator.new()
var deck_list: DeckList
var ball: Ball
## Who is playing. Set before any stroke is struck.
var golfer: Golfer = tour()

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
	# The cut is positional -- the bottom share of the field goes home after
	# halfway -- not the old fixed +8. DEFAULT_CUT survives only so saves and
	# readouts have a number.
	print("=== whole runs, bottom %.0f%% cut after halfway, %d attempts each ==="
		% [RunState.CUT_SHARE * 100.0, RUNS])
	print("  %-16s %8s %8s %8s %8s" % [
		"golfer", "average", "best", "worst", "cut"])
	var missed := 0
	for who in field():
		missed += _runs_for(who)
	print("")
	if missed == 0:
		print("  Nobody missed a cut. Either the field is too weak or the cut")
		print("  share is too small -- and check the run has a leaderboard at")
		print("  all, because without one the cut is never evaluated.")
	else:
		print("  A cut the best player never misses and the worst usually does")
		print("  is the shape to want. Read down the column, not across.")


## One golfer's forty runs.
##
## The seed is reset first, so every band plays the same forty routes, the same
## holes and the same shuffles. Without that the bands differ by luck as much as
## by skill and the table cannot be read down its columns.
func _runs_for(who: Golfer) -> int:
	golfer = who
	rng.seed = 20240107
	var cut := 0
	var total_score := 0
	var total_holes := 0
	var best := 99
	var worst := -99

	for attempt in RUNS:
		var run := RunState.new()
		# The tournament, exactly as main.gd sets one up. Without a leaderboard
		# RunState._missed_the_cut returns false on the first line and the cut is
		# never evaluated at all -- so this report said "0% missed the cut" for a
		# golfer averaging +11.6 against a cut at +8, and had been saying it
		# about every build ever measured. It was not reporting that the game is
		# easy. It was reporting that nothing was being checked.
		run.round_holes = MapGenerator.HOLES_PER_NINE
		run.tour = TourLibrary.by_rung(0)
		run.leaderboard = Leaderboard.new(rng.randi(),
			run.tour.field_skill_delta if run.tour != null else 0.0)
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
		worst = maxi(worst, run.score_to_par())

	print("  %-16s %+8.1f %+8d %+8d %7.0f%%" % [
		who.label, float(total_score) / RUNS, best, worst,
		100.0 * cut / RUNS])
	return cut


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
	var late := absf(rng.randfn(0.0, golfer.timing_sigma / 1000.0))
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
	power = clampf(power + rng.randf_range(-golfer.power_error, golfer.power_error), 0.02, 1.0)

	var target := _target_for(profile.max_reach_yards() * hole.pixels_per_yard)
	var aim := (_read_the_break(target) - shot_origin).normalized()
	aim = aim.rotated(deg_to_rad(rng.randf_range(-golfer.aim_error_deg, golfer.aim_error_deg)))

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
	if best < 0:
		return longest
	# Judgement, as opposed to execution. Taking one club too many or too few is
	# the amateur's real mistake, and it is a different shape of error from a
	# wobbly swing: the strike is clean and the ball is simply in the wrong place,
	# which is how greens get missed long and bunkers get found short.
	if golfer.wrong_club > 0.0 and rng.randf() < golfer.wrong_club:
		var wrong := _neighbouring_club(best, remaining)
		if wrong >= 0:
			return wrong
	return best


## The club either side of the right one, by reach. Returns -1 when the hand
## holds nothing else worth calling a mistake.
func _neighbouring_club(correct: int, remaining: float) -> int:
	var lie := hole.surface_at(ball.position)
	var reaches: Array = []
	for i in deck.hand.size():
		var card: CardData = deck.hand[i]
		if not card.is_shot():
			continue
		if lie.blocks_ground_shots and card.club != null and card.club.is_ground_shot:
			continue
		reaches.append({"slot": i, "reach": _profile_for(card).max_reach_yards()})
	if reaches.size() < 2:
		return -1
	reaches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["reach"]) < float(b["reach"]))
	var at := -1
	for i in reaches.size():
		if int(reaches[i]["slot"]) == correct:
			at = i
			break
	if at < 0:
		return -1
	# One either way, and never off the end of what is actually in hand.
	var step := 1 if rng.randf() < 0.5 else -1
	var landed := at + step
	if landed < 0 or landed >= reaches.size():
		landed = at - step
	if landed < 0 or landed >= reaches.size() or landed == at:
		return -1
	# A club so wrong it could not reach half way is not a misjudgement, it is a
	# different shot entirely, and the robot would never pull it.
	if float(reaches[landed]["reach"]) < remaining * 0.45:
		return -1
	return int(reaches[landed]["slot"])


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
