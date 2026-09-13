## One of the other players in the field.
##
## The cut was the whole of the pressure in this game and it was not enough
## pressure: a bad round still came in at +2 against a line drawn at +8. Score
## against a fixed number is a bar that either fills or does not. Score against a
## field is a position, and a position moves every hole whether you played well
## or not.
##
## The field is not random. Each player has a **skill** -- how far under par they
## go on an average hole -- and a **steadiness**, which is how tightly they hold
## to it. Those two together are what makes a leaderboard feel like a tournament
## rather than a dice roll: the best player in the field is near the top every
## single week, and you have to actually beat him rather than hope he blows up.
class_name RivalSpec
extends Resource

@export_group("Identity")
@export var id: StringName = &"rival"
@export var display_name: String = "A Golfer"
## Shown where there is no room for the full name.
@export var short_name: String = "GOLFER"
## One line, for the leaderboard's hover or the commentary.
@export var flavour: String = ""
@export var colour: Color = Color(0.85, 0.87, 0.82)

@export_group("Form")
## Strokes under par on an average hole. Negative is good: -0.7 is a player who
## goes round a nine in about six under.
@export var skill: float = 0.0
## How tightly they hold to that, in strokes. Low is metronomic; high is a
## player who makes eagles and doubles in the same round.
@export var steadiness: float = 1.1
## What happens to them in contention. Positive numbers are a player who tightens
## up when they get their nose in front, which is a thing that happens to real
## golfers and is much funnier than it should be.
@export var nerve: float = 0.0

@export_group("Scoring")
## Nobody in the field makes an albatross or an eleven; scores are clamped here
## so one absurd roll cannot decide a tournament.
@export var best_hole: int = -3
@export var worst_hole: int = 4


## What this player shoots on one hole, relative to par.
##
## Deterministic in the seed, so a given tournament plays out the same way twice
## and a run can be replayed. `pressure` is 0 for anyone out of contention and 1
## for the outright leader, which is where `nerve` bites.
## `skill_delta` is the tour's, shifted onto the expectation rather than onto
## the resource: these specs are shared library objects, and a field that got
## better by mutating them would stay better for every tournament afterwards.
func score_for_hole(hole_seed: int, pressure: float,
		skill_delta: float = 0.0) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, hole_seed])
	var expected := skill + skill_delta + nerve * clampf(pressure, 0.0, 1.0)
	var rolled := rng.randfn(expected, maxf(steadiness, 0.05))
	return clampi(roundi(rolled), best_hole, worst_hole)
