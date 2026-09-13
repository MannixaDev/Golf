## Builds a branching route across the course.
##
## The shape comes from walking several paths from the first tee to the closing
## hole, each step only ever moving to a node roughly opposite it in the next
## column. That guarantees the route is connected and fully playable, keeps the
## lines from crossing into spaghetti, and still produces real branches and
## merges. Nodes nothing reaches are pruned afterwards.
class_name MapGenerator
extends RefCounted

const LIBRARY_PATH := "res://resources/map_nodes"

## Holes in a round. A nine is a nine, the way it is on a real card.
##
## This used to be a column count with golf and services alternating, which
## worked out at seven holes -- a number nothing in golf has ever cared about.
## The round is now specified in holes and the columns are derived from it.
const HOLES_PER_NINE := 9
## Golf stops between service stops. Two holes then a breather keeps the run
## about golf rather than about shopping, and lands a nine at thirteen columns,
## which is what the map can draw legibly.
const HOLES_BETWEEN_SERVICES := 2
const MIN_PER_LAYER := 2
const MAX_PER_LAYER := 4
const OPENING_LAYER_SIZE := 3
## Walks carved from the first tee to the closing hole. Tuned by measurement:
## this lands at ~1.9 live choices per stop, which branches without becoming a
## mesh where every route is the same.
const PATH_COUNT := 12
## How far apart two nodes may sit vertically, in pixels, and still connect.
## Judged on where they actually end up rather than on their slot index, because
## columns hold different numbers of nodes and the player only sees the drawing.
const MAX_STEP_Y := 250.0

# Map pixel layout.
const MARGIN_X := 150.0
const MARGIN_Y := 160.0
const USABLE_WIDTH := 1300.0
## Leaves room under the lowest row for its label and the information panel.
const USABLE_HEIGHT := 470.0
const JITTER := 16.0

static var _specs: Dictionary = {}
static var _loaded: bool = false


static func ensure_specs_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(LIBRARY_PATH):
		if res is MapNodeSpec:
			_specs[res.id] = res
		else:
			push_warning("MapGenerator: %s is not a MapNodeSpec" % res.resource_path)


static func spec(id: StringName) -> MapNodeSpec:
	ensure_specs_loaded()
	return _specs.get(id)


## The shape of one round, column by column: true is golf, false is a service
## stop. Derived from the hole count so a nine and an eighteen are the same code
## rather than two hand-laid tables.
##
## The last column is always golf -- that is the closing hole -- and the one
## before it always a service stop, so there is a breather before the close.
static func layer_kinds(holes: int) -> Array[bool]:
	var kinds: Array[bool] = []
	for i in holes:
		kinds.append(true)
		if i == holes - 1:
			continue
		# A service stop every couple of holes, and always one immediately before
		# the close whether the rhythm calls for it or not -- walking straight
		# from an ordinary hole into the closing hole gives you nowhere to
		# prepare for it.
		var on_rhythm := (i + 1) % HOLES_BETWEEN_SERVICES == 0
		if on_rhythm or i == holes - 2:
			kinds.append(false)
	return kinds


static func generate(map_seed: int, holes: int = HOLES_PER_NINE) -> RunMap:
	ensure_specs_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	var map := RunMap.new()
	map.kinds = layer_kinds(holes)
	_build_columns(map, rng)
	# Position before carving: connections are chosen by how close two nodes
	# actually sit, which is the only thing that makes the route readable.
	_position_nodes(map, rng)
	_carve_paths(map, rng)
	_prune_unreachable(map)
	_assign_specs(map, rng)

	for node in map.nodes:
		node.hole_seed = rng.randi()

	map.begin()
	return map


# --- Structure ------------------------------------------------------------

static func _build_columns(map: RunMap, rng: RandomNumberGenerator) -> void:
	var layers := map.kinds.size()
	for layer in layers:
		var count := rng.randi_range(MIN_PER_LAYER, MAX_PER_LAYER)
		if layer == 0:
			count = OPENING_LAYER_SIZE
		elif layer == layers - 1:
			count = 1  # the closing hole is always a single destination

		var ids: Array = []
		for slot in count:
			var node := MapNode.new()
			node.id = map.nodes.size()
			node.layer = layer
			node.slot = slot
			node.offset = 0.5 if count == 1 else float(slot) / float(count - 1)
			map.nodes.append(node)
			ids.append(node.id)
		map.layers.append(ids)


static func _carve_paths(map: RunMap, rng: RandomNumberGenerator) -> void:
	for path in PATH_COUNT:
		var current: MapNode = map.node_by_id(
			map.layers[0][rng.randi_range(0, map.layers[0].size() - 1)])

		for layer in range(1, map.kinds.size()):
			var next := _pick_step(map, current, layer, rng)
			if next == null:
				break
			if not current.next_ids.has(next.id):
				current.next_ids.append(next.id)
				next.previous_ids.append(current.id)
			current = next


## Choose a node in the next column that sits roughly opposite this one, so the
## route reads as a route rather than a tangle.
static func _pick_step(map: RunMap, from: MapNode, layer: int,
		rng: RandomNumberGenerator) -> MapNode:
	var candidates: Array[MapNode] = []
	var nearest: MapNode = null
	var nearest_gap := INF

	for id in map.layers[layer]:
		var node: MapNode = map.node_by_id(id)
		var gap: float = absf(node.position.y - from.position.y)
		if gap <= MAX_STEP_Y:
			candidates.append(node)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = node

	if candidates.is_empty():
		return nearest
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Anything the walks never touched would be an island, so drop it.
static func _prune_unreachable(map: RunMap) -> void:
	var keep: Array[MapNode] = []
	for node in map.nodes:
		var is_opening := node.layer == 0
		var connected := not node.next_ids.is_empty() or not node.previous_ids.is_empty()
		if connected or (is_opening and not node.next_ids.is_empty()):
			keep.append(node)

	# Ids are indices, so renumber and repair every reference.
	var remap: Dictionary = {}
	for i in keep.size():
		remap[keep[i].id] = i

	for node in keep:
		node.next_ids = _remapped(node.next_ids, remap)
		node.previous_ids = _remapped(node.previous_ids, remap)
	for i in keep.size():
		keep[i].id = i

	map.nodes = keep
	var rebuilt: Array = []
	for layer in map.layers:
		var ids: Array = []
		for old_id in layer:
			if remap.has(old_id):
				ids.append(remap[old_id])
		rebuilt.append(ids)
	map.layers = rebuilt


static func _remapped(ids: Array[int], remap: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for id in ids:
		if remap.has(id):
			result.append(remap[id])
	return result


# --- Content --------------------------------------------------------------

## Which columns are golf is fixed by the round's shape, not rolled.
##
## Stop kinds used to come from one weighted pool, which meant no route was
## guaranteed any golf at all. Measured across 400 maps, a player picking their
## way through the shops could reach the closing hole having played as few as
## **two** holes -- and because a rest took strokes off the card, dodging the
## game paid twice over.
##
## Now every route through a map contains exactly the round's hole count, so
## choosing a route is about *which* golf you take on, never whether you take
## any. `tools/route_check.gd` asserts it.
static func _assign_specs(map: RunMap, rng: RandomNumberGenerator) -> void:
	var last_layer := map.layers.size() - 1
	var used: Dictionary = {}

	for layer_index in map.layers.size():
		for id in map.layers[layer_index]:
			var node: MapNode = map.node_by_id(id)

			if layer_index == last_layer:
				node.spec = spec(&"boss_hole")
				continue
			if layer_index == 0:
				# Open on ordinary golf so the first choice is never a gamble.
				node.spec = spec(&"hole")
				continue
			if layer_index == last_layer - 1:
				# A breather before the closing hole, always.
				node.spec = spec(&"halfway_house")
				continue

			node.spec = _weighted_pick(map, node, layer_index, used, rng,
				map.kinds[layer_index])
			used[node.spec.id] = int(used.get(node.spec.id, 0)) + 1


## `want_golf` picks which half of the library this column draws from, so a golf
## column still chooses between ordinary, tough and championship holes, and a
## service column still chooses between shops, ranges, events and the rest.
static func _weighted_pick(map: RunMap, node: MapNode, layer: int,
		used: Dictionary, rng: RandomNumberGenerator,
		want_golf: bool) -> MapNodeSpec:
	var pool: Array[MapNodeSpec] = []
	var weights: Array[float] = []
	var total := 0.0

	for id in _specs:
		var candidate: MapNodeSpec = _specs[id]
		if candidate.weight <= 0.0:
			continue
		if candidate.plays_hole != want_golf:
			continue
		if layer < candidate.min_layer:
			continue
		if candidate.max_layer >= 0 and layer > candidate.max_layer:
			continue
		if candidate.max_per_run > 0 \
				and int(used.get(candidate.id, 0)) >= candidate.max_per_run:
			continue
		if candidate.avoid_repeat and _follows_same_kind(map, node, candidate.id):
			continue
		pool.append(candidate)
		weights.append(candidate.weight)
		total += candidate.weight

	if pool.is_empty():
		return spec(&"hole") if want_golf else spec(&"event")

	var roll := rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


## Avoid putting two of the same stop back to back on a single route, which
## reads as a generator bug even when it is only luck.
static func _follows_same_kind(map: RunMap, node: MapNode, id: StringName) -> bool:
	for previous_id in node.previous_ids:
		var previous: MapNode = map.node_by_id(previous_id)
		if previous != null and previous.spec != null and previous.spec.id == id:
			return true
	return false


# --- Layout ---------------------------------------------------------------

static func _position_nodes(map: RunMap, rng: RandomNumberGenerator) -> void:
	var columns := map.layers.size()
	for layer_index in columns:
		var ids: Array = map.layers[layer_index]
		var x := MARGIN_X + USABLE_WIDTH * (float(layer_index) / float(maxi(columns - 1, 1)))
		for slot in ids.size():
			var node: MapNode = map.node_by_id(ids[slot])
			var y := MARGIN_Y + USABLE_HEIGHT * 0.5
			if ids.size() > 1:
				y = MARGIN_Y + USABLE_HEIGHT * (float(slot) / float(ids.size() - 1))
			# A little scatter so the route looks walked rather than plotted.
			node.position = Vector2(
				x + rng.randf_range(-JITTER, JITTER),
				y + rng.randf_range(-JITTER, JITTER))
