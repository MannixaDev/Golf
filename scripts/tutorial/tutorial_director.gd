## Walks a player through one hole, a sentence at a time.
##
## The game narrates well already -- twenty-one status messages, and a swing
## meter that says "release to set" and then "at the left edge" as you use it --
## so the swing teaches itself. What nothing anywhere explained was the bag:
## focus, techniques, combinations, and what the cards in your hand are for. A
## stranger clicking the itch link met all of that on a tee with no introduction.
##
## Deliberately a guided hole rather than a separate tutorial mode. It is the
## real HoleView, the real deck, the real swing; only the hole is fixed and
## somebody is talking. Nothing here reaches into the game to force an outcome --
## the director watches signals and waits. If the player shanks it into a bunker
## the lesson carries on regardless, because a tutorial you can fail is a
## tutorial that was lying about being the game.
class_name TutorialDirector
extends Node

## The lesson is over, one way or another.
signal finished()
## What the panel should be showing, or "" for nothing.
signal prompt_changed(text: String)

## A gentle par four, no water, no wind, one tree: short enough that driver,
## wedge and a putt is a birdie. Fixed so the lesson can talk about the hole in
## front of you rather than in generalities.
const HOLE_SEED := 29
const HOLE_TIER := 0

var _steps: Array[TutorialStep] = []
var _at := -1
var _view: HoleView = null
var _linger := 0.0
var _satisfied := false


func setup(view: HoleView, lesson: Array[TutorialStep]) -> void:
	_view = view
	_steps = lesson

	_view.hand_changed.connect(_on_hand_changed)
	_view.strokes_changed.connect(_on_strokes_changed)
	_view.modifiers_changed.connect(_on_modifiers_changed)
	_view.lie_changed.connect(_on_lie_changed)
	_view.hole_completed.connect(_on_hole_completed)

	_advance()


func _process(delta: float) -> void:
	if _linger > 0.0:
		_linger -= delta
		if _linger <= 0.0 and _satisfied:
			_advance()


## Move to the next line, or finish.
func _advance() -> void:
	_at += 1
	_satisfied = false
	if _at >= _steps.size():
		prompt_changed.emit("")
		finished.emit()
		return
	var step := _steps[_at]
	prompt_changed.emit(step.text)
	_linger = step.linger
	if step.wait == TutorialStep.Wait.NOTHING:
		_satisfy()


## The current step's condition has been met. Waits out whatever is left of the
## linger first, so a line is never pulled off the screen mid-sentence.
func _satisfy() -> void:
	if _satisfied:
		return
	_satisfied = true
	if _linger <= 0.0:
		_advance()


func _current() -> TutorialStep:
	if _at < 0 or _at >= _steps.size():
		return null
	return _steps[_at]


func _waiting_for(wait: int) -> TutorialStep:
	var step := _current()
	return step if step != null and step.wait == wait and not _satisfied else null


# --- Watching ---------------------------------------------------------------

func _on_hand_changed(hand: Array, selected: int, _playable: Array,
		_combining: Array) -> void:
	var step := _waiting_for(TutorialStep.Wait.CARD_SELECTED)
	if step == null or selected < 0 or selected >= hand.size():
		return
	var card: CardData = hand[selected]
	if card != null and card.id == step.card_id:
		_satisfy()


func _on_strokes_changed(strokes: int) -> void:
	var step := _waiting_for(TutorialStep.Wait.STROKES_PLAYED)
	if step != null and strokes >= step.strokes:
		_satisfy()


func _on_modifiers_changed(names: Array, combinations: PackedStringArray) -> void:
	var step := _waiting_for(TutorialStep.Wait.TECHNIQUE_PLAYED)
	if step != null:
		# Matched on the title rather than the id, because the title is what the
		# heads-up display is showing and what the lesson just told them to play.
		var card := CardLibrary.template(step.card_id)
		if card != null and names.has(card.title()):
			_satisfy()
		return
	if _waiting_for(TutorialStep.Wait.COMBINATION_LIVE) != null \
			and not combinations.is_empty():
		_satisfy()


func _on_lie_changed(surface: SurfaceType) -> void:
	var step := _waiting_for(TutorialStep.Wait.ON_THE_GREEN)
	# Asked by id rather than by a helper, because SurfaceType has none and the
	# putting surface is the one lie the whole game agrees on the name of.
	if step != null and surface != null and surface.id == &"green":
		_satisfy()


func _on_hole_completed(_strokes: int, _par: int, _holed: bool) -> void:
	# Whatever it was waiting for, the hole is over and the lesson with it.
	if _waiting_for(TutorialStep.Wait.HOLED) != null:
		_satisfy()
		return
	prompt_changed.emit("")
	finished.emit()
