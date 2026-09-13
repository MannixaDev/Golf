## Sound effects, reachable from anywhere without being threaded through the
## scene tree.
##
## Deliberately a static service rather than an autoload. An autoload is not
## visible to scripts launched with `--script`, which is how every test harness
## in tools/ runs, so making it one caused HoleView to fail to compile the moment
## it asked for a sound. This works identically in the game, in the editor and in
## a headless suite, and no-ops where there is nothing to hear.
class_name Sfx
extends RefCounted

## Enough for a strike, its landing, a card and a UI click to overlap.
const VOICES := 8

static var _bank: Dictionary = {}
static var _players: Array[AudioStreamPlayer] = []
static var _next := 0
static var _ready := false
static var _enabled := false
static var _master_db := -6.0


static func _ensure_ready() -> void:
	if _ready:
		return
	_ready = true

	# A headless run has no output device and nothing to hear, and generating the
	# bank there would only slow the suites down.
	var loop := Engine.get_main_loop()
	_enabled = DisplayServer.get_name() != "headless" and loop is SceneTree
	if not _enabled:
		return

	_bank = SoundBank.build()
	var root: Node = (loop as SceneTree).root
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		root.add_child(player)
		_players.append(player)
	apply_volume()


## Push the player's volume setting onto every voice. Per-sound offsets are
## applied on top at play time, so this is only the ceiling.
static func apply_volume() -> void:
	_master_db = Settings.volume_db()
	for player in _players:
		player.volume_db = _master_db


## `pitch_variation` keeps a repeated sound from turning into a machine gun.
static func play(id: StringName, volume_db: float = 0.0,
		pitch_variation: float = 0.08) -> void:
	_ensure_ready()
	if not _enabled or not _bank.has(id) or _players.is_empty():
		return

	var player := _players[_next]
	_next = (_next + 1) % _players.size()

	player.stream = _bank[id]
	player.volume_db = _master_db + volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## The sound a club makes, chosen from what the club actually is rather than
## from its name, so a new club needs no new case here.
static func play_strike(profile: ShotProfile, power: float) -> void:
	var id := &"iron"
	if profile.is_ground_shot:
		id = &"putt"
	elif profile.carry_yards_max >= 200.0:
		id = &"drive"
	elif profile.carry_yards_max <= 100.0:
		id = &"chip"
	# A half swing should not sound like a full one.
	play(id, lerpf(-9.0, 0.0, clampf(power, 0.0, 1.0)))


## What the ground sounds like when the ball arrives on it.
static func play_landing(surface: SurfaceType) -> void:
	if surface == null:
		play(&"land_soft")
		return
	if surface.catches_ball:
		play(&"splash", 1.0)
	elif surface.blocks_ground_shots:
		play(&"land_sand")
	elif surface.roll_friction >= 2.0:
		play(&"land_rough")
	else:
		play(&"land_soft")
