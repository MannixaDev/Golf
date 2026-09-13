## One card, as data.
##
## Cards are authored as .tres files and never as code. Gameplay systems read
## these fields; they never branch on a card's name or id. A card that needs
## behaviour beyond these numbers gets an effect in Milestone 3 rather than a
## special case in the golf logic.
class_name CardData
extends Resource

enum CardType {
	SHOT,       ## Strikes the ball. Costs a stroke and ends the hand.
	TECHNIQUE,  ## Modifies the next shot. (Milestone 3)
	UTILITY,    ## Manipulates the situation. (Milestone 3)
}

## LEGENDARY is deliberately outside the reward pools: nothing rolls one, and
## the only way a legendary reaches a bag is by being made.
enum Rarity { STARTER, COMMON, UNCOMMON, RARE, LEGENDARY }

@export_group("Identity")
@export var id: StringName = &"card"
@export var display_name: String = "Card"
@export_multiline var description: String = ""
@export var type: CardType = CardType.SHOT
@export var rarity: Rarity = Rarity.STARTER
## Focus spent to play this card.
@export var cost: int = 1

@export_group("Shot")
## SHOT cards swing this club. Several cards can share one club and differ only
## by the multipliers below.
@export var club: ClubSpec
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0

@export_group("Effects")
## Everything this card does beyond swinging a club. Authored as sub-resources
## inside the card's .tres, so a new technique is data rather than code.
@export var effects: Array[CardEffect] = []

@export_group("Upgrade")
@export var upgraded: bool = false
## Name shown once upgraded. Falls back to the base name with a marker.
@export var upgraded_name: String = ""
## Extra effects folded in once upgraded. An upgrade is therefore just more of
## the same data -- a ProfileTweakEffect that tightens a club or lengthens it --
## rather than a parallel set of upgraded statistics to keep in step.
@export var upgrade_effects: Array[CardEffect] = []
## Change to the focus cost when upgraded. Usually 0 or -1.
@export var upgrade_cost_delta: int = 0
## One line describing what upgrading does, for the range and the card face.
@export var upgrade_note: String = ""


func is_shot() -> bool:
	return type == CardType.SHOT


## Everything this card currently does, upgrade included. Nothing should read
## `effects` directly, or an upgraded card will quietly behave like a base one.
func active_effects() -> Array[CardEffect]:
	if not upgraded or upgrade_effects.is_empty():
		return effects
	var combined: Array[CardEffect] = effects.duplicate()
	combined.append_array(upgrade_effects)
	return combined


## Focus needed to play this right now.
func effective_cost() -> int:
	return maxi(cost + (upgrade_cost_delta if upgraded else 0), 0)


## True if this card has anything left to gain from the range.
func can_upgrade() -> bool:
	return not upgraded and (not upgrade_effects.is_empty() or upgrade_cost_delta != 0)


func upgrade() -> bool:
	if not can_upgrade():
		return false
	upgraded = true
	return true


## Effects held until the next stroke, rather than fired on play.
func shot_modifiers() -> Array[CardEffect]:
	var held: Array[CardEffect] = []
	for effect in active_effects():
		if effect != null and effect.is_shot_modifier():
			held.append(effect)
	return held


## Joined rules text from every effect, for the card face.
func effect_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for effect in active_effects():
		if effect == null:
			continue
		var line := effect.describe()
		if line != "":
			lines.append(line)
	return "\n".join(lines)


func title() -> String:
	if not upgraded:
		return display_name
	return upgraded_name if upgraded_name != "" else display_name + "+"


## Short stat line for the card face. Empty for non-shot cards.
func stat_line() -> String:
	if not is_shot() or club == null:
		return ""
	var profile := ShotProfile.from_card(self)
	if profile.is_ground_shot:
		return "%d yd roll" % roundi(profile.carry_yards_max)
	return "%d yd carry" % roundi(profile.carry_yards_max)


## Secondary stat line: how wild it is, and how much it runs out.
func detail_line() -> String:
	if not is_shot() or club == null:
		return ""
	var profile := ShotProfile.from_card(self)
	var spread := "spread %.1f deg" % profile.dispersion_deg
	var parts: PackedStringArray = PackedStringArray([spread])
	if not profile.is_ground_shot and profile.roll_ratio > 0.001:
		parts.append("run +%d%%" % roundi(profile.roll_ratio * 100.0))
	parts.append(swing_note())
	# A club you can work either way is a decision you make every time you play
	# it, so it has to be on the face rather than only in the flavour line.
	if profile.shape_deg > 0.001:
		parts.append("shape it either way")
	return "  ·  ".join(parts)


## How hard this club is to time, in words.
##
## The timing window is derived from dispersion, so a tighter club is also a
## more forgiving one to swing. That connection decides every shot you play and
## nothing on the card previously admitted to it -- an upgraded Driver reads as
## "slightly less spray" when what it actually buys you is half again as long to
## catch the meter.
func swing_note() -> String:
	if not is_shot() or club == null:
		return ""
	var scale := ShotProfile.from_card(self).sweet_spot_scale()
	if scale >= 1.35:
		return "easy to time"
	if scale >= 1.05:
		return "steady swing"
	if scale >= 0.85:
		return "demanding"
	return "hard to time"
