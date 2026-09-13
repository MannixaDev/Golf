## Measures the real room the two body labels get, rather than trusting arithmetic.
##
## Throwaway diagnostic: lays a card out for real, lets the container settle over
## a few frames, and reports where every row actually ended up.
extends SceneTree

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
const IDS := ["driver", "mulligan"]

var _view: CardView = null
var _frames := 0
var _index := 0


func _initialize() -> void:
	_view = CARD_SCENE.instantiate()
	root.add_child(_view)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return false

	# Two frames per card: one to set it up, one to read the settled layout.
	if _frames % 2 == 0:
		if _index >= IDS.size():
			quit(0)
			return true
		var card := CardLibrary.copy(IDS[_index])
		_view.setup(card, 0)
		_view.set_state(false, true)
		return false

	var id: String = IDS[_index]
	var column: VBoxContainer = _view.get_node("Body/Column")
	print("=== %s ===" % id)
	print("  card       h=%.0f" % _view.size.y)
	print("  column     y=%.0f h=%.0f" % [column.position.y, column.size.y])
	for child in column.get_children():
		var c := child as Control
		print("  %-12s y=%.0f h=%.0f visible=%s" % [
			c.name, c.position.y, c.size.y, c.visible])
	_index += 1
	return false
