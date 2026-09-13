## A plain full-screen message with one button.
##
## Used for the stops that are not yet built (Pro Shop, Driving Range and the
## rest arrive with the reward system in Milestone 6) and for the end of a run.
## Deliberately honest rather than a fake shop front.
class_name NoticeScreen
extends Control

signal continued()
## Which of several offered options was taken. Index into the array given to
## show_choice().
signal option_chosen(index: int)

@onready var _title: Label = %NoticeTitle
@onready var _body: Label = %NoticeBody
@onready var _footnote: Label = %NoticeFootnote
@onready var _button: Button = %NoticeButton
@onready var _options: VBoxContainer = %NoticeOptions

var _option_buttons: Array[Button] = []


func _ready() -> void:
	_button.pressed.connect(func() -> void: continued.emit())
	_button.grab_focus()


func show_notice(title: String, body: String, footnote: String,
		button_text: String, accent: Color) -> void:
	_clear_options()
	_title.text = title.to_upper()
	_body.text = body
	_footnote.text = footnote
	_footnote.visible = footnote != ""
	_button.text = button_text
	_button.show()
	_title.add_theme_color_override("font_color", accent)


## A stop that asks you to pick between a couple of things rather than just
## acknowledging something. Each entry becomes a button.
func show_choice(title: String, body: String, options: Array,
		accent: Color, leave_text: String = "") -> void:
	show_notice(title, body, "", leave_text, accent)
	_button.visible = leave_text != ""

	for i in options.size():
		var button := Button.new()
		button.text = str(options[i])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(480.0, 52.0)
		button.add_theme_font_size_override("font_size", 17)
		var index := i
		button.pressed.connect(func() -> void: option_chosen.emit(index))
		_options.add_child(button)
		_option_buttons.append(button)
	if not _option_buttons.is_empty():
		_option_buttons[0].grab_focus()


func _clear_options() -> void:
	for button in _option_buttons:
		button.queue_free()
	_option_buttons.clear()


## The stop exists on the map but its contents are a later milestone.
func show_placeholder(node: MapNode) -> void:
	show_notice(
		node.display_name(),
		node.spec.description,
		"This stop is on the route, but what happens here arrives with the "
			+ "reward and shop systems. For now, walk on.",
		"Back to the route",
		node.spec.colour)
