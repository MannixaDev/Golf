## A technique that pays off depending on what else is on the stroke.
##
## The split hand is what makes this worth having. A golf turn has always been a
## combination -- one club plus whatever techniques you stack onto the same
## ShotProfile -- but while clubs and techniques shared a hand you often held
## none, and a card reading "if you are already bending it" would have been a
## dead card most of the time. Holding two techniques every stroke turns the
## extras into a small puzzle with a right answer.
##
## Asks about the *shape of the stroke* rather than about card names: "is this
## ball already being bent" rather than "did you play Draw". That keeps working
## when a new shaping card is added, and it is the thing the player can actually
## see on the aiming line.
##
## Folded in after every ordinary technique -- see ShotProfile.apply_effects --
## so the order you play a pair in does not matter.
class_name ComboEffect
extends CardEffect

enum Needs {
	ANOTHER_TECHNIQUE,    ## Anything else on this stroke at all.
	A_SHAPED_STROKE,      ## Something is bending the ball.
	A_STRAIGHT_STROKE,    ## Nothing is. Rewards keeping it simple.
	A_POWERED_STROKE,     ## Something has added distance.
	A_CONTROLLED_STROKE,  ## Something has tightened the dispersion.
}

## Rules text for the card face. Say the condition out loud: a combo the player
## has to discover by experiment is a combo they will never play on purpose.
@export_multiline var summary: String = ""
@export var needs: Needs = Needs.ANOTHER_TECHNIQUE

@export_group("What it always does")
## Both halves of a combo card live in one effect on purpose. Authored as two --
## an ordinary ProfileTweakEffect for the base and this for the bonus -- the base
## counted towards `modifiers_on_stroke` and the card satisfied its own
## condition: Follow Through combined with itself and paid out on every stroke,
## alone. A flat list of effects carries no card identity, so the only way for a
## combo to ask about *other* cards is to be a single effect.
@export var base_distance_multiplier: float = 1.0
@export var base_dispersion_multiplier: float = 1.0
@export var base_roll_multiplier: float = 1.0
@export var base_sweet_spot_multiplier: float = 1.0

@export_group("What it adds when it combines")
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0
## Takes the bend back out of a stroke that is already being shaped. The payoff
## for working the ball and then deciding you would rather it went straight.
@export var straightens: bool = false
@export var sweet_spot_multiplier: float = 1.0
@export var slope_resistance: float = 0.0


func describe() -> String:
	return summary


func is_shot_modifier() -> bool:
	return true


func is_combo() -> bool:
	return true


## A combo contributes no tags of its own. It reads the stroke rather than
## describing it, and letting one combo satisfy another is a loop nobody asked
## for -- two of them would each be waiting on the other.
func stroke_tags() -> Array[StringName]:
	return []


func modify_profile(profile: ShotProfile) -> void:
	# Always, so a combo card drawn with nothing to pair it with is still a card
	# worth playing rather than a blank.
	profile.carry_yards_max *= base_distance_multiplier
	profile.dispersion_deg *= base_dispersion_multiplier
	profile.roll_ratio *= base_roll_multiplier
	profile.sweet_spot_multiplier *= base_sweet_spot_multiplier

	if not _fires(profile):
		return
	profile.carry_yards_max *= distance_multiplier
	profile.dispersion_deg *= dispersion_multiplier
	profile.roll_ratio *= roll_multiplier
	profile.sweet_spot_multiplier *= sweet_spot_multiplier
	profile.slope_resistance = maxf(profile.slope_resistance, slope_resistance)
	if straightens:
		profile.curve_deg = 0.0
		profile.conceal_shape = false


func _fires(profile: ShotProfile) -> bool:
	match needs:
		Needs.ANOTHER_TECHNIQUE:
			return profile.modifiers_on_stroke > 0
		Needs.A_SHAPED_STROKE:
			return profile.stroke_is(&"shape")
		Needs.A_STRAIGHT_STROKE:
			return not profile.stroke_is(&"shape")
		Needs.A_POWERED_STROKE:
			return profile.stroke_is(&"power")
		Needs.A_CONTROLLED_STROKE:
			return profile.stroke_is(&"control")
	return false
