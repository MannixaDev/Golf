## The end of a round: the card, what it was worth, and where it leaves you.
##
## Replaces a two-line notice. A round of golf ends with somebody handing you a
## scorecard, and now that the ladder makes finishing one mean something, the
## ending is worth more than a sentence.
class_name ScorecardScreen
extends Control

signal continued()

@onready var _title: Label = %CardTitle
@onready var _subtitle: Label = %CardSubtitle
@onready var _card: ScorecardView = %Card
@onready var _footnote: Label = %CardFootnote
@onready var _unlock: Label = %CardUnlock
@onready var _button: Button = %CardButton


func _ready() -> void:
	_button.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		continued.emit())
	_button.grab_focus()


func show_card(run: RunState, tour: TourSpec, made_the_end: bool,
		opened: TourSpec) -> void:
	var place := run.leaderboard.player_place() if run.leaderboard != null else 0
	var tour_name := tour.display_name if tour != null else "the tour"

	if made_the_end:
		_title.text = ("%s PLACE" % Leaderboard.ordinal(place).to_upper()) \
			if place > 0 else "ROUND COMPLETE"
		_title.add_theme_color_override("font_color",
			Palette.GOLD if place == 1 else Palette.INK)
		_subtitle.text = "%s  ·  %s  ·  %d holes" % [
			tour_name, run.score_text(), run.holes_played]
	else:
		_title.text = "MISSED THE CUT"
		_title.add_theme_color_override("font_color", Palette.DANGER)
		_subtitle.text = "%s  ·  %s when only the top %d went through" % [
			tour_name, run.position_text(), run.cut_place()]

	_card.set_card(run.card, tour_name, run.strokes_clawed_back)

	var notes: PackedStringArray = PackedStringArray()
	notes.append("%d in winnings" % run.winnings)
	notes.append("%d %s" % [run.relics.size(),
		"piece of equipment" if run.relics.size() == 1 else "pieces of equipment"])
	if run.strokes_clawed_back > 0:
		# Said out loud, because the card will not add up otherwise and a card
		# that does not add up looks like a bug however true the total is.
		notes.append("%d clawed back off the card" % run.strokes_clawed_back)
	_footnote.text = "  ·  ".join(notes)

	if opened != null:
		_unlock.show()
		_unlock.text = "%s has opened up.  %s" % [opened.display_name, opened.blurb]
		# Gold, not the tour's own colour: opening a rung is the best news the
		# screen has, and some of the tours are a red that reads as a warning.
		_unlock.add_theme_color_override("font_color", Palette.GOLD)
	else:
		_unlock.hide()

	_button.text = "Back to the clubhouse" if made_the_end else "Try again"
