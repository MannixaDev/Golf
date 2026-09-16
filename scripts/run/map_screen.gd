## The route screen: where you are, where you can go, and how the card is going.
class_name MapScreen
extends Control

signal node_chosen(id: int)

@onready var _map_view: MapView = %MapView
@onready var _course_label: Label = %CourseLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _cut_label: Label = %CutLabel
@onready var _deck_label: Label = %DeckLabel
@onready var _purse_label: Label = %PurseLabel
@onready var _relic_row: HBoxContainer = %RelicRow
@onready var _info_title: Label = %InfoTitle
@onready var _info_body: Label = %InfoBody
@onready var _info_detail: Label = %InfoDetail


## Which nine this route is. Set by the run layer before setup(), because the
## map screen has no idea how long a round the player picked.
var course_name: String = "THE FRONT NINE"


func _ready() -> void:
	_map_view.node_chosen.connect(func(id: int) -> void: node_chosen.emit(id))
	_map_view.node_hovered.connect(_on_node_hovered)
	_show_default_info()


func setup(map: RunMap, run: RunState, deck: Deck) -> void:
	_map_view.set_map(map)
	# The map draws the cut, so it has to be told where it falls. Taken from the
	# run rather than from a constant: an eighteen cuts later than a nine.
	_map_view.cut_after_hole = run.cut_hole() if run != null else 0
	refresh(run, deck)


func refresh(run: RunState, deck: Deck) -> void:
	_course_label.text = course_name
	_score_label.text = "CARD  %s" % run.score_text().to_upper()
	_cut_label.text = _standing(run)
	_deck_label.text = "BAG  %d CARDS" % deck.total_cards()
	_purse_label.text = "WINNINGS  %d" % run.winnings
	_show_relics(run.relics)

	# The cut is the run's health bar, so it turns as it gets close.
	var spare := run.strokes_remaining()
	var colour := Color(0.76, 0.89, 0.68)
	if spare <= 2:
		colour = Color(0.94, 0.35, 0.28)
	elif spare <= 4:
		colour = Color(1.0, 0.72, 0.35)
	_cut_label.add_theme_color_override("font_color", colour)


## Carried equipment, drawn as tagged chips so the bar stays readable however
## much of it you have accumulated.
## Where you are in the tournament, and what is still to play for.
func _standing(run: RunState) -> String:
	if run.leaderboard == null:
		return "CUT AT  +%d" % run.cut_line
	var board := run.leaderboard
	if run.holes_played < run.cut_hole():
		return "%s  ·  TOP %d MAKE THE CUT" % [
			run.position_text().to_upper(), run.cut_place()]
	var leader: int = board.entries[0].to_par
	var behind: int = board.player().to_par - leader
	if behind <= 0:
		return "%s  ·  LEADING" % run.position_text().to_upper()
	return "%s  ·  %d BEHIND" % [run.position_text().to_upper(), behind]


func _show_relics(relics: Array[RelicSpec]) -> void:
	for child in _relic_row.get_children():
		child.queue_free()
	for relic in relics:
		var chip := Label.new()
		chip.text = " %s " % relic.short_label
		chip.tooltip_text = "%s\n%s" % [relic.display_name, relic.effect_text()]
		chip.add_theme_font_size_override("font_size", 15)
		chip.add_theme_color_override("font_color", relic.colour)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		_relic_row.add_child(chip)


func _on_node_hovered(node: MapNode) -> void:
	if node == null or node.spec == null:
		_show_default_info()
		return

	_info_title.text = node.display_name().to_upper()
	_info_body.text = node.spec.description
	if node.plays_hole():
		var tier: Array = ["a gentle one", "ordinary", "a real test", "brutal", "the closer"]
		_info_detail.text = "Golf hole · %s" % tier[clampi(node.difficulty(), 0, 4)]
	else:
		_info_detail.text = "No stroke played here."
	_info_title.add_theme_color_override("font_color", node.spec.colour)


func _show_default_info() -> void:
	_info_title.text = "CHOOSE YOUR ROUTE"
	_info_body.text = "Pick any stop the highlighted lines lead to. " \
		+ "Hover a stop to see what waits there."
	_info_detail.text = ""
	_info_title.add_theme_color_override("font_color", Color(0.94, 0.98, 0.88))
