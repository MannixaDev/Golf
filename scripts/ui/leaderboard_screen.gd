## The board between holes.
##
## Shown after every hole and before the prize, because that is the beat where a
## score turns into a position: you did not shoot a four, you went past three
## people. Movement is marked, so a hole that gained you nothing still tells you
## the field is coming.
class_name LeaderboardScreen
extends Control

signal continued()

## Rows either side of you, when the field is too long to show whole.
const CONTEXT := 4

@onready var _title: Label = %BoardTitle
@onready var _subtitle: Label = %BoardSubtitle
@onready var _rows: VBoxContainer = %BoardRows
@onready var _button: Button = %ContinueButton


func _ready() -> void:
	_button.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		continued.emit())
	_button.grab_focus()


func show_board(board: Leaderboard, holes_played: int, round_holes: int,
		cut_hole: int, cut_place: int) -> void:
	_title.text = "AFTER %d" % holes_played
	if holes_played < cut_hole:
		_subtitle.text = "%d to the cut  ·  top %d go through" % [
			cut_hole - holes_played, cut_place]
	elif holes_played >= round_holes:
		_subtitle.text = "Final standings"
	else:
		_subtitle.text = "%d holes to play" % (round_holes - holes_played)

	for child in _rows.get_children():
		child.queue_free()

	# Headers, because a column of "+2", "–" and "E" means nothing at all to
	# somebody reading a leaderboard for the first time.
	_rows.add_child(_header())
	_rows.add_child(_rule())
	for entry in _visible(board):
		_rows.add_child(_row(entry, board))


## The top of the board plus everything near you. A twelve-strong field fits
## whole; a longer one shows the people you can actually catch.
func _visible(board: Leaderboard) -> Array:
	if board.entries.size() <= 12:
		return board.entries

	var shown: Array = []
	var player_index := board.entries.find(board.player())
	for i in board.entries.size():
		if i < 3 or absi(i - player_index) <= CONTEXT:
			shown.append(board.entries[i])
	return shown


## The column titles. "MOVED" rather than an arrow glyph: the arrow needs
## explaining and the word does not.
func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var faint := Color(Palette.INK, 0.38)
	row.add_child(_cell("POS", 46, faint, HORIZONTAL_ALIGNMENT_RIGHT, Typo.MICRO))
	row.add_child(_cell("MOVED", 30, faint, HORIZONTAL_ALIGNMENT_CENTER, Typo.MICRO))
	row.add_child(_cell("PLAYER", 330, faint, HORIZONTAL_ALIGNMENT_LEFT, Typo.MICRO))
	row.add_child(_cell("TO PAR", 64, faint, HORIZONTAL_ALIGNMENT_RIGHT, Typo.MICRO))
	return row


func _rule() -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.color = Color(Palette.INK, 0.12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _row(entry, board: Leaderboard) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if entry.is_player:
		# Your line is the one you are looking for, so it is lit.
		var style := StyleBoxFlat.new()
		style.bg_color = Color(Palette.GOLD, 0.13)
		style.border_color = Color(Palette.GOLD, 0.45)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 3.0
		style.content_margin_bottom = 3.0
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		_fill(row, entry, board)
		return panel

	_fill(row, entry, board)
	return row


func _fill(row: HBoxContainer, entry, board: Leaderboard) -> void:
	var tied := _shares_place(entry, board)
	row.add_child(_cell("%s%d" % ["T" if tied else "", entry.place],
		46, Color(Palette.INK, 0.55), HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_cell(_movement(entry), 30, _movement_colour(entry),
		HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_cell(entry.name, 330, entry.colour,
		HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_cell(Leaderboard.to_par_text(entry.to_par), 64,
		_score_colour(entry.to_par), HORIZONTAL_ALIGNMENT_RIGHT))


func _shares_place(entry, board: Leaderboard) -> bool:
	for other in board.entries:
		if other != entry and other.place == entry.place:
			return true
	return false


## Up, down, or held station. Shown because a hole where you scored well and
## still lost ground is the most useful thing a board can tell you.
func _movement(entry) -> String:
	var moved: int = entry.moved()
	if moved > 0:
		return "+%d" % moved
	if moved < 0:
		return str(moved)
	return "–"


func _movement_colour(entry) -> Color:
	var moved: int = entry.moved()
	if moved > 0:
		return Palette.GOOD
	if moved < 0:
		return Palette.DANGER
	return Color(Palette.INK, 0.25)


func _score_colour(to_par: int) -> Color:
	if to_par < 0:
		return Palette.GOOD
	if to_par > 0:
		return Color(Palette.INK, 0.6)
	return Color(Palette.INK, 0.85)


func _cell(text: String, width: float, colour: Color,
		align: int, size: int = Typo.BODY) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	label.add_theme_font_override("font", Typo.SEMIBOLD)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
