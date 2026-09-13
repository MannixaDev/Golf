## A piece of equipment you carry for the rest of the run.
##
## Everything about it is data, including what it does: `effects` holds the same
## kind of parameterised sub-resources that cards use.
class_name RelicSpec
extends Resource

enum Rarity { COMMON, UNCOMMON, RARE }

@export_group("Identity")
@export var id: StringName = &"relic"
@export var display_name: String = "Equipment"
@export_multiline var description: String = ""
## Two or three characters drawn in the equipment bar.
@export var short_label: String = "??"
@export var colour: Color = Color("#d8b46a")

@export_group("Value")
@export var rarity: Rarity = Rarity.COMMON
## Asking price in the pro shop.
@export var price: int = 60
## Relative chance of being offered.
@export var weight: float = 10.0

@export_group("Behaviour")
@export var effects: Array[RelicEffect] = []


## Joined rules text from every effect, for tooltips and shop listings.
func effect_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for effect in effects:
		if effect == null:
			continue
		var line := effect.describe()
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return description
	return "  ".join(lines)
