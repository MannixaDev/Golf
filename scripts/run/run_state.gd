## Everything that persists across a run.
##
## The failure condition is golf's own: your score against par accumulates, and
## if you drift further over than the cut allows, you miss the cut and the run is
## finished. Bogeys are damage, birdies heal, and a Signature Hole hits hard
## because par on it is genuinely difficult.
class_name RunState
extends RefCounted

signal changed()
signal run_ended(won: bool)

## The cut, as a share of the field that goes home. Real tournaments cut on
## position, not on a number, and so does this one now.
##
## A fixed line at +8 was the whole of the pressure in this game and it was not
## pressure at all: a genuinely bad round still came in at +2 and cleared it by
## six. A position moves every hole whether you played well or not, and the
## bottom third going home scales itself against however the field is playing.
const CUT_SHARE := 0.34
## Which hole the cut falls after, as a share of the round.
const CUT_AFTER := 0.55
## Kept so old saves and the harnesses still have a number to talk about.
@warning_ignore("unused_signal")
const DEFAULT_CUT := 8

## Starting purse. Enough to buy something early, not enough to buy everything.
const STARTING_WINNINGS := 40

var cut_line: int = DEFAULT_CUT
## The tournament you are playing in. Injected by the run layer, because the
## field belongs to the run rather than to the score.
var leaderboard: Leaderboard = null
## Which rung of the ladder this round is being played on. Never null in a real
## run; the harnesses that do not care leave it unset and get the opening tour.
var tour: TourSpec = null
## Holes in the whole round, so the cut knows when halfway is.
var round_holes: int = 9
var made_the_cut: bool = false
var holes_played: int = 0
var total_strokes: int = 0
var total_par: int = 0
var finished: bool = false
var won: bool = false

var winnings: int = STARTING_WINNINGS
var relics: Array[RelicSpec] = []

## The card itself: one entry per hole played, in order, as
## {par, strokes, place}. Kept because a round of golf is a scorecard, and the
## game was throwing every hole away the moment it had added it to a running
## total.
var card: Array[Dictionary] = []
## Strokes clawed back between holes, at the halfway house or by equipment.
## Held apart from the card rather than smuggled into a hole's score: you cannot
## un-play a hole, and a card that quietly disagrees with the total is worse
## than no card at all.
var strokes_clawed_back: int = 0


## What the card adds up to, independent of the running total. Anything that
## edits your score has to leave these two agreeing.
func card_strokes() -> int:
	var total := 0
	for line in card:
		total += int(line["strokes"])
	return total - strokes_clawed_back


func card_par() -> int:
	var total := 0
	for line in card:
		total += int(line["par"])
	return total


func score_to_par() -> int:
	return total_strokes - total_par


## "+3", "-1" or "level", the way a leaderboard would show it.
func score_text() -> String:
	var score := score_to_par()
	if score == 0:
		return "level"
	return "%+d" % score


func strokes_remaining() -> int:
	return cut_line - score_to_par()


## A sit-down at the halfway house. Claws back strokes you have dropped, and
## stops at level: you cannot rest your way under par, because resting is not
## golf. See the note on Main.REST_STROKES.
##
## Returns how many strokes it actually took off, so the screen can say.
func rest(strokes: int) -> int:
	var recovered := mini(strokes, maxi(score_to_par(), 0))
	if recovered <= 0:
		return 0
	total_strokes -= recovered
	strokes_clawed_back += recovered
	# The board hears about it too. Two numbers describing the same round are
	# allowed to disagree exactly never.
	if leaderboard != null:
		leaderboard.adjust_player(-recovered)
	changed.emit()
	return recovered


func record_hole(strokes: int, par: int) -> void:
	holes_played += 1
	total_strokes += strokes
	total_par += par
	if leaderboard != null:
		leaderboard.record_hole(strokes - par)
	card.append({
		"par": par,
		"strokes": strokes,
		"place": leaderboard.player_place() if leaderboard != null else 0,
	})
	changed.emit()

	if _missed_the_cut():
		finished = true
		won = false
		run_ended.emit(false)
	elif holes_played == cut_hole():
		made_the_cut = true


## The hole after which the bottom of the field goes home.
func cut_hole() -> int:
	return maxi(1, roundi(round_holes * CUT_AFTER))


## Bottom third of the field at the halfway point and you are on the road.
func _missed_the_cut() -> bool:
	if leaderboard == null or holes_played != cut_hole():
		return false
	var field := leaderboard.field_size()
	return leaderboard.player_place() > ceili(field * (1.0 - cut_share()))


## How many of the field survive the cut.
func cut_place() -> int:
	if leaderboard == null:
		return 0
	return ceili(leaderboard.field_size() * (1.0 - cut_share()))


## How much of the field goes home. The tour tightens it as you climb.
func cut_share() -> float:
	return tour.cut_share if tour != null else CUT_SHARE


## Where you stand, for the readouts.
func position_text() -> String:
	if leaderboard == null:
		return score_text()
	return leaderboard.player_position_text()


# --- Winnings -------------------------------------------------------------

func add_winnings(amount: int) -> void:
	winnings = maxi(0, winnings + amount)
	changed.emit()


func can_afford(price: int) -> bool:
	return winnings >= price


## Returns false and changes nothing if you cannot cover it.
func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	winnings -= price
	changed.emit()
	return true


# --- Relics ---------------------------------------------------------------

func add_relic(relic: RelicSpec) -> void:
	if relic == null or has_relic(relic.id):
		return
	relics.append(relic)
	changed.emit()


func has_relic(id: StringName) -> bool:
	for relic in relics:
		if relic.id == id:
			return true
	return false


func finish_run(victory: bool) -> void:
	if finished:
		return
	finished = true
	won = victory
	changed.emit()
	run_ended.emit(victory)


func summary() -> String:
	if holes_played == 0:
		return "No holes played."
	return "%d holes, %d strokes, %s to par." % [holes_played, total_strokes, score_text()]


## Golf's name for a score relative to par, shared by the hole result panel and
## the reward table so the two can never disagree about what you just did.
static func score_name(strokes: int, par: int) -> String:
	if strokes == 1:
		return "Hole in One"
	match strokes - par:
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		3: return "Triple Bogey"
	return "%+d" % (strokes - par)
