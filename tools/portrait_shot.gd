## Dev-only: photographs the two places the Driron is looked at.
##
## Run *without* --headless -- there is nothing to capture otherwise. The club
## is drawn rather than imported, and the shape control appears for exactly one
## card in the game, so in both cases the only way to know whether it came out
## right is to look at it.
extends SceneTree

const FUSION_SCREEN := preload("res://scenes/ui/fusion_screen.tscn")
const HOLE_SCREEN := preload("res://scenes/run/hole_screen.tscn")
## Long enough for the reveal to finish playing itself in.
const REVEAL_FRAMES := 240
## And for a hole to finish its flyover and settle.
const HOLE_FRAMES := 220

var frames := 0
var stage := 0
var _screen: Node


func _initialize() -> void:
	_screen = FUSION_SCREEN.instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	frames += 1
	if DisplayServer.get_name() == "headless":
		print("nothing to photograph: run this one with a window")
		return true

	match stage:
		0:
			if frames == 1:
				# Not in _initialize: the tree is not running there yet, so the
				# screen's @onready references are all still null.
				_screen.show_fusion(_made(), _wood(), _iron())
			elif frames >= REVEAL_FRAMES:
				_grab("driron.png")
				_screen.queue_free()
				_screen = HOLE_SCREEN.instantiate()
				_screen.setup(HoleGenerator.generate(4242, 2, 1),
					Deck.new([_made(), CardLibrary.copy(&"putter")]))
				root.add_child(_screen)
				frames = 0
				stage = 1
		1:
			if frames == 2:
				_screen.begin()
			elif frames == 4:
				# Staged and shaped, so the row is showing and the aiming
				# overlay is drawing the bend that was just asked for.
				var view: HoleView = _screen.get_node("HoleView")
				for i in view.deck.hand.size():
					if view.deck.hand[i].id == ClubFusion.RESULT_ID:
						view.select_card(i)
						view.set_shot_shape(-1)
						break
			elif frames >= HOLE_FRAMES:
				_grab("driron_shape.png")
				return true
	return false


func _made() -> CardData:
	return ClubFusion.fuse(_wood(), _iron())


func _wood() -> CardData:
	return CardLibrary.copy(&"driver")


func _iron() -> CardData:
	return CardLibrary.copy(&"iron_5")


func _grab(file_name: String) -> void:
	root.get_texture().get_image().save_png("user://" + file_name)
	print("wrote %s" % ProjectSettings.globalize_path("user://" + file_name))
