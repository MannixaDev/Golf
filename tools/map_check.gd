## Diagnostic: generate maps and holes and prove they are actually traversable.
##
## The important assertions are structural: every node must be reachable from the
## first tee, every node must lead somewhere, and every generated hole must have a
## tee that is playable and a cup that is not underwater.
extends SceneTree

const MAPS := 60
const HOLES := 500

var failures := 0


func _initialize() -> void:
	_check_maps()
	_check_holes()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


# --- Maps -----------------------------------------------------------------

func _check_maps() -> void:
	print("=== map structure, %d generated ===" % MAPS)
	var type_counts: Dictionary = {}
	var total_nodes := 0
	var total_choices := 0
	var choice_samples := 0

	for i in MAPS:
		var map := MapGenerator.generate(1000 + i)
		total_nodes += map.nodes.size()

		# Columns are derived from the hole count now, not fixed.
		var expected := MapGenerator.layer_kinds(MapGenerator.HOLES_PER_NINE).size()
		_expect(map.layers.size() == expected,
			"a nine should lay out %d columns" % expected)
		_expect(map.layers[map.layers.size() - 1].size() == 1,
			"the run should end at a single closing hole")

		# Every node must be reachable walking forward from the first column.
		var reached := {}
		var queue: Array = []
		for id in map.layers[0]:
			queue.append(id)
			reached[id] = true
		while not queue.is_empty():
			var node: MapNode = map.node_by_id(queue.pop_front())
			for next_id in node.next_ids:
				if not reached.has(next_id):
					reached[next_id] = true
					queue.append(next_id)
		_expect(reached.size() == map.nodes.size(),
			"every node should be reachable (%d of %d)" % [reached.size(), map.nodes.size()])

		var last_layer := map.layers.size() - 1
		for node in map.nodes:
			_expect(node.spec != null, "every node should have a spec")
			if node.layer < last_layer:
				_expect(not node.next_ids.is_empty(),
					"node on column %d should lead somewhere" % node.layer)
			if node.spec != null:
				type_counts[node.spec.id] = int(type_counts.get(node.spec.id, 0)) + 1

		# Walk a route and count how many choices the player actually gets.
		map.begin()
		var guard := 0
		while not map.available_ids().is_empty() and guard < 50:
			var options := map.available_ids()
			if guard < map.layers.size() - 2:
				total_choices += options.size()
				choice_samples += 1
			map.travel_to(options[0])
			guard += 1
		_expect(guard == map.layers.size(),
			"a route should be exactly %d stops long, walked %d" % [map.layers.size(), guard])

	print("  nodes per map: %.1f" % (float(total_nodes) / MAPS))
	print("  choices per stop (open stretch): %.2f" % (float(total_choices) / maxf(choice_samples, 1)))
	var ids: Array = type_counts.keys()
	ids.sort()
	for id in ids:
		print("    %-16s %4d  (%.0f%%)" % [
			id, type_counts[id], 100.0 * type_counts[id] / total_nodes])


# --- Holes ----------------------------------------------------------------

func _check_holes() -> void:
	var shape_ratios := 0.0
	print("")
	print("=== generated holes, %d per tier ===" % (HOLES / 5))
	for tier in 5:
		var pars: Dictionary = {}
		var lengths := 0.0
		var hazards := 0
		var winds := 0.0

		for i in HOLES / 5:
			var hole := HoleGenerator.generate(7000 + tier * 500 + i, tier, i + 1)
			pars[hole.par] = int(pars.get(hole.par, 0)) + 1
			lengths += hole.hole_length_yards()
			hazards += hole.hazards.size()
			winds += hole.wind_yards_per_100

			# Fairness: you must be able to stand on the tee and see a cup.
			var tee_surface := hole.surface_at(hole.tee_position)
			_expect(not tee_surface.catches_ball,
				"tier %d: the tee should never be in water" % tier)
			_expect(not tee_surface.blocks_ground_shots,
				"tier %d: the tee should never be in sand" % tier)
			var pin_surface := hole.surface_at(hole.pin_position)
			_expect(not pin_surface.catches_ball,
				"tier %d: the cup should never be underwater" % tier)
			_expect(hole.bounds.has_point(hole.tee_position)
					and hole.bounds.has_point(hole.pin_position),
				"tier %d: tee and pin should be in bounds" % tier)
			_expect(hole.fairway_polygon.size() >= 4,
				"tier %d: the fairway should be a real band" % tier)
			_expect(hole.hole_length_yards() > 100.0,
				"tier %d: holes should not be absurdly short" % tier)

			# The putting surface has to be puttable, and it has to be puttable
			# all the way to its edge. Probing a fixed fraction of the nominal
			# radius stopped being good enough the moment greens became shapes:
			# it only ever looked at a circle inside the real green and would
			# have missed a bunker biting into a lobe entirely.
			#
			# So the probes come from the green's own outline, walked in from
			# every vertex, which covers the corners a circle never reaches.
			# The hole has to be inside its own boundary. Out of bounds is a
			# generated shape now, so "the tee is out of bounds" is a thing that
			# can happen to a whole hole rather than to one bad shot.
			_expect(hole.is_in_bounds(hole.tee_position),
				"tier %d: the tee of %s is out of bounds" % [tier, hole.hole_name])
			_expect(hole.is_in_bounds(hole.pin_position),
				"tier %d: the pin of %s is out of bounds" % [tier, hole.hole_name])
			for point in hole.fairway_polygon:
				if not hole.is_in_bounds(point):
					_expect(false, "tier %d: the fairway of %s leaves the hole"
						% [tier, hole.hole_name])
					break
			for point in hole.green_polygon:
				if not hole.is_in_bounds(point):
					_expect(false, "tier %d: the green of %s leaves the hole"
						% [tier, hole.hole_name])
					break

			# A canopy is in the air; sand and water are cut into the ground.
			# One growing through the other is not a hazard, it is two hazards
			# rolled on top of each other, and it looked exactly like that.
			var tangled := _canopy_over_ground(hole)
			if tangled != "":
				_expect(false, "tier %d: %s on %s" % [tier, tangled, hole.hole_name])

			if not _green_is_clean(hole):
				_expect(false, "tier %d: trouble on the green of %s" % [
					tier, hole.hole_name])

			shape_ratios += _green_shape_ratio(hole)

		var par_text: PackedStringArray = PackedStringArray()
		var keys: Array = pars.keys()
		keys.sort()
		for par in keys:
			par_text.append("par %d x%d" % [par, pars[par]])
		print("  tier %d: %-28s avg %3.0f yd, %.1f hazards, wind %.1f" % [
			tier, ", ".join(par_text), lengths / (HOLES / 5),
			float(hazards) / (HOLES / 5), winds / (HOLES / 5)])

	# Every green was a circle until this pass, which made every approach the
	# same approach. One means a coin.
	var spread := shape_ratios / HOLES
	print("  greens reach %.2fx further one way than the other, on average" % spread)
	_expect(spread > 1.15, "greens should not all be circles")


## Trees standing in sand or water, which cannot be a real feature and reads as
## a generator accident.
func _canopy_over_ground(hole: HoleData) -> String:
	for tree in hole.hazards:
		if tree == null or tree.surface().style != SurfaceType.Style.FOLIAGE:
			continue
		for other in hole.hazards:
			if other == null or other == tree:
				continue
			var style := other.surface().style
			if style != SurfaceType.Style.SAND and style != SurfaceType.Style.WATER:
				continue
			if tree.centre.distance_to(other.centre) < tree.radius + other.radius:
				return "a tree growing out of the %s" % other.surface().display_name
	return ""


## Every point on the putting surface has to actually be putting surface.
## Walked in from the outline rather than sampled in a ring, so a hazard cutting
## into one lobe of an irregular green cannot hide between two probes.
func _green_is_clean(hole: HoleData) -> bool:
	var outline := hole.green_polygon
	if outline.size() < 3:
		return true
	for vertex in outline:
		for inset in [0.97, 0.80, 0.55, 0.25]:
			var probe: Vector2 = hole.green_center 				+ (vertex - hole.green_center) * inset
			var surface := hole.surface_at(probe)
			if surface.catches_ball or surface.blocks_ground_shots:
				return false
	return true


## How far from circular this green is: its widest reach over its narrowest.
## One means a coin, which is what every green used to be.
func _green_shape_ratio(hole: HoleData) -> float:
	var widest := 0.0
	var narrowest := INF
	for step in 24:
		var reach := hole.green_reach(Vector2.RIGHT.rotated(TAU * float(step) / 24.0))
		widest = maxf(widest, reach)
		narrowest = minf(narrowest, reach)
	return widest / maxf(narrowest, 0.001)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		if failures < 12:
			print("  FAIL: %s" % what)
