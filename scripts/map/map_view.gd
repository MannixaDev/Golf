## Draws the route and lets the player choose where to go next.
##
## Everything is drawn with primitives from the node specs, so a new kind of stop
## needs no art and no code here -- it arrives with its own colour and shape.
class_name MapView
extends Control

signal node_chosen(id: int)
signal node_hovered(node: MapNode)

const NODE_RADIUS := 24.0
const HIT_RADIUS := 34.0
const LABEL_OFFSET := 40.0

## Routes are drawn as paths worn across a course rather than as graph edges: a
## pale track underneath and a thinner line on top of it. A map that looks like a
## node diagram tells the player they are reading a flowchart; the same
## information drawn as ground tells them they are walking a golf course.
const PATH_LOCKED := Color(0.949, 0.961, 0.925, 0.07)
const PATH_OPEN := Color(0.941, 0.784, 0.376, 0.62)
const PATH_WALKED := Color(0.902, 0.878, 0.784, 0.55)
const COL_LOCKED := Color(0.26, 0.33, 0.26, 0.72)
const COL_TEXT := Color(0.949, 0.961, 0.925, 0.78)
## Ground under the route. Its own turf rather than the course's, because a map
## is a drawing of a course and should not pretend to be one.
const GROUND_GRAIN_SCALE := 420.0
const GROUND_MOTTLE_SCALE := 1250.0

## How long the whole route takes to draw itself in, and how much of that is
## the stagger from left to right.
const REVEAL_TIME := 0.55
const REVEAL_STAGGER := 0.4

var map: RunMap = null
var _hovered_id: int = -1
var _pulse: float = 0.0
## Counts up once when the route appears, so the map draws itself in column by
## column rather than snapping into existence.
var _reveal: float = 0.0


func _ready() -> void:
	# Grain is tiled over the whole map, which needs UVs past 0..1 to wrap.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_map(new_map: RunMap) -> void:
	map = new_map
	if map != null and not map.changed.is_connected(_on_map_changed):
		map.changed.connect(_on_map_changed)
	_reveal = 0.0
	queue_redraw()


func _on_map_changed() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	# Only the available nodes pulse, so the eye goes straight to the choice.
	_pulse = fmod(_pulse + delta * 2.2, TAU)
	if _reveal < 1.0:
		_reveal = minf(1.0, _reveal + delta / REVEAL_TIME)
	queue_redraw()


## 0 to 1 for a single node, staggered by how far along the route it sits.
func _reveal_of(node: MapNode) -> float:
	if map.layer_count() <= 1:
		return _reveal
	var along := float(node.layer) / float(map.layer_count() - 1)
	var start := along * REVEAL_STAGGER
	return clampf((_reveal - start) / maxf(1.0 - REVEAL_STAGGER, 0.01), 0.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return

	if event is InputEventMouseMotion:
		var found := _node_at(event.position)
		var id := found.id if found != null else -1
		if id != _hovered_id:
			if found != null and map.is_available(id):
				Sfx.play(&"select", -14.0, 0.03)
			_hovered_id = id
			node_hovered.emit(found)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var found := _node_at(event.position)
		if found != null and map.is_available(found.id):
			Sfx.play(&"whoosh", -3.0)
			_reveal = 1.0
			node_chosen.emit(found.id)
			accept_event()


func _node_at(point: Vector2) -> MapNode:
	if map == null:
		return null
	for node in map.nodes:
		if node.position.distance_to(point) <= HIT_RADIUS:
			return node
	return null


# --- Drawing --------------------------------------------------------------

func _draw() -> void:
	if map == null:
		return
	_draw_edges()
	_draw_start_marker()
	for node in map.nodes:
		_draw_node(node)


func _draw_edges() -> void:
	# Two passes: every track laid down first, then the live ones over the top,
	# so an open route is never half-buried under a locked one crossing it.
	for live in [false, true]:
		for node in map.nodes:
			for next_id in node.next_ids:
				var next := map.node_by_id(next_id)
				if next == null:
					continue
				var walked := node.state == MapNode.State.VISITED \
					and next.state == MapNode.State.VISITED
				var open := node.id == map.current_id and map.is_available(next_id)
				if (walked or open) != live:
					continue
				_draw_path(node.position, next.position, walked, open)


## One route between two stops. A soft worn track underneath and a firmer line
## on top: it is the track that makes it read as ground rather than as a wire.
func _draw_path(from: Vector2, to: Vector2, walked: bool, open: bool) -> void:
	var colour := PATH_LOCKED
	var width := 2.0
	var track := 0.0
	if walked:
		colour = PATH_WALKED
		width = 3.0
		track = 9.0
	elif open:
		colour = PATH_OPEN
		width = 2.5
		track = 8.0

	if track > 0.0:
		draw_line(from, to, Color(colour, 0.13), track, true)
	draw_line(from, to, colour, width, true)


## The map is read at a glance and hovered over, so its ground carries about
## half the grain a hole does -- enough to stop it being flat, not enough to
## compete with the route drawn on top of it.
func _grain(rect: Rect2, texture: Texture2D, scale: float,
		strength: float = 0.5) -> void:
	if texture == null or scale <= 0.0:
		return
	var points := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(point / scale)
	draw_colored_polygon(points, Color(1.0, 1.0, 1.0, strength), uvs, texture)


## A tee marker off to the left, with lines into the opening column, so the run
## reads as starting somewhere rather than floating.
func _draw_start_marker() -> void:
	if map.layers.is_empty():
		return
	var anchor := Vector2(70.0, size.y * 0.5)
	var started := map.current_id != -1
	for id in map.layers[0]:
		var node := map.node_by_id(id)
		_draw_path(anchor, node.position, false, not started)

	# The first tee, drawn as one: the same marker pair you stand between on a
	# hole, so the map opens with something the player already recognises.
	var box := Rect2(anchor - Vector2(17.0, 10.0), Vector2(34.0, 20.0))
	draw_rect(Rect2(box.position + Palette.shadow_offset(3.0), box.size),
		Color(Palette.SHADOW, 0.45))
	draw_rect(box, Palette.TEE)
	draw_rect(box, Color(1.0, 0.98, 0.88, 0.25), false, 1.5)
	for side in [-1.0, 1.0]:
		draw_circle(box.get_center() + Vector2(10.0 * side, 0.0), 2.5,
			Color(0.94, 0.95, 0.90))

	var font := Typo.SEMIBOLD
	if font != null:
		draw_string(font, anchor + Vector2(-26.0, 34.0), "FIRST TEE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, Typo.SMALL, COL_TEXT)


func _draw_node(node: MapNode) -> void:
	var spec := node.spec
	if spec == null:
		return

	var available := map.is_available(node.id)
	var visited := node.state == MapNode.State.VISITED
	var current := node.id == map.current_id

	var colour: Color = spec.colour
	if not available and not visited:
		colour = COL_LOCKED
	elif visited:
		colour = spec.colour.darkened(0.35)

	# The node the player is standing on, and everything they may pick next.
	if current:
		draw_arc(node.position, NODE_RADIUS + 9.0, 0.0, TAU, 40,
			Color(Palette.INK, 0.85), 3.0, true)
	elif available:
		var swell := 4.0 + sin(_pulse) * 3.0
		draw_arc(node.position, NODE_RADIUS + swell, 0.0, TAU, 40,
			Color(Palette.GOLD, 0.60), 2.5, true)
		# A soft halo underneath, so a live choice glows rather than just rings.
		draw_circle(node.position, NODE_RADIUS + swell + 6.0,
			Color(Palette.GOLD, 0.06))

	var hovered := node.id == _hovered_id
	var radius := NODE_RADIUS + (3.0 if hovered and available else 0.0)
	# Overshoot slightly on the way in, so a stop lands rather than appears.
	var grown := _reveal_of(node)
	if grown <= 0.01:
		return
	radius *= 1.0 + sin(grown * PI) * 0.18
	radius *= grown

	var points := _shape_points(spec.shape, node.position, radius)
	# Same sun as the course, so a stop reads as a marker standing on the map
	# rather than a shape floating over it.
	var shadow := _shape_points(spec.shape,
		node.position + Palette.shadow_offset(5.0), radius)
	draw_colored_polygon(shadow, Color(Palette.SHADOW, 0.45))

	draw_colored_polygon(points, colour)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, colour.lightened(0.4), 2.0, true)
	# A crescent of light along the sun side, which is what stops a flat polygon
	# reading as a sticker.
	var lit := _shape_points(spec.shape,
		node.position - Palette.SUN * radius * 0.16, radius * 0.74)
	draw_colored_polygon(lit, Color(1.0, 0.98, 0.86, 0.10))

	var font := Typo.SEMIBOLD
	if font == null:
		return
	var label_colour := COL_TEXT if (available or visited) else Color(Palette.INK, 0.32)
	label_colour.a *= grown
	var label_size := font.get_string_size(spec.short_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Typo.SMALL)
	var at := node.position + Vector2(-label_size.x * 0.5, LABEL_OFFSET)
	# Labels sit over textured ground now, so they need their own shadow to stay
	# readable wherever they land.
	draw_string(font, at + Vector2(1.0, 1.0), spec.short_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Typo.SMALL,
		Color(0.0, 0.0, 0.0, 0.5 * grown))
	draw_string(font, at, spec.short_label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Typo.SMALL, label_colour)


## Regular polygons for everything except the star, so shapes read apart at a
## glance without any art.
func _shape_points(shape: int, centre: Vector2, radius: float) -> PackedVector2Array:
	match shape:
		MapNodeSpec.Shape.CIRCLE:
			return _regular(centre, radius, 20, 0.0)
		MapNodeSpec.Shape.DIAMOND:
			return _regular(centre, radius * 1.15, 4, 0.0)
		MapNodeSpec.Shape.SQUARE:
			return _regular(centre, radius * 1.05, 4, PI * 0.25)
		MapNodeSpec.Shape.TRIANGLE:
			return _regular(centre, radius * 1.15, 3, -PI * 0.5)
		MapNodeSpec.Shape.HEXAGON:
			return _regular(centre, radius, 6, 0.0)
		MapNodeSpec.Shape.STAR:
			return _star(centre, radius * 1.25, radius * 0.55, 5)
	return _regular(centre, radius, 20, 0.0)


func _regular(centre: Vector2, radius: float, sides: int,
		rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := rotation + TAU * float(i) / float(sides)
		points.append(centre + Vector2.RIGHT.rotated(angle) * radius)
	return points


func _star(centre: Vector2, outer: float, inner: float,
		points_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in points_count * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := -PI * 0.5 + PI * float(i) / float(points_count)
		points.append(centre + Vector2.RIGHT.rotated(angle) * radius)
	return points
