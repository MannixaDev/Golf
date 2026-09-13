## A named set of special rules, and any changes it wants made to the hole itself.
##
## Elite holes draw a light one, the closing hole draws a heavy one. Both come
## from the same library, filtered by difficulty, so adding either is a .tres.
class_name CourseRuleSet
extends Resource

@export_group("Identity")
@export var id: StringName = &"rules"
@export var display_name: String = "Local Rules"
@export_multiline var description: String = ""
@export var colour: Color = Color("#c9538f")

@export_group("Placement")
## Lowest hole difficulty this may appear on. Elites are 3, the closer is 4.
@export var min_difficulty: int = 4
@export var weight: float = 10.0

@export_group("Rules")
@export var rules: Array[CourseRule] = []

@export_group("Hole overrides")
## Force a par, or 0 to leave the generator alone.
@export var force_par: int = 0
## Force a length in yards, or 0 to leave it alone.
@export var force_length_yards: float = 0.0
## Extra greenside trouble, on top of whatever the tier already brings.
@export var extra_greenside_hazards: int = 0
## Multiplies the fairway width. Below 1 makes a hole meaner without more sand.
@export var fairway_scale: float = 1.0


func rules_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for rule in rules:
		if rule == null:
			continue
		var line := rule.describe()
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return description
	return "  ".join(lines)
