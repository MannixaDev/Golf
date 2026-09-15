## The fully-computed characteristics of one shot, immediately before it is rolled.
##
## This is the seam between the card layer and the golf simulation. A card builds
## a profile from its club plus its own modifiers; the resolver only ever sees the
## profile. Technique cards, hazards and relics all act by mutating a profile,
## which is why none of them will need to touch ShotResolver.
class_name ShotProfile
extends RefCounted

var display_name: String = "Shot"
## What the bag looked like as this stroke was built. Set before any effect is
## folded in, so a card can scale itself on the company it keeps without
## reaching out of the card layer to find out.
var bag: BagStats = BagStats.new()
var carry_yards_max: float = 100.0
var roll_ratio: float = 0.10
var dispersion_deg: float = 5.0
var arc_factor: float = 0.80
var distance_variance: float = 0.035
var is_ground_shot: bool = false
## Signed bend in degrees applied across the flight. Negative draws left,
## positive fades right.
var curve_deg: float = 0.0
## Do not draw the bend on the aiming overlay. A worked shot whose curve is
## previewed is identical to simply aiming off, which makes the card pointless;
## concealing it turns the card into a real trade -- a tighter shot in exchange
## for judging the shape yourself.
var conceal_shape: bool = false
## Degrees this stroke can be worked either way, at the player's choosing. Zero
## for every club in the bag except the one that was welded together out of two.
##
## Deliberately separate from curve_deg: that is a bend the card imposes on you,
## this is a bend you are allowed to ask for. Draw and Fade hand you a shape and
## hide it; a club you can shape shows you exactly what it is about to do.
var shape_deg: float = 0.0
## How much of the lie to shrug off, 0 to 1. A sand wedge or a good caddie can
## take some of the sting out of a bad lie; at 1.0 the ground stops mattering
## entirely. Applied by SurfaceType when it folds the lie in, which is why relics
## and cards are applied before the lie rather than after it.
var lie_resistance: float = 0.0
## The ball cannot be lost on this stroke. Out of bounds and water both
## pull it back to the last playable spot instead of costing you a penalty.
var protects_ball: bool = false
## Widens the pure-strike window without touching where the ball goes.
##
## The window is normally derived from dispersion, so every card that tightened
## a shot also made it easier to time -- which is fine but leaves no room for a
## card that buys you *only* time. This is that lever: a rehearsal swing does
## not make the club straighter, it makes it easier to catch.
var sweet_spot_multiplier: float = 1.0
## How much of a green's break this stroke ignores, 0 to 1. A putt rapped firmly
## takes the slope out of it, at the cost of running further past if it misses.
var slope_resistance: float = 0.0

## What produced this profile, for feedback and for relics that care.
var source_card: CardData = null


static func from_club(club: ClubSpec) -> ShotProfile:
	var profile := ShotProfile.new()
	profile.display_name = club.display_name
	profile.carry_yards_max = club.carry_yards_max
	profile.roll_ratio = club.roll_ratio
	profile.dispersion_deg = club.dispersion_deg
	profile.arc_factor = club.arc_factor
	profile.distance_variance = club.distance_variance
	profile.is_ground_shot = club.is_ground_shot
	return profile


## `bag` is what the player is carrying. It is optional because the card face
## builds a profile too, just to print its own numbers, and there is no bag in
## that context -- a synergy card shown in a shop reads at its floor, which is
## the honest thing for it to say.
static func from_card(card: CardData, bag: BagStats = null) -> ShotProfile:
	if card == null or card.club == null:
		push_error("ShotProfile: card %s has no club." % [card.id if card else "<null>"])
		return ShotProfile.new()

	var profile := from_club(card.club)
	if bag != null:
		profile.bag = bag
	profile.display_name = card.display_name
	profile.source_card = card
	profile.carry_yards_max *= card.distance_multiplier
	profile.roll_ratio *= card.roll_multiplier
	profile.dispersion_deg *= card.dispersion_multiplier
	profile.apply_effects(card.shot_modifiers())
	return profile


## --- The situation ---------------------------------------------------------
##
## Where this stroke is being played from and what came before it, for cards
## that read the hole rather than the stroke. Set in one call, before anything is
## folded in, because the lie is applied *after* the effects and a card asking
## "am I in trouble" during modify_profile would otherwise always hear no.
##
## A golf turn was already a combination -- club plus techniques onto one profile
## -- so the unexplored axis was never within a stroke but between them. A hole
## is a sequence, which is something most card games do not have.
var stroke_number: int = 1
var hole_par: int = 4
var lie_is_trouble: bool = false
## The club played on the stroke before this one, for rhythm.
var last_club_id: StringName = &""


## Tell the profile where it is. One call rather than four assignments, so a
## caller cannot half-remember it -- and every situation card silently does
## nothing when it is forgotten, which is the failure this project keeps having.
func set_situation(stroke: int, par: int, in_trouble: bool,
		previous_club: StringName = &"") -> void:
	stroke_number = maxi(stroke, 1)
	hole_par = maxi(par, 1)
	lie_is_trouble = in_trouble
	last_club_id = previous_club


## What is already on this stroke, for combo cards to read. Filled in as the
## ordinary techniques are folded in, so a combo sees the finished shot.
var stroke_tags: Array[StringName] = []
## Ordinary techniques on this stroke. Combos do not count themselves, so a
## combo asking for "another technique" is asking about something other than it.
var modifiers_on_stroke: int = 0


## Fold a list of CardEffects into this profile.
##
## Two passes, and that is the whole trick: everything ordinary first, then the
## combos, so a combo is answering a question about the complete stroke. Folded
## in one pass they would only see the cards played before them, and a pair would
## work in one order and not the other -- which is a sequencing puzzle rather
## than a combination, and not what anybody means by playing two cards together.
func apply_effects(effects: Array) -> void:
	for effect in effects:
		if not (effect is CardEffect) or effect.is_combo():
			continue
		modifiers_on_stroke += 1
		for tag in effect.stroke_tags():
			if not stroke_tags.has(tag):
				stroke_tags.append(tag)
		effect.modify_profile(self)

	for effect in effects:
		if effect is CardEffect and effect.is_combo():
			effect.modify_profile(self)


## Is something already doing this to the stroke?
func stroke_is(tag: StringName) -> bool:
	return stroke_tags.has(tag)


## Furthest the shot can finish at full power, carry plus roll.
func max_reach_yards() -> float:
	return carry_yards_max * (1.0 + roll_ratio)


## How high this club would fly the ball at a given swing, before dispersion.
## Used to tell the player what they are about to do while they are still
## deciding, which is the only moment the number is any use to them.
## How wide this club's pure-strike window is, as a multiple of the base.
##
## Derived from dispersion rather than authored as a separate number, because
## the two say the same thing about a club: one that sprays when you catch it
## wrong is the same one that is hard to catch right. A putter is forgiving, a
## driver punishes you. Techniques that tighten dispersion widen the window with
## it, which is a reward they were not previously paying.
func sweet_spot_scale() -> float:
	var from_club := remap(dispersion_deg, 1.2, 7.5, 1.7, 0.75)
	return clampf(from_club * sweet_spot_multiplier, 0.4, 2.6)


## Worst offline miss this club can produce from a total mistime, in degrees.
func offline_deg() -> float:
	return dispersion_deg * 1.8


func apex_yards(power: float = 1.0) -> float:
	return carry_yards_max * clampf(power, 0.0, 1.0) \
		* ShotResult.APEX_RATIO * arc_factor
