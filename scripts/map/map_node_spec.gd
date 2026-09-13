## One kind of place you can visit on the route.
##
## Everything the generator needs to decide where a node may appear, and
## everything the map needs to draw it, lives here as data. Adding a new stop on
## the course is a .tres file: the generator reads weights and placement rules
## from these rather than hard-coding a table of node types.
class_name MapNodeSpec
extends Resource

enum Shape { CIRCLE, DIAMOND, SQUARE, TRIANGLE, HEXAGON, STAR }

@export_group("Identity")
@export var id: StringName = &"node"
@export var display_name: String = "Stop"
## Two to six characters, drawn under the node on the map.
@export var short_label: String = "?"
@export_multiline var description: String = ""

@export_group("Appearance")
@export var colour: Color = Color("#7ec96a")
@export var shape: Shape = Shape.CIRCLE

@export_group("Behaviour")
## True if visiting this plays a golf hole.
@export var plays_hole: bool = false
## Feeds the hole generator. 0 gentle, 4 boss.
@export var difficulty: int = 1

@export_group("Placement")
## Relative chance of being chosen. Zero means the generator never picks it and
## it must be placed explicitly, as the boss and the opening holes are.
@export var weight: float = 0.0
## Never appears before this layer, so the run opens gently.
@export var min_layer: int = 0
## Never appears after this layer. -1 for no limit.
@export var max_layer: int = -1
## Cap across a whole run. 0 for no cap.
@export var max_per_run: int = 0
## Refuse to place this directly after another of the same kind.
@export var avoid_repeat: bool = true
