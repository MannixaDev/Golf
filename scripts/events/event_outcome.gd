## What taking one option in an event actually does to your run.
##
## Data rather than code: an event is a .tres holding a few of these, so writing
## a new one is writing prose and numbers, never a script.
class_name EventOutcome
extends Resource

@export_multiline var label: String = "Get on with it"
## Shown after the choice is taken.
@export_multiline var result_text: String = ""

@export_group("Consequences")
@export var winnings_delta: int = 0
## Added to your card. Positive is worse: these are strokes, not points.
@export var strokes_delta: int = 0
## Card added to the bag by id, or empty for none.
@export var add_card_id: StringName = &""
## Remove one random card from the bag.
@export var removes_random_card: bool = false
## Upgrade one random upgradeable card.
@export var upgrades_random_card: bool = false
## Grant a random piece of equipment you do not already own.
@export var grants_relic: bool = false
## Requires this much in winnings to be offered at all.
@export var requires_winnings: int = 0


func is_affordable(winnings: int) -> bool:
	if requires_winnings > 0 and winnings < requires_winnings:
		return false
	# A cost you cannot cover should not be offered as a choice.
	return winnings + winnings_delta >= 0 or winnings_delta >= 0
