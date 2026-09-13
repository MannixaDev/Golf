## Diagnostic: probe the hole's surface map and the wind model, so hazard
## geometry can be checked without squinting at a screenshot.
extends SceneTree


func _initialize() -> void:
	var hole: HoleData = load("res://resources/holes/hole_01.tres")
	print("surfaces loaded: ", SurfaceLibrary.all_ids().size())
	print("hazard regions:  ", hole.hazards.size())
	print("wind: %s, %.1f yd/100 (%s)" % [
		hole.wind_direction, hole.wind_yards_per_100, hole.wind_description()])
	print("")

	print("=== probes ===")
	var probes := {
		"tee": hole.tee_position,
		"mid fairway": Vector2(600, 520),
		"left fairway bunker": Vector2(893, 404),
		"right fairway bunker": Vector2(826, 517),
		"water on approach": Vector2(1160, 400),
		"greenside bunker": Vector2(1288, 452),
		"green": hole.green_center,
		"in the divot": Vector2(612, 505),
		"wet patch": Vector2(430, 585),
		"deep rough north": Vector2(1010, 130),
		"way off line": Vector2(300, 200),
	}
	for label in probes:
		var surface: SurfaceType = hole.surface_at(probes[label])
		print("  %-22s -> %-11s friction %.2f  catches %s" % [
			label, surface.display_name, surface.roll_friction, surface.catches_ball])

	print("")
	print("=== playing out of trouble (9 Iron, 130 yd) ===")
	var card: CardData = CardLibrary.template(&"iron_9")
	for id in [&"fairway", &"rough", &"deep_rough", &"bunker", &"divot", &"wet_patch"]:
		var profile := ShotProfile.from_card(card)
		SurfaceLibrary.by_id(id).apply_to(profile)
		print("  %-11s carry %5.1f yd  spread %.2f  roll %.3f  putting %s" % [
			id, profile.carry_yards_max, profile.dispersion_deg, profile.roll_ratio,
			"blocked" if SurfaceLibrary.by_id(id).blocks_ground_shots else "ok"])

	print("")
	print("=== wind drift over the carry ===")
	var wind := hole.wind_vector()
	for spec in [["Driver", 250.0, 0.5], ["9 Iron", 130.0, 0.95],
			["Wedge", 95.0, 1.2], ["Punched 9 Iron", 110.0, 0.285]]:
		var drift: Vector2 = ShotResolver.wind_drift(wind, spec[1], spec[2])
		print("  %-16s carry %5.1f, arc %.2f -> %5.1f yd of drift" % [
			spec[0], spec[1], spec[2], drift.length()])
	_probe_landing_zone(hole)
	quit()


## Where do drives actually finish? Bunker placement should follow evidence
## rather than arithmetic done in my head.
func _probe_landing_zone(hole: HoleData) -> void:
	print("")
	print("=== driver landing zone, 200 tee shots ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ball: Ball = load("res://scenes/golf/ball.tscn").instantiate()
	root.add_child(ball)
	ball.configure(hole.pin_position, hole.cup_radius, hole.bounds)
	ball.sampler = SurfaceSampler.new(hole)

	var card: CardData = CardLibrary.template(&"driver")
	var counts: Dictionary = {}
	var mean := Vector2.ZERO
	var samples := 0
	var furthest := 0.0
	var furthest_at := Vector2.ZERO
	var furthest_surface := ""
	var green_examples: Array = []

	for i in 200:
		var profile := ShotProfile.from_card(card)
		hole.surface_at(hole.tee_position).apply_to(profile)
		var aim := (hole.pin_position - hole.tee_position).normalized()
		aim = aim.rotated(deg_to_rad(rng.randf_range(-1.5, 1.5)))
		var power := clampf(1.0 + rng.randf_range(-0.06, 0.06), 0.0, 1.0)
		var shot := ShotResolver.resolve(profile, power, aim, rng, hole.wind_vector())

		ball.reset_to(hole.tee_position)
		ball.launch(shot, hole.pixels_per_yard)
		var guard := 0
		while ball.is_moving() and guard < 100000:
			ball._physics_process(1.0 / 60.0)
			guard += 1

		var surface := hole.surface_at(ball.position)
		counts[surface.display_name] = counts.get(surface.display_name, 0) + 1
		mean += ball.position
		samples += 1
		var travelled := hole.to_yards(hole.tee_position.distance_to(ball.position))
		if travelled > furthest:
			furthest = travelled
			furthest_at = ball.position
			furthest_surface = surface.display_name
		if surface.display_name == "Green" and green_examples.size() < 4:
			green_examples.append("%s after %.0f yd (guard %d)" % [ball.position, travelled, guard])

	mean /= float(samples)
	print("  mean resting point: %s" % mean)
	var names: Array = counts.keys()
	names.sort()
	for name in names:
		print("    %-11s %3d  (%.0f%%)" % [name, counts[name], 100.0 * counts[name] / samples])
	print("  furthest: %.0f yd, finishing %s on %s" % [furthest, furthest_at, furthest_surface])
	for example in green_examples:
		print("    reached green: %s" % example)
	ball.queue_free()
