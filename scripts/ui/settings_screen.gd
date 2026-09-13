## Sound and screen. Everything here changes the moment you touch it.
##
## No apply button and no confirmation: the whole point of a volume slider is
## that you hear the result while you are dragging it, and a settings screen you
## have to commit is a settings screen people back out of by mistake.
class_name SettingsScreen
extends Control

signal closed()

@onready var _volume: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _sound: CheckButton = %SoundToggle
@onready var _fullscreen: CheckButton = %FullscreenToggle
@onready var _swing: CheckButton = %SwingToggle
@onready var _back: Button = %BackButton


func _ready() -> void:
	Settings.ensure_loaded()

	# The browser owns its own window, and itch launches the build fullscreen
	# from its own button, so the row is left out rather than shown broken.
	#
	# The card keeps its four-row height and is left an empty band shorter of
	# content. Fixing that properly means the panel sizing itself to its rows
	# rather than sitting on fixed offsets, which is a scene change; measuring
	# it at runtime does not work, because nothing has a size yet during _ready
	# and a deferred pass did not move it either. Not worth a restructure for a
	# few pixels of air on one screen of one platform.
	var fullscreen_row: Node = _fullscreen.get_parent()
	if not Settings.owns_the_window() and fullscreen_row is Control:
		fullscreen_row.hide()

	_volume.value = Settings.volume * 100.0
	_sound.button_pressed = Settings.sound_enabled
	_fullscreen.button_pressed = Settings.fullscreen
	_swing.button_pressed = Settings.swing_accuracy
	_refresh_volume_label()
	_refresh_enabled()

	_volume.value_changed.connect(_on_volume_changed)
	_sound.toggled.connect(_on_sound_toggled)
	_fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.set_fullscreen(on))
	_swing.toggled.connect(func(on: bool) -> void:
		Settings.set_swing_accuracy(on)
		Sfx.play(&"card", -4.0))
	_back.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		closed.emit())

	_back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()


func _on_volume_changed(value: float) -> void:
	Settings.set_volume(value / 100.0)
	_refresh_volume_label()
	# Play something as you drag, or the slider is a number with no meaning.
	Sfx.play(&"select", -10.0, 0.0)


func _on_sound_toggled(on: bool) -> void:
	Settings.set_sound_enabled(on)
	_refresh_enabled()
	if on:
		Sfx.play(&"card", -4.0)


func _refresh_volume_label() -> void:
	_volume_value.text = "%d%%" % roundi(Settings.volume * 100.0)


## A volume slider you can still drag while sound is off is a lie about what the
## control does.
func _refresh_enabled() -> void:
	_volume.editable = Settings.sound_enabled
	var faded := 1.0 if Settings.sound_enabled else 0.4
	_volume.modulate.a = faded
	_volume_value.modulate.a = faded
