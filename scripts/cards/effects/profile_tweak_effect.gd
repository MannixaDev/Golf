## The workhorse technique effect: changes the numbers of the next stroke.
##
## Deliberately general. Draw, Fade, Punch, Full Send and Bawl Grabbur are all
## this one class with different exported values, which is the whole point --
## adding a new technique should be a .tres file, not a script.
class_name ProfileTweakEffect
extends CardEffect

## Rules text for the card face.
@export_multiline var summary: String = ""

@export_group("Numbers")
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0
@export var arc_multiplier: float = 1.0

@export_group("Shape")
## Signed bend in degrees. Negative draws left, positive fades right.
@export var curve_deg: float = 0.0
## Hide the bend from the aiming overlay, so the player has to judge it.
@export var conceals_shape: bool = false
## Degrees of bend this stroke may be worked either way, on request. The player
## picks the direction before the swing and the overlay draws it.
@export var shape_choice_deg: float = 0.0

@export_group("Swing")
## Above one, the timing window gets wider without the shot getting straighter.
@export var sweet_spot_multiplier: float = 1.0
## How much of a green's break this stroke ignores, 0 to 1.
@export var slope_resistance: float = 0.0

@export_group("Lie")
## How much of a bad lie this shrugs off, 0 to 1. A sand wedge does not care as
## much about sand.
@export var lie_resistance: float = 0.0

@export_group("Protection")
## The ball cannot be lost on this stroke: out of bounds and water both pull it
## back to the last playable spot rather than costing a penalty.
@export var grants_ball_protection: bool = false


func describe() -> String:
	return summary


func is_shot_modifier() -> bool:
	return true


## Read off the numbers, never authored. Draw and Fade both come out as shape
## because both bend the ball, which is the thing a combo actually cares about.
func stroke_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	if not is_zero_approx(curve_deg) or shape_choice_deg > 0.0:
		tags.append(&"shape")
	if distance_multiplier > 1.001:
		tags.append(&"power")
	if dispersion_multiplier < 0.999:
		tags.append(&"control")
	if roll_multiplier < 0.999 or arc_multiplier > 1.001:
		tags.append(&"soft")
	if lie_resistance > 0.0 or grants_ball_protection:
		tags.append(&"safety")
	return tags


func modify_profile(profile: ShotProfile) -> void:
	profile.carry_yards_max *= distance_multiplier
	profile.dispersion_deg *= dispersion_multiplier
	profile.roll_ratio *= roll_multiplier
	profile.arc_factor *= arc_multiplier
	profile.curve_deg += curve_deg
	profile.sweet_spot_multiplier *= sweet_spot_multiplier
	profile.slope_resistance = maxf(profile.slope_resistance, slope_resistance)
	profile.lie_resistance = maxf(profile.lie_resistance, lie_resistance)
	profile.shape_deg = maxf(profile.shape_deg, shape_choice_deg)
	if conceals_shape:
		profile.conceal_shape = true
	if grants_ball_protection:
		profile.protects_ball = true
