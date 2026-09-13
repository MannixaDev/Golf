## What a finished hole turned out to be worth.
##
## The payout used to be computed and banked in one line, which left equipment
## no way to care about how you scored -- only about how the ball flew. A relic
## that pays you for birdies changes what you are willing to risk on a par 5,
## and that is a different decision from a relic that makes the ball fly
## straighter.
##
## The run layer builds one, passes it round the bag, then applies it.
class_name HoleReward
extends RefCounted

var strokes: int = 0
var par: int = 4
## Winnings before the bag has its say.
var winnings: int = 0
## Strokes taken back off the card. Claws back what has been dropped and never
## improves a round that is already level, exactly like resting does -- score
## against par is this game's health bar, so anything that heals also flatters
## the card unless it stops at level.
var strokes_back: int = 0
## Lines shown with the payout, so a relic that fired says so.
var notes: PackedStringArray = PackedStringArray()


func _init(shots: int = 0, hole_par: int = 4, paid: int = 0) -> void:
	strokes = shots
	par = hole_par
	winnings = paid


func to_par() -> int:
	return strokes - par


func is_birdie_or_better() -> bool:
	return to_par() <= -1


func note(line: String) -> void:
	if line != "":
		notes.append(line)
