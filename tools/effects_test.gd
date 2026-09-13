## Verifies Milestone 3's card effects actually do what their rules text claims.
##
## Profile maths and instant effects are checked synchronously; the curved flight
## and the out-of-bounds save need the ball to actually fly, so those run as a
## small sequence of scenarios.
extends SceneTree

const PPY := 3.0

var hole: HoleData
var ball: Ball
var scenarios: Array = []
var current: Dictionary = {}
var start_position := Vector2.ZERO
var settled := false
var went_ob := false
var was_saved := false
## Members, not locals: a GDScript lambda captures locals by value, so a handler
## writing to a local flag updates its own copy and the test always reads false.
var water_lost := false
var water_rescued := false
var failures := 0


func _initialize() -> void:
	hole = load("res://resources/holes/hole_01.tres")
	_test_profiles()
	_test_instant_effects()

	ball = load("res://scenes/golf/ball.tscn").instantiate()
	root.add_child(ball)
	ball.configure(hole.pin_position, hole.cup_radius, hole.bounds)
	ball.came_to_rest.connect(func(_p: Vector2) -> void: settled = true)
	ball.went_out_of_bounds.connect(func(_p: Vector2) -> void:
		went_ob = true
		settled = true)
	ball.saved_from_trouble.connect(func() -> void: was_saved = true)

	print("")
	print("=== flight shape ===")
	scenarios = [
		{"name": "straight 5 Iron", "card": &"iron_5", "tech": [], "expect": "no drift"},
		{"name": "with Draw", "card": &"iron_5", "tech": [&"draw"], "expect": "left"},
		{"name": "with Fade", "card": &"iron_5", "tech": [&"fade"], "expect": "right"},
	]
	_next_scenario()


# --- Profile maths --------------------------------------------------------

func _test_profiles() -> void:
	print("=== technique effects on a 5 Iron ===")
	var base := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	_print_profile("plain", base)

	for id in [&"draw", &"fade", &"punch", &"full_send", &"ball_retriever"]:
		var profile := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
		profile.apply_effects(CardLibrary.template(id).shot_modifiers())
		_print_profile(str(id), profile)

	# Techniques must stack, not overwrite each other.
	var stacked := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	stacked.apply_effects(CardLibrary.template(&"punch").shot_modifiers())
	stacked.apply_effects(CardLibrary.template(&"full_send").shot_modifiers())
	_print_profile("punch+full_send", stacked)
	_expect(stacked.carry_yards_max > base.carry_yards_max * 1.0,
		"stacked punch+full send should still gain distance")
	_expect(stacked.roll_ratio > base.roll_ratio * 1.5,
		"stacked punch should keep its extra run")


func _print_profile(label: String, p: ShotProfile) -> void:
	print("  %-16s carry %6.1f  roll %.3f  spread %.2f  arc %.2f  curve %+.1f  protects %s" % [
		label, p.carry_yards_max, p.roll_ratio, p.dispersion_deg,
		p.arc_factor, p.curve_deg, p.protects_ball])


# --- Instant effects ------------------------------------------------------

func _test_instant_effects() -> void:
	print("")
	print("=== instant effects ===")

	# Mulligan on the tee: nothing to take back.
	var tee_ctx := _context(Vector2(170, 640), false)
	_play(&"mulligan", tee_ctx)
	_expect(tee_ctx.is_rejected(), "mulligan on the tee should be refused")
	print("  mulligan (no stroke yet): refused -- %s" % tee_ctx.rejection_reason())

	# Mulligan after a stroke: rewind and refund.
	var played_ctx := _context(Vector2(900, 500), true)
	played_ctx.last_shot_origin = Vector2(170, 640)
	played_ctx.strokes = 2
	_play(&"mulligan", played_ctx)
	_expect(not played_ctx.is_rejected(), "mulligan after a stroke should work")
	_expect(played_ctx.stroke_delta == -1, "mulligan should refund exactly one stroke")
	_expect(played_ctx.move_ball_to == Vector2(170, 640), "mulligan should rewind to the origin")
	print("  mulligan (after a stroke): ball -> %s, strokes %+d" % [
		played_ctx.move_ball_to, played_ctx.stroke_delta])

	# Foot wedge from range: shuffles the ball forward.
	var far_ctx := _context(hole.pin_position - Vector2(300, 0), true)
	_play(&"foot_wedge", far_ctx)
	var gained: float = far_ctx.yards_to_pin() \
		- (far_ctx.move_ball_to as Vector2).distance_to(hole.pin_position) / PPY
	_expect(not far_ctx.is_rejected(), "foot wedge at range should work")
	_expect(absf(gained - 10.0) < 0.01, "foot wedge should gain its stated 10 yards")
	print("  foot wedge (100 yd out): gained %.1f yards, no stroke" % gained)

	# Foot wedge from a tap-in: refused, so it cannot walk the ball in.
	var near_ctx := _context(hole.pin_position - Vector2(9, 0), true)
	_play(&"foot_wedge", near_ctx)
	_expect(near_ctx.is_rejected(), "foot wedge from 3 yards should be refused")
	print("  foot wedge (3 yd out): refused -- %s" % near_ctx.rejection_reason())


func _context(ball_pos: Vector2, can_rewind: bool) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.ball_position = ball_pos
	ctx.pin_position = hole.pin_position
	ctx.last_shot_origin = ball_pos
	ctx.can_rewind = can_rewind
	ctx.pixels_per_yard = PPY
	return ctx


func _play(id: StringName, ctx: EffectContext) -> void:
	for effect in CardLibrary.template(id).active_effects():
		effect.on_play(ctx)
		if ctx.is_rejected():
			return


# --- Flight scenarios -----------------------------------------------------

func _next_scenario() -> void:
	if scenarios.is_empty():
		_test_ob_save()
		return

	current = scenarios.pop_front()
	var profile := ShotProfile.from_card(CardLibrary.template(current["card"]))
	for tech in current["tech"]:
		profile.apply_effects(CardLibrary.template(tech).shot_modifiers())

	# Hand-built so there is no dispersion noise: we are measuring shape only.
	var shot := ShotResult.new()
	shot.profile = profile
	shot.direction = Vector2.RIGHT
	shot.carry_yards = profile.carry_yards_max
	shot.roll_yards = profile.carry_yards_max * profile.roll_ratio
	shot.arc_factor = profile.arc_factor
	shot.curve_offset_yards = tan(deg_to_rad(profile.curve_deg)) * shot.carry_yards

	start_position = Vector2(200, 450)
	ball.reset_to(start_position)
	settled = false
	ball.launch(shot, PPY)


func _process(_delta: float) -> bool:
	if not settled or current.is_empty():
		return false

	var drift_yards := (ball.position.y - start_position.y) / PPY
	var travelled := (ball.position.x - start_position.x) / PPY
	# Screen y grows downward, so a positive drift is right of the line.
	var shape := "straight"
	if drift_yards < -1.0:
		shape = "left"
	elif drift_yards > 1.0:
		shape = "right"

	print("  %-18s %5.0f yd down the line, %+6.1f yd sideways -> %s" % [
		current["name"], travelled, drift_yards, shape])

	var expected: String = current["expect"]
	if expected == "no drift":
		_expect(absf(drift_yards) < 1.0, "a plain shot should not drift")
	else:
		_expect(shape == expected, "%s should shape %s" % [current["name"], expected])

	current = {}
	_next_scenario()
	return false


# --- Out of bounds protection --------------------------------------------

func _test_ob_save() -> void:
	print("")
	print("=== ball retriever ===")

	var near_edge := Vector2(hole.bounds.end.x - 60.0, 450.0)
	var profile := ShotProfile.from_card(CardLibrary.template(&"iron_5"))

	for protected in [false, true]:
		if protected:
			profile.apply_effects(CardLibrary.template(&"ball_retriever").shot_modifiers())

		var shot := ShotResult.new()
		shot.profile = profile
		shot.direction = Vector2.RIGHT
		shot.carry_yards = 100.0
		shot.roll_yards = 0.0
		shot.arc_factor = 1.0
		shot.protects_ball = profile.protects_ball

		went_ob = false
		was_saved = false
		settled = false
		ball.reset_to(near_edge)
		ball.launch(shot, PPY)

		# Drive the ball to completion without waiting on frames.
		var guard := 0
		while not settled and guard < 100000:
			ball._physics_process(1.0 / 60.0)
			guard += 1

		var inside: bool = hole.bounds.has_point(ball.position)
		print("  protected=%-5s  went OB: %-5s  saved: %-5s  finished inside: %s" % [
			protected, went_ob, was_saved, inside])
		if protected:
			_expect(not went_ob and was_saved and inside,
				"a protected stroke should stop at the boundary")
		else:
			_expect(went_ob, "an unprotected stroke should go out of bounds")

	_test_water_rescue()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## The card is only worth holding if it saves you from water, which is common,
## rather than only from out of bounds, which is rare.
func _test_water_rescue() -> void:
	print("")
	print("=== bawl grabbur vs water ===")

	# A pond straight down the line, with dry land in front of it.
	var pond := HazardRegion.new()
	pond.surface_id = &"water"
	pond.shape = HazardRegion.Shape.CIRCLE
	pond.centre = Vector2(600, 450)
	pond.radius = 90.0
	var pond_hole: HoleData = load("res://resources/holes/hole_01.tres").duplicate()
	pond_hole.hazards = [pond] as Array[HazardRegion]
	ball.configure(pond_hole.pin_position, pond_hole.cup_radius, pond_hole.bounds)
	ball.sampler = SurfaceSampler.new(pond_hole)

	for protected in [false, true]:
		var profile := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
		if protected:
			profile.apply_effects(CardLibrary.template(&"ball_retriever").shot_modifiers())

		var shot := ShotResult.new()
		shot.profile = profile
		shot.direction = Vector2.RIGHT
		shot.carry_yards = 100.0
		shot.roll_yards = 0.0
		shot.arc_factor = 1.0
		shot.protects_ball = profile.protects_ball

		water_lost = false
		water_rescued = false
		settled = false
		var on_caught := func(_p: Vector2) -> void:
			water_lost = true
			settled = true
		var on_saved := func() -> void: water_rescued = true
		ball.caught_by_hazard.connect(on_caught)
		ball.saved_from_trouble.connect(on_saved)

		ball.reset_to(Vector2(300, 450))
		ball.launch(shot, PPY)
		var guard := 0
		while not settled and guard < 100000:
			ball._physics_process(1.0 / 60.0)
			guard += 1

		ball.caught_by_hazard.disconnect(on_caught)
		ball.saved_from_trouble.disconnect(on_saved)

		var dry: bool = not pond_hole.surface_at(ball.position).catches_ball
		print("  protected=%-5s  lost: %-5s  rescued: %-5s  finished dry: %s" % [
			protected, water_lost, water_rescued, dry])
		if protected:
			_expect(not water_lost and water_rescued and dry,
				"a protected stroke should be fished out of the water")
		else:
			_expect(water_lost, "an unprotected stroke should be lost in the water")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
