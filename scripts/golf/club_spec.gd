## The shot characteristics of one club.
##
## In Milestone 2 a shot card will reference (or embed) one of these, so the
## resolver never needs to know whether the player chose a club directly or
## played a card.
class_name ClubSpec
extends Resource

enum Family {
	WOOD,     ## Driver, 3 wood, hybrid: long, and it sprays.
	IRON,     ## The honest middle of the bag.
	WEDGE,    ## Short, high, and it stops.
	PUTTER,   ## On the deck.
	SPECIAL,  ## One of a kind. Belongs to no family and fuses with nothing.
}

@export var id: StringName = &"club"
@export var display_name: String = "Club"
## What kind of club this is. Anything that wants to reason about clubs as a
## group -- the workshop that fuses two of them, for one -- asks this rather
## than matching on the id, which is the rule everywhere else in the game.
@export var family: Family = Family.IRON
## Short tag shown in the club list, e.g. "DR", "9i", "PT".
@export var short_label: String = "CL"
## Display order in the bag, longest club first.
@export var sort_order: int = 0
@export_multiline var description: String = ""

@export_group("Distance")
## Carry at 100% power, in yards. Power scales this linearly.
@export var carry_yards_max: float = 100.0
## Roll after landing, as a fraction of carry.
@export var roll_ratio: float = 0.10
## Random distance error, as a fraction. 0.04 == plus or minus ~4%.
@export var distance_variance: float = 0.035

@export_group("Control")
## Maximum aim error in degrees at full power.
@export var dispersion_deg: float = 5.0
## Visual flight height multiplier. 0 for shots that stay on the deck.
@export var arc_factor: float = 0.8
## True for putts and (later) chips: no carry, the whole shot is roll.
@export var is_ground_shot: bool = false
