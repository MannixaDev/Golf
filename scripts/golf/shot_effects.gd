## Transient impact effects: divots, splashes, sand, and the burst when a putt
## finally drops.
##
## Drawn by hand rather than with GPUParticles2D, for the same reason as
## everything else here -- particle materials want textures, and the project has
## none. A few dozen decaying dots cost nothing and stay in the same visual
## language as the rest of the course.
class_name ShotEffects
extends Node2D

const GRAVITY := 320.0

## One flying speck of turf, sand or water.
class Speck:
	var position: Vector2
	var velocity: Vector2
	var life: float
	var max_life: float
	var size: float
	var colour: Color

	func _init(from: Vector2, vel: Vector2, duration: float, radius: float,
			tint: Color) -> void:
		position = from
		velocity = vel
		life = duration
		max_life = duration
		size = radius
		colour = tint


## An expanding ring, for a splash or a holed putt.
class Ring:
	var centre: Vector2
	var life: float
	var max_life: float
	var radius: float
	var grow: float
	var colour: Color

	func _init(at: Vector2, duration: float, start_radius: float,
			growth: float, tint: Color) -> void:
		centre = at
		life = duration
		max_life = duration
		radius = start_radius
		grow = growth
		colour = tint


var _specks: Array[Speck] = []
var _rings: Array[Ring] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func clear() -> void:
	_specks.clear()
	_rings.clear()
	queue_redraw()


## The ball arriving. What flies up is decided by the ground it hit.
func impact(at: Vector2, strength: float, surface: SurfaceType) -> void:
	var colour := Palette.ACCENT_SHOT
	var count := 8
	var speed := 90.0

	if surface != null:
		if surface.catches_ball:
			_splash(at, strength, surface)
			return
		colour = surface.colour.lightened(0.25)
		if surface.blocks_ground_shots:
			# Sand throws up far more than turf does.
			count = 18
			speed = 130.0
		elif surface.roll_friction >= 2.0:
			count = 12

	count = int(count * clampf(strength, 0.3, 1.0)) + 3
	for i in count:
		var angle := _rng.randf_range(-PI, 0.0)
		var velocity := Vector2.RIGHT.rotated(angle) \
			* _rng.randf_range(speed * 0.4, speed) * clampf(strength, 0.4, 1.0)
		_specks.append(Speck.new(at, velocity,
			_rng.randf_range(0.25, 0.5), _rng.randf_range(1.5, 3.0), colour))
	queue_redraw()


func _splash(at: Vector2, strength: float, surface: SurfaceType) -> void:
	var colour := surface.colour.lightened(0.45)
	_rings.append(Ring.new(at, 0.55, 6.0, 90.0 * clampf(strength, 0.4, 1.0), colour))
	for i in 14:
		var angle := _rng.randf_range(-PI, 0.0)
		var velocity := Vector2.RIGHT.rotated(angle) * _rng.randf_range(60.0, 150.0)
		_specks.append(Speck.new(at, velocity,
			_rng.randf_range(0.3, 0.6), _rng.randf_range(1.5, 3.5), colour))
	queue_redraw()


## The moment the ball drops. Deliberately the biggest effect in the game.
func celebrate(at: Vector2) -> void:
	var gold := Palette.GOLD
	_rings.append(Ring.new(at, 0.7, 4.0, 120.0, gold))
	_rings.append(Ring.new(at, 0.95, 4.0, 70.0, gold))
	for i in 20:
		var angle := _rng.randf_range(0.0, TAU)
		var velocity := Vector2.RIGHT.rotated(angle) * _rng.randf_range(70.0, 190.0)
		_specks.append(Speck.new(at, velocity,
			_rng.randf_range(0.4, 0.8), _rng.randf_range(2.0, 3.5), gold))
	queue_redraw()


func _process(delta: float) -> void:
	if _specks.is_empty() and _rings.is_empty():
		return

	for i in range(_specks.size() - 1, -1, -1):
		var speck := _specks[i]
		speck.life -= delta
		if speck.life <= 0.0:
			_specks.remove_at(i)
			continue
		speck.velocity.y += GRAVITY * delta
		speck.position += speck.velocity * delta

	for i in range(_rings.size() - 1, -1, -1):
		var ring := _rings[i]
		ring.life -= delta
		if ring.life <= 0.0:
			_rings.remove_at(i)
			continue
		ring.radius += ring.grow * delta

	queue_redraw()


func _draw() -> void:
	for ring in _rings:
		var fade := ring.life / ring.max_life
		var colour := ring.colour
		colour.a = fade * 0.7
		draw_arc(ring.centre, ring.radius, 0.0, TAU, 40, colour,
			maxf(1.0, 3.0 * fade), true)

	for speck in _specks:
		var fade := speck.life / speck.max_life
		var colour := speck.colour
		colour.a = fade
		draw_circle(speck.position, speck.size * fade, colour)
