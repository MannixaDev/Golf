## A technique that pays off depending on the situation you are in.
##
## The sister of ComboEffect, reading the hole instead of the stroke. A hole is a
## sequence of shots and the shots have consequences that persist, which is
## something most card games have no equivalent of -- their unit is the turn, and
## golf's is the hole.
##
## Deliberately biased towards trouble. The obvious version of this rewards a
## good last shot, which compounds: a good drive buys a good approach buys a
## birdie, and a run snowballs away from anybody having a bad day. Golf's own
## celebrated skill is the opposite one -- scrambling, getting up and down from
## somewhere awful -- so these pay out when the hole is already going badly. Same
## mechanism, far better curve, and it is the more golf of the two.
##
## Everything it reads is set by ShotProfile.set_situation before any effect is
## folded in. A caller that forgets leaves every one of these silently inert, so
## situation_check drives the real HoleView rather than trusting the numbers.
class_name SituationEffect
extends CardEffect

enum Needs {
	FROM_TROUBLE,     ## The ball is sitting in rough, sand or worse.
	GRINDING,         ## The third stroke of this hole or later.
	BEHIND_ON_THE_HOLE, ## Par is already gone: playing for a bogey.
	SAME_CLUB_AGAIN,  ## The club you hit last stroke, while you still have the feel.
}

## Rules text for the card face.
@export_multiline var summary: String = ""
## A few words shown on the heads-up display the moment this fires, so the
## player can see the combination land rather than infer it from the numbers.
## Falls back to the full summary, which is better than silence but too long.
@export var fired_label: String = ""
@export var needs: Needs = Needs.FROM_TROUBLE

@export_group("What it always does")
@export var base_distance_multiplier: float = 1.0
@export var base_dispersion_multiplier: float = 1.0
@export var base_roll_multiplier: float = 1.0

@export_group("What it adds when the situation holds")
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0
@export var sweet_spot_multiplier: float = 1.0
## How much of a bad lie this shrugs off, 0 to 1.
@export var lie_resistance: float = 0.0
## The ball cannot be lost on this stroke.
@export var grants_ball_protection: bool = false


func describe() -> String:
	return summary


func is_shot_modifier() -> bool:
	return true


## Not a combo: this reads the hole rather than the stroke, so it can be folded
## in with the ordinary techniques and can honestly contribute tags -- a card
## that tightens the shot when you are in trouble really has tightened it, and a
## combo asking for a controlled stroke should see that.
func stroke_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	if base_dispersion_multiplier < 0.999 or dispersion_multiplier < 0.999:
		tags.append(&"control")
	if base_distance_multiplier > 1.001 or distance_multiplier > 1.001:
		tags.append(&"power")
	if base_roll_multiplier < 0.999 or roll_multiplier < 0.999:
		tags.append(&"soft")
	if lie_resistance > 0.0 or grants_ball_protection:
		tags.append(&"safety")
	return tags


func modify_profile(profile: ShotProfile) -> void:
	profile.carry_yards_max *= base_distance_multiplier
	profile.dispersion_deg *= base_dispersion_multiplier
	profile.roll_ratio *= base_roll_multiplier

	if not _fires(profile):
		return
	profile.fired_combos.append(fired_label if fired_label != "" else summary)
	profile.carry_yards_max *= distance_multiplier
	profile.dispersion_deg *= dispersion_multiplier
	profile.roll_ratio *= roll_multiplier
	profile.sweet_spot_multiplier *= sweet_spot_multiplier
	profile.lie_resistance = maxf(profile.lie_resistance, lie_resistance)
	if grants_ball_protection:
		profile.protects_ball = true


func _fires(profile: ShotProfile) -> bool:
	match needs:
		Needs.FROM_TROUBLE:
			return profile.lie_is_trouble
		Needs.GRINDING:
			return profile.stroke_number >= 3
		Needs.BEHIND_ON_THE_HOLE:
			# On a par four, the fourth stroke onwards. Par has gone; this is
			# about not dropping two.
			return profile.stroke_number >= profile.hole_par
		Needs.SAME_CLUB_AGAIN:
			return profile.source_card != null \
				and profile.last_club_id != &"" \
				and profile.source_card.id == profile.last_club_id
	return false
