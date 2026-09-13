## Asserts every card's text fits inside the card, at every size it is drawn at.
##
## Cards are authored as data, so nobody writing a new one should have to count
## characters. This measures the real wrapped height of every card in the game,
## base and upgraded, and fails if anything would spill past its own border.
extends SceneTree

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")

var failures := 0
var _view: CardView = null


func _initialize() -> void:
	_view = CARD_SCENE.instantiate()
	root.add_child(_view)


func _process(_delta: float) -> bool:
	print("=== card text fit ===")

	var ids: Array = CardLibrary.all_ids()
	ids.sort()
	var shrunk := 0
	var trimmed := 0

	for id in ids:
		for upgraded in [false, true]:
			var card := CardLibrary.copy(id)
			if upgraded:
				if not card.can_upgrade():
					continue
				card.upgrade()

			_view.setup(card, 0)
			_view.set_state(false, true)

			var detail: Label = _view.get_node("Body/Column/Detail")
			var description: Label = _view.get_node("Body/Column/Description")
			var detail_size := _font_size(detail)

			# Asked of the card itself, so this cannot drift from what the card
			# actually did when it laid its own text out.
			var budget := _view.body_budget()
			var used := _view.measured_body_height()

			if detail_size < CardView.DETAIL_SIZE:
				shrunk += 1
			if not description.visible:
				trimmed += 1

			var label := "%s%s" % [card.id, "+" if upgraded else ""]
			if used > budget:
				print("  OVERFLOW  %-18s %.0f of %.0f" % [label, used, budget])
				_expect(false, "%s does not fit its card" % label)
			else:
				print("  %-18s %2.0f of %2.0f  rules %dpt%s" % [
					label, used, budget, detail_size,
					"" if description.visible else "  (flavour dropped)"])

			# The rules are the part that must never be lost.
			_expect(detail.visible or card.effect_text() == "",
				"%s hid its rules text" % label)

	print("  %d cards measured, %d shrunk to fit, %d dropped their flavour line"
		% [ids.size(), shrunk, trimmed])

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


func _font_size(label: Label) -> int:
	return label.get_theme_font_size("font_size")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
