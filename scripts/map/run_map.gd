## The whole route for one run, plus where the player currently stands.
##
## Pure data and navigation. It knows nothing about drawing or about golf.
class_name RunMap
extends RefCounted

signal changed()

var nodes: Array[MapNode] = []
## Node ids grouped by column.
var layers: Array = []
## True for a golf column, false for a service column, one per layer. Set by the
## generator from the round length so nothing downstream has to infer it.
var kinds: Array[bool] = []
## -1 before the first tee shot has been chosen.
var current_id: int = -1
var finished: bool = false


func node_by_id(id: int) -> MapNode:
	if id < 0 or id >= nodes.size():
		return null
	return nodes[id]


func current() -> MapNode:
	return node_by_id(current_id)


func layer_count() -> int:
	return layers.size()


## Nodes the player may choose right now: the whole first column before anything
## has been played, otherwise wherever the current node leads.
func available_ids() -> Array[int]:
	var result: Array[int] = []
	if finished:
		return result
	if current_id == -1:
		for id in layers[0]:
			result.append(int(id))
		return result
	var node := current()
	if node == null:
		return result
	for id in node.next_ids:
		result.append(id)
	return result


func is_available(id: int) -> bool:
	return available_ids().has(id)


## Commit to a node. Returns false if it was not a legal move.
func travel_to(id: int) -> bool:
	if not is_available(id):
		return false
	var node := node_by_id(id)
	if node == null:
		return false

	node.state = MapNode.State.VISITED
	current_id = id
	_refresh_states()
	changed.emit()
	return true


func is_final(id: int) -> bool:
	var node := node_by_id(id)
	return node != null and node.layer == layers.size() - 1


func _refresh_states() -> void:
	var reachable := available_ids()
	for node in nodes:
		if node.state == MapNode.State.VISITED:
			continue
		node.state = MapNode.State.AVAILABLE if reachable.has(node.id) \
			else MapNode.State.LOCKED


## Call once after generation so the opening column is selectable.
func begin() -> void:
	current_id = -1
	finished = false
	for node in nodes:
		node.state = MapNode.State.LOCKED
	_refresh_states()
	changed.emit()


func path_taken() -> Array[int]:
	var path: Array[int] = []
	for node in nodes:
		if node.state == MapNode.State.VISITED:
			path.append(node.id)
	return path
