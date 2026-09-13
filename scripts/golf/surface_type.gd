## One kind of ground, and everything that follows from being on it.
##
## A surface does three separate jobs, and it is worth keeping them apart:
##
##   playing FROM it   multipliers folded into the next shot's profile
##   rolling OVER it   friction, so a ball running into rough pulls up short
##   landing IN it     water catches the ball and costs a penalty
##
## All of it is data. Adding a new hazard is a .tres file plus a region on a hole.
class_name SurfaceType
extends Resource

@export_group("Identity")
@export var id: StringName = &"surface"
@export var display_name: String = "Ground"
## One short line for the lie readout.
@export var summary: String = ""

## How the renderer should treat this ground. The renderer used to work this out
## by asking whether a surface blocked ground shots or caught the ball, which
## tied what a thing *looks* like to what it *does* -- so a decorative pond and a
## penalty pond could not look the same, and a new hazard could not pick its own
## treatment without also changing how it plays.
enum Style {
	## Flat ground: grain and nothing else. Fairway, rough, tee, divots.
	TURF,
	## A raked bowl, lit from the sun side with a shadow under the far lip.
	SAND,
	## Deeper towards the middle, with a shoreline and a ruffled surface.
	WATER,
	## A clump that sits above the ground and casts a shadow onto it.
	FOLIAGE,
}

@export_group("Appearance")
@export var colour: Color = Color("#3a6b3d")
@export var outline_colour: Color = Color(0, 0, 0, 0.25)
@export var style: Style = Style.TURF

@export_group("Playing from here")
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var arc_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0
## Sand: you cannot putt your way out of it.
@export var blocks_ground_shots: bool = false

@export_group("Standing in the way")
## Trees do not only sit on the ground, they occupy the air above it, and that is
## the only part of a golf course that interacts with a shot *in flight*.
##
## A shot crossing this surface is judged against a height band:
##
##   above `canopy_top_yards`     clears it, and nothing happens
##   inside the band             hits branches and drops straight down
##   below `trunk_clear_yards`   passes underneath, through the trunks
##
## That last line is the interesting one. It is why a punch is worth carrying:
## from under a tree you cannot go over, so you go under. Nothing else in the
## game reads `arc_factor`, which meant a low shot was flavour text until now.
##
## Zero canopy means the surface is not in the air at all, which is every other
## surface on the course.
@export var canopy_top_yards: float = 0.0
@export var trunk_clear_yards: float = 0.0

@export_group("Ball behaviour")
## Multiplies rolling deceleration. Above 1 pulls the ball up short.
@export var roll_friction: float = 1.0
## Water: the ball is lost the moment it arrives.
@export var catches_ball: bool = false
@export var penalty_strokes: int = 0


## Does anything stand up out of this ground?
func has_canopy() -> bool:
	return canopy_top_yards > 0.0


## Would a ball crossing here at this height be stopped by what is growing on it?
func blocks_at_height(height_yards: float) -> bool:
	if not has_canopy():
		return false
	return height_yards > trunk_clear_yards and height_yards <= canopy_top_yards


## True if being here changes how the ball can be played at all.
func modifies_play() -> bool:
	return blocks_ground_shots \
		or not is_equal_approx(distance_multiplier, 1.0) \
		or not is_equal_approx(dispersion_multiplier, 1.0) \
		or not is_equal_approx(arc_multiplier, 1.0) \
		or not is_equal_approx(roll_multiplier, 1.0)


## Fold this lie into a stroke. Anything the player has done to resist the lie
## has already been applied, so it is honoured here by easing each multiplier
## back toward neutral rather than by a separate code path.
func apply_to(profile: ShotProfile) -> void:
	var softening := clampf(profile.lie_resistance, 0.0, 1.0)
	profile.carry_yards_max *= lerpf(distance_multiplier, 1.0, softening)
	profile.dispersion_deg *= lerpf(dispersion_multiplier, 1.0, softening)
	profile.arc_factor *= lerpf(arc_multiplier, 1.0, softening)
	profile.roll_ratio *= lerpf(roll_multiplier, 1.0, softening)
