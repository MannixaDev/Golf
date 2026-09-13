## Equipment that tells you something, rather than doing something.
##
## The cheapest kind of power to give and often the most interesting to hold:
## nothing about the shot changes, only what you knew when you chose it. Reading
## a green before you are standing on it changes which side of the flag you aim
## at from two hundred yards, which is a real decision you were previously
## making blind.
class_name InsightRelic
extends RelicEffect

## The green's fall is shown while the ball is still short of it, instead of
## only once you are putting.
const GREEN_READ := &"green_read"
## Worked shots draw their bend on the aiming overlay. Draw and Fade hide it on
## purpose, and this is the equipment that stops them.
const SHOT_SHAPE := &"shot_shape"

@export_multiline var summary: String = ""

@export_group("What it shows you")
@export var reads_greens_early: bool = false
@export var reveals_shot_shape: bool = false


func describe() -> String:
	return summary


func grants(insight: StringName) -> bool:
	match insight:
		GREEN_READ:
			return reads_greens_early
		SHOT_SHAPE:
			return reveals_shot_shape
	return false
