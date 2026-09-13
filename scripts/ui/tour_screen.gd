## The ladder: which tour you are playing, and how far up you have got.
##
## Shown between the title and the first tee. Deliberately a whole screen rather
## than a dropdown, because it is the only place the game admits it has a shape
## beyond the round in front of you -- a locked rung you can see is a reason to
## finish the one you are on.
class_name TourScreen
extends Control

signal tour_chosen(tour: TourSpec, holes: int)
signal closed()

const ROW_HEIGHT := 78.0

@onready var _rows: VBoxContainer = %TourRows
@onready var _blurb: Label = %TourBlurb
@onready var _nine: Button = %NineButton
@onready var _eighteen: Button = %EighteenButton
@onready var _back: Button = %BackButton

var _selected: TourSpec = null


func _ready() -> void:
	TourLibrary.ensure_career_loaded()
	_nine.pressed.connect(func() -> void: _start(MapGenerator.HOLES_PER_NINE))
	_eighteen.pressed.connect(func() -> void:
		_start(MapGenerator.HOLES_PER_NINE * 2))
	_back.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		closed.emit())
	_build()


func _build() -> void:
	for child in _rows.get_children():
		child.queue_free()

	# Highest unlocked is selected by default: the ladder is a career, and the
	# thing you were most recently working on is the thing you came back for.
	for tour in TourLibrary.all():
		if TourLibrary.is_unlocked(tour):
			_selected = tour
		_rows.add_child(_row(tour))
	_refresh()


func _row(tour: TourSpec) -> Control:
	var unlocked := TourLibrary.is_unlocked(tour)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	button.disabled = not unlocked
	button.toggle_mode = true
	button.add_theme_font_override("font", Typo.SEMIBOLD)
	button.add_theme_font_size_override("font_size", Typo.BODY)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_meta(&"tour", tour)

	var best := TourLibrary.best_on(tour)
	var trailer := ""
	if not unlocked:
		trailer = "        locked  ·  finish the %s" % _below(tour)
	elif best > 0:
		trailer = "        best finish  %s" % Leaderboard.ordinal(best)
	button.text = "%s%s\n        %s" % [tour.display_name, trailer, tour.summary()]

	if unlocked:
		button.pressed.connect(func() -> void:
			Sfx.play(&"card", -6.0)
			_selected = tour
			_refresh())
	return button


func _below(tour: TourSpec) -> String:
	var under := TourLibrary.by_rung(tour.rung - 1)
	return under.display_name if under != null else "one below"


func _refresh() -> void:
	for child in _rows.get_children():
		if child is Button and child.has_meta(&"tour"):
			var tour: TourSpec = child.get_meta(&"tour")
			child.set_pressed_no_signal(tour == _selected)
			child.add_theme_color_override("font_color",
				tour.colour if tour == _selected else Palette.INK_DIM)
	_blurb.text = _selected.blurb if _selected != null else ""
	var playable := _selected != null
	_nine.disabled = not playable
	_eighteen.disabled = not playable


func _start(holes: int) -> void:
	if _selected == null:
		return
	Sfx.play(&"whoosh", -3.0)
	tour_chosen.emit(_selected, holes)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
