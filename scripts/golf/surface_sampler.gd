## Lets the ball ask about the ground under it without knowing what a hole is.
##
## The ball needs friction every frame while it rolls, so it cannot wait for
## HoleView to tell it after the fact. Handing it a sampler keeps the physics
## generic: the ball asks "how sticky here?" and "am I lost here?" and never
## learns the words bunker or water.
class_name SurfaceSampler
extends RefCounted

var hole: HoleData = null


func _init(hole_data: HoleData = null) -> void:
	hole = hole_data


func friction_at(point: Vector2) -> float:
	if hole == null:
		return 1.0
	return hole.surface_at(point).roll_friction


func catches_at(point: Vector2) -> bool:
	if hole == null:
		return false
	return hole.surface_at(point).catches_ball


## Which way the ground falls here, for a ball rolling over it. The ball asks
## every frame and still never learns what a green is.
func slope_at(point: Vector2) -> Vector2:
	if hole == null:
		return Vector2.ZERO
	return hole.slope_at(point)


## Has the ball left the hole? Asked of the sampler rather than of a rectangle,
## because the boundary is a shape that follows the line of play now.
func out_of_bounds_at(point: Vector2) -> bool:
	if hole == null:
		return false
	return not hole.is_in_bounds(point)


## Is there something growing here that a ball at this height would hit? The
## ball asks this every frame it is in the air and still never learns the word
## tree.
func blocks_flight_at(point: Vector2, height_yards: float) -> bool:
	if hole == null:
		return false
	return hole.surface_at(point).blocks_at_height(height_yards)
