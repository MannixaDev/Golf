## The card you see before anything else. Press anything to go on.
##
## It exists to give the game a front door rather than dumping you straight onto
## a route map, and to give the audio bank a moment to build before the first
## sound is asked for.
class_name SplashScreen
extends Control

signal continued()

## Long enough to read the name, short enough that nobody reaches for a skip
## button. Any key goes through immediately anyway.
const HOLD := 0.7

@onready var _prompt: Label = %Prompt

var _elapsed := 0.0
var _done := false


func _ready() -> void:
	_prompt.modulate.a = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < HOLD:
		return
	# The prompt breathes rather than blinks: a hard flash reads as an error.
	_prompt.modulate.a = 0.45 + 0.4 * sin((_elapsed - HOLD) * 3.0)


## Keys arrive here. Mouse clicks do not: a Control swallows them into
## `_gui_input` first, so a splash that only listened here would ignore every
## click on a game played entirely with the mouse.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_go()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_go()


func _go() -> void:
	# A click that lands in the first fraction of a second is almost always one
	# left over from whatever opened the game.
	if _done or _elapsed < 0.15:
		return
	_done = true
	Sfx.play(&"whoosh", -4.0)
	get_viewport().set_input_as_handled()
	continued.emit()
