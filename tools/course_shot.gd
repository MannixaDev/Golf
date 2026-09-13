## Dev-only: render the worst-case card faces so the text fitting can be judged
## by eye rather than only by measurement.
extends SceneTree

var frames := 0
var main: Node
var stage := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _grab(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = root.get_texture().get_image()
	image.save_png("user://" + file_name)
	print("saved: " + file_name)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 32:
		return false
	frames = 0

	if stage == 0:
		# The longest rules text in the game, base and upgraded, side by side.
		var cards: Array = []
		for entry in [["punch", false], ["punch", true], ["ball_retriever", false],
				["stinger", true], ["sand_wedge", false], ["mulligan", false]]:
			var card := CardLibrary.copy(StringName(entry[0]))
			if entry[1]:
				card.upgrade()
			cards.append(card)

		var screen = load("res://scenes/ui/card_picker_screen.tscn").instantiate()
		main._swap_screen(screen)
		screen.show_cards("Card faces", "The longest text in the game.", cards)
		stage = 1
		return false

	if stage == 1:
		_grab("m8_cards.png")
		return true
	return false
