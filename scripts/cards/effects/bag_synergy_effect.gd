## A technique that is worth more when the bag agrees with it.
##
## The general form of "this card rewards a direction": count something about
## the bag, measure it against a pivot, and scale the stroke by how far past it
## you are. One exported class rather than a card-shaped script each time, the
## same way ProfileTweakEffect covers every plain technique in the game.
##
## Deliberately capped. An effect that keeps paying is an effect that decides
## the run on its own by hole six, and the interesting version of "build towards
## this" is one where the last two steps are the hard ones.
class_name BagSynergyEffect
extends CardEffect

enum Counts {
	CARDS,       ## Everything in the bag.
	CLUBS,       ## Shot cards.
	TECHNIQUES,  ## Everything that is not a shot.
	WOODS,
	IRONS,
	WEDGES,
	UPGRADED,    ## Cards grooved at the range.
}

@export_multiline var summary: String = ""

@export_group("What it counts")
@export var counts: Counts = Counts.CLUBS
## The count this card considers neutral. Steps are measured from here.
@export var pivot: int = 6
## Count *below* the pivot instead of above it, for cards that reward a bag you
## have deliberately kept small.
@export var fewer_is_better: bool = false
## Most steps that can ever pay out.
@export var max_steps: int = 5

@export_group("Per step")
## Added to the distance multiplier per step. 0.04 is four per cent a step.
@export var distance_per_step: float = 0.0
## Added to the dispersion multiplier per step. Negative tightens.
@export var dispersion_per_step: float = 0.0
@export var roll_per_step: float = 0.0
## Added to the timing window per step.
@export var sweet_spot_per_step: float = 0.0


func describe() -> String:
	return summary


func is_shot_modifier() -> bool:
	return true


func modify_profile(profile: ShotProfile) -> void:
	var steps := steps_for(profile.bag)
	if steps <= 0:
		return
	profile.carry_yards_max *= 1.0 + distance_per_step * steps
	profile.dispersion_deg *= maxf(1.0 + dispersion_per_step * steps, 0.1)
	profile.roll_ratio *= maxf(1.0 + roll_per_step * steps, 0.0)
	profile.sweet_spot_multiplier *= 1.0 + sweet_spot_per_step * steps


## How many steps this bag is worth. Public so the card face and the harness can
## both ask without replaying the whole effect.
func steps_for(bag: BagStats) -> int:
	# No bag at all means no bag *information* -- a card sat in a shop, or a
	# face printing its own numbers. It must read as zero steps, and for a
	# fewer-is-better card that is not the same as an empty bag: counting down
	# from a pivot of twelve against a count of zero handed the card its maximum
	# payout in the one place it has nothing to go on.
	if bag == null or bag.cards <= 0:
		return 0
	var found := count_in(bag)
	var over := (pivot - found) if fewer_is_better else (found - pivot)
	return clampi(over, 0, max_steps)


func count_in(bag: BagStats) -> int:
	match counts:
		Counts.CARDS:
			return bag.cards
		Counts.CLUBS:
			return bag.clubs
		Counts.TECHNIQUES:
			return bag.techniques
		Counts.WOODS:
			return bag.of_family(ClubSpec.Family.WOOD)
		Counts.IRONS:
			return bag.of_family(ClubSpec.Family.IRON)
		Counts.WEDGES:
			return bag.of_family(ClubSpec.Family.WEDGE)
		Counts.UPGRADED:
			return bag.upgraded
	return 0
