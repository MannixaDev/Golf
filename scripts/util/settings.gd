## Player settings, loaded once and written back whenever they change.
##
## Kept deliberately small. Every option here is one the player can actually tell
## the difference between, which rules out the usual menu padding: there is no
## point offering a graphics quality toggle for a game drawn entirely in
## polygons, or a resolution list when the whole thing scales to the window.
##
## A static class, not an autoload, for the same reason Sfx is one -- autoloads
## are invisible to the `--script` test harnesses.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"
const SECTION := "player"

## Loudest the game will ever be. The sound bank is synthesised at full scale, so
## this is where the actual headroom lives.
const MASTER_CEILING_DB := -6.0
## Below this the slider means silence rather than "very quiet".
const SILENT_DB := -60.0

## Two-stage swing: power, then timing. Off makes every strike pure and the
## swing a single press, for anyone who wants the deckbuilding without the
## execution test.
static var swing_accuracy: bool = true
static var volume: float = 0.8
static var sound_enabled: bool = true
static var fullscreen: bool = false
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return  # first run, defaults stand
	swing_accuracy = bool(config.get_value(SECTION, "swing_accuracy", swing_accuracy))
	volume = clampf(float(config.get_value(SECTION, "volume", volume)), 0.0, 1.0)
	sound_enabled = bool(config.get_value(SECTION, "sound_enabled", sound_enabled))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", fullscreen))


static func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "swing_accuracy", swing_accuracy)
	config.set_value(SECTION, "volume", volume)
	config.set_value(SECTION, "sound_enabled", sound_enabled)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.save(PATH)


## Volume as decibels for an AudioStreamPlayer.
##
## Loudness is perceived roughly logarithmically, so a slider mapped straight to
## decibels feels dead across its top half and then falls off a cliff. Squaring
## the slider first gives a travel that matches what the ear expects.
static func volume_db() -> float:
	ensure_loaded()
	if not sound_enabled or volume <= 0.001:
		return SILENT_DB
	var shaped := volume * volume
	return linear_to_db(shaped) + MASTER_CEILING_DB


static func set_volume(value: float) -> void:
	ensure_loaded()
	volume = clampf(value, 0.0, 1.0)
	Sfx.apply_volume()
	save()


static func set_sound_enabled(value: bool) -> void:
	ensure_loaded()
	sound_enabled = value
	Sfx.apply_volume()
	save()


static func set_swing_accuracy(value: bool) -> void:
	ensure_loaded()
	swing_accuracy = value
	save()


static func set_fullscreen(value: bool) -> void:
	ensure_loaded()
	fullscreen = value
	apply_window()
	save()


## True where the game does not own its own window.
##
## In a browser the page owns it, and itch owns the page: a build embedded there
## is launched fullscreen by itch's own button. Offering our own toggle as well
## is at best a duplicate and at worst a lie, because the browser refuses a
## fullscreen request that did not come from a click -- so a saved preference
## applied on boot silently fails and the switch then disagrees with the screen.
static func owns_the_window() -> bool:
	return not OS.has_feature("web")


## Pushed to the window on boot and whenever the option changes.
static func apply_window() -> void:
	ensure_loaded()
	if DisplayServer.get_name() == "headless" or not owns_the_window():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
