## A single stop on the route, once the generator has placed it.
##
## The spec says what kind of place this is; this says where it sits, what it
## connects to, and whether the player has been there.
class_name MapNode
extends RefCounted

enum State { LOCKED, AVAILABLE, VISITED }

var id: int = -1
var spec: MapNodeSpec = null
## Column across the map. 0 is the first tee.
var layer: int = 0
## Position within its column, 0 at the top.
var slot: int = 0
## 0..1 down the column, so columns of different sizes can be compared.
var offset: float = 0.5
## Where to draw it, in map pixels.
var position: Vector2 = Vector2.ZERO
## Ids of the nodes this leads on to.
var next_ids: Array[int] = []
var previous_ids: Array[int] = []

var state: State = State.LOCKED
## Seed for the hole this node generates, so revisiting shows the same hole.
var hole_seed: int = 0


func plays_hole() -> bool:
	return spec != null and spec.plays_hole


func difficulty() -> int:
	return spec.difficulty if spec != null else 1


func display_name() -> String:
	return spec.display_name if spec != null else "Stop"
