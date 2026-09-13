## The card you hand in at the end.
##
## A round of golf is a scorecard. The game was reducing one to a single number
## and a sentence, which threw away the only artefact the sport actually
## produces -- the thing you would put in your pocket and look at again.
##
## Drawn rather than laid out in Controls because the marks matter: golf circles
## a birdie and boxes a bogey, and a player can read a card at a glance from the
## shapes alone without reading a single number. Doubling the ring or the box for
## eagles and doubles is the real convention too.
class_name ScorecardView
extends Control

## Nine to a block, the way a card folds.
const BLOCK := 9
const ROW_HEIGHT := 42.0
const HEADER_HEIGHT := 34.0
## Widest a hole column is allowed to get on a nine, so a short round does not
## stretch into a banner.
const MAX_COLUMN := 78.0
const MARK_RADIUS := 15.0

var lines: Array = []
var tour_name: String = ""
var clawed_back: int = 0

var _column := 60.0
var _left := 0.0


func set_card(card: Array, tour: String, adjustments: int) -> void:
	lines = card
	tour_name = tour
	clawed_back = adjustments
	queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	if lines.is_empty() or size.x <= 8.0:
		return

	# The label column down the left, the holes, a total for each block of nine,
	# and the round itself. The label column has to be counted here as well as
	# positioned: leaving it out made the card one column narrower than what was
	# drawn on it, and the total ran off the end of the panel.
	var blocks := ceili(float(lines.size()) / float(BLOCK))
	var columns := 1 + lines.size() + blocks + (1 if blocks > 1 else 0)
	_column = minf(size.x / float(columns), MAX_COLUMN)
	_left = (size.x - _column * float(columns)) * 0.5

	_draw_grid(columns)
	_draw_headers()
	_draw_pars()
	_draw_scores()


func _draw_grid(columns: int) -> void:
	var wide := _column * float(columns)
	var tall := HEADER_HEIGHT + ROW_HEIGHT * 2.0
	draw_rect(Rect2(_left, 0.0, wide, tall), Color(Palette.SHADE, 0.55))
	draw_rect(Rect2(_left, 0.0, wide, HEADER_HEIGHT),
		Color(Palette.FAIRWAY, 0.16))
	# Vertical rules only between columns, so the card reads as a card rather
	# than as a spreadsheet.
	for i in range(1, columns):
		var x := _left + _column * float(i)
		draw_line(Vector2(x, 0.0), Vector2(x, tall), Color(Palette.INK, 0.10), 1.0)
	for y in [HEADER_HEIGHT, HEADER_HEIGHT + ROW_HEIGHT]:
		draw_line(Vector2(_left, y), Vector2(_left + wide, y),
			Color(Palette.INK, 0.10), 1.0)
	draw_rect(Rect2(_left, 0.0, wide, tall), Color(Palette.INK, 0.18), false, 1.0)


func _draw_headers() -> void:
	_label("HOLE", 0.0, HEADER_HEIGHT * 0.5, _column, Color(Palette.INK, 0.5),
		Typo.MICRO)
	for i in lines.size():
		_cell_label(str(i + 1), _slot(i), HEADER_HEIGHT * 0.5,
			Color(Palette.INK, 0.5), Typo.MICRO)
	for slot in _total_slots():
		_cell_label(slot["name"], slot["at"], HEADER_HEIGHT * 0.5,
			Color(Palette.GOLD, 0.75), Typo.MICRO)


func _draw_pars() -> void:
	var y := HEADER_HEIGHT + ROW_HEIGHT * 0.5
	_label("PAR", 0.0, y, _column, Color(Palette.INK, 0.45), Typo.SMALL)
	for i in lines.size():
		_cell_label(str(int(lines[i]["par"])), _slot(i), y,
			Color(Palette.INK, 0.55), Typo.SMALL)
	for slot in _total_slots():
		_cell_label(str(slot["par"]), slot["at"], y,
			Color(Palette.INK, 0.7), Typo.SMALL)


func _draw_scores() -> void:
	var y := HEADER_HEIGHT + ROW_HEIGHT * 1.5
	_label("SCORE", 0.0, y, _column, Color(Palette.INK, 0.45), Typo.SMALL)
	for i in lines.size():
		var strokes := int(lines[i]["strokes"])
		var par := int(lines[i]["par"])
		_draw_mark(_slot(i), y, strokes - par)
		_cell_label(str(strokes), _slot(i), y, Palette.INK, Typo.STAT)
	for slot in _total_slots():
		_cell_label(str(slot["strokes"]), slot["at"], y, Palette.GOLD, Typo.STAT)


## Golf's own notation: a ring for a birdie, two for an eagle, a box for a
## bogey, two for anything worse. Readable across a room without the numbers.
func _draw_mark(at: float, y: float, to_par: int) -> void:
	var centre := Vector2(_left + at + _column * 0.5, y)
	if to_par < 0:
		var colour := Color(Palette.GOOD, 0.9)
		draw_arc(centre, MARK_RADIUS, 0.0, TAU, 28, colour, 1.8, true)
		if to_par <= -2:
			draw_arc(centre, MARK_RADIUS - 4.0, 0.0, TAU, 28, colour, 1.8, true)
	elif to_par > 0:
		var colour := Color(Palette.DANGER, 0.8)
		var box := MARK_RADIUS * 0.92
		draw_rect(Rect2(centre - Vector2(box, box), Vector2(box, box) * 2.0),
			colour, false, 1.8)
		if to_par >= 2:
			var inner := box - 4.0
			draw_rect(Rect2(centre - Vector2(inner, inner),
				Vector2(inner, inner) * 2.0), colour, false, 1.8)


# --- Geometry -------------------------------------------------------------

## Where a hole's column starts, allowing for the total columns that interrupt
## the run of holes after every nine.
func _slot(hole_index: int) -> float:
	var blocks_before := hole_index / BLOCK
	return _column * float(1 + hole_index + blocks_before)


## The OUT / IN / TOT columns, with what goes in them.
func _total_slots() -> Array:
	var slots: Array = []
	var blocks := ceili(float(lines.size()) / float(BLOCK))
	var names := ["OUT", "IN"]
	for block in blocks:
		var first := block * BLOCK
		var last := mini(first + BLOCK, lines.size())
		var par := 0
		var strokes := 0
		for i in range(first, last):
			par += int(lines[i]["par"])
			strokes += int(lines[i]["strokes"])
		slots.append({
			"name": names[block] if block < names.size() else "OUT",
			"at": _column * float(1 + last + block),
			"par": par,
			"strokes": strokes,
		})
	if blocks > 1:
		var par := 0
		var strokes := 0
		for line in lines:
			par += int(line["par"])
			strokes += int(line["strokes"])
		slots.append({
			"name": "TOT",
			"at": _column * float(1 + lines.size() + blocks),
			"par": par,
			"strokes": strokes,
		})
	return slots


func _cell_label(text: String, at: float, y: float, colour: Color,
		point: int) -> void:
	_label(text, at, y, _column, colour, point)


func _label(text: String, at: float, y: float, width: float, colour: Color,
		point: int) -> void:
	var font := Typo.SEMIBOLD
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, point)
	draw_string(font,
		Vector2(_left + at + (width - measured.x) * 0.5, y + measured.y * 0.34),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, point, colour)
