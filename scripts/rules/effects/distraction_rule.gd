## Somebody is putting you off. A chance each stroke that your swing goes wilder
## than it should, announced when it happens so it never feels like the maths
## quietly cheated.
##
## This is the comedic side of the brief made mechanical: the phone, the chatter,
## the well-meaning "nice shot" that curses the next one.
class_name DistractionRule
extends CourseRule

@export_multiline var summary: String = "Somebody keeps putting you off."
## Chance per stroke, 0 to 1.
@export var chance: float = 0.45
@export var dispersion_multiplier: float = 1.9
@export var distance_multiplier: float = 1.0
## Picked at random when it fires.
@export var announcements: PackedStringArray = PackedStringArray([
	"Someone talks during your backswing.",
	"A phone goes off in the next fairway.",
	"\"Nice shot!\" they say, far too early.",
])

## Rolled in before_stroke so the aiming cone already shows the damage, rather
## than surprising the player after they have committed.
var _active: bool = false


func describe() -> String:
	return summary


func on_hole_start(_hole: HoleData, _ctx: CourseRuleContext) -> void:
	_active = false


func before_stroke(_hole: HoleData, ctx: CourseRuleContext) -> void:
	_active = ctx.rng.randf() < chance
	if not _active:
		return
	if announcements.is_empty():
		ctx.announce("Something puts you off.")
	else:
		ctx.announce(announcements[ctx.rng.randi_range(0, announcements.size() - 1)])


func modify_profile(profile: ShotProfile, _ctx: CourseRuleContext) -> void:
	if not _active:
		return
	profile.dispersion_deg *= dispersion_multiplier
	profile.carry_yards_max *= distance_multiplier
