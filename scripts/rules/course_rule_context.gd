## What a course rule may know, and what it may ask the hole to do.
##
## Same pattern as EffectContext and RelicContext: rules read a snapshot and
## write their intent back, so a rule can be tested on its own and the hole stays
## the only thing that actually changes anything.
class_name CourseRuleContext
extends RefCounted

## 1 for the tee shot, 2 for the next, and so on.
var stroke_number: int = 1
var strokes_taken: int = 0
## Shared so a rule's randomness is reproducible with the hole it belongs to.
var rng: RandomNumberGenerator = null

## Lines the hole should show the player. Rules announce themselves rather than
## quietly changing the game underneath you.
var messages: PackedStringArray = PackedStringArray()
## Set when the course has been rearranged and needs redrawing.
var course_changed: bool = false
## Set when the weather has changed and the readout needs refreshing.
var conditions_changed: bool = false


func announce(text: String) -> void:
	messages.append(text)
