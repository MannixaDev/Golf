## Pick the bag you are going to play with.
##
## Every run in this game started from the same fifteen cards. The route, the
## holes and the shop rolls changed; what you *began* with never did, and in a
## deckbuilder that is the biggest replay lever there is.
##
## What makes these viable rather than a gimmick is the split hand. A bag thin on
## clubs and thick with techniques would have been unplayable a week ago -- you
## would simply have drawn no clubs and been stuck. Four guaranteed club slots is
## what turns "few clubs, many shapes" into a build instead of a soft lock.
##
## Built in code rather than as a scene because it is a row of panels generated
## from however many bags the folder holds, and a .tscn with a fixed number of
## slots would be a lie about that.
class_name GolferScreen
extends Control

signal chosen(bag: DeckList)
signal closed()

const CARD_WIDTH := 300.0
const GAP := 22.0
## Room for everything that is not a club line: the name, the wrapped blurb, the
## two captions, the separation between all of them and the panel's own margins.
## Measured up from 196 after the Grinder's seven clubs pushed its card count out
## through the bottom border a second time.
const PANEL_CHROME := 252.0
## One line per club.
const CLUB_LINE := 24.0


func _ready() -> void:
	# Anchors *and* offsets. Every other screen is a .tscn with anchors_preset
	# 15, which sets both; set_anchors_preset alone left this one at zero size,
	# so the backdrop drew nothing and the row of golfers packed itself into the
	# top left corner rather than centring. It looked centred in a screenshot
	# only because the row happens to be most of the width of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop()

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A little air at the top: with the column centred and the panels as tall as
	# they are, the heading was being clipped by the edge of the screen.
	column.add_child(_spacer(24))
	column.add_child(_heading("WHO IS PLAYING", Typo.DISPLAY, Palette.INK))
	column.add_child(_heading(
		"The same course, the same shops, a different problem to solve.",
		Typo.BODY, Palette.INK_DIM))
	column.add_child(_spacer(14))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	# Every panel as tall as the longest club list, measured rather than picked:
	# at a flat 300 the Grinder's seven clubs pushed its card count out through
	# the bottom border. A row of panels at different heights would be worse.
	var deepest := 0
	for bag in DeckLibrary.all():
		deepest = maxi(deepest, bag.clubs().size())
	var height := PANEL_CHROME + CLUB_LINE * float(deepest)
	for bag in DeckLibrary.all():
		row.add_child(_bag_panel(bag, height))

	column.add_child(_spacer(18))
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200.0, 44.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_override("font", Typo.SEMIBOLD)
	back.add_theme_font_size_override("font_size", Typo.SMALL)
	back.pressed.connect(func() -> void:
		Sfx.play(&"select", -6.0)
		closed.emit())
	column.add_child(back)


## The same ground every other screen stands on. This was a flat ColorRect when
## the picker was written, which made it the one screen in the game sitting on a
## void rather than on a golf course.
func _backdrop() -> void:
	var turf := TurfBackdrop.new()
	turf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(turf)
	# Anchors *and* offsets, after parenting. set_anchors_preset alone left the
	# rect at zero size, so the backdrop drew nothing at all and the picker sat
	# on a flat void -- which measured as a background with no pixel variation
	# whatever while every other screen's ran from 28 to 250.
	turf.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One golfer: who they are, how they talk about themselves, and the clubs they
## own. The club list is the important part -- what a bag can and cannot reach is
## most of what makes it a different run, and it is a fact rather than a mood.
func _bag_panel(bag: DeckList, height: float) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.10, 0.96)
	style.border_color = Color(Palette.GOLD, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	for side in ["left", "right", "top", "bottom"]:
		style.set("content_margin_%s" % side, 18.0)

	var button := Button.new()
	button.custom_minimum_size = Vector2(CARD_WIDTH, height)
	button.add_theme_stylebox_override("normal", style)
	var hovered := style.duplicate() as StyleBoxFlat
	hovered.border_color = Palette.GOLD
	hovered.bg_color = Color(0.11, 0.19, 0.13, 0.98)
	button.add_theme_stylebox_override("hover", hovered)
	button.add_theme_stylebox_override("focus", hovered)
	button.add_theme_stylebox_override("pressed", hovered)
	button.pressed.connect(func() -> void:
		Sfx.play(&"whoosh", -3.0)
		chosen.emit(bag))

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 10)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.offset_left = 18.0
	inner.offset_right = -18.0
	inner.offset_top = 18.0
	inner.offset_bottom = -18.0
	button.add_child(inner)

	inner.add_child(_label(bag.display_name.to_upper(), Typo.STAT, Palette.GOLD))
	inner.add_child(_label(bag.blurb, Typo.SMALL, Palette.INK_DIM, true))
	inner.add_child(_spacer(6))

	var clubs := bag.clubs()
	inner.add_child(_label("IN THE BAG", Typo.MICRO, Color(Palette.INK, 0.45)))
	for club in clubs:
		var reach := ShotProfile.from_card(club).max_reach_yards()
		inner.add_child(_label("%s   ·   %d yd" % [club.title(), int(reach)],
			Typo.SMALL, Palette.INK))

	inner.add_child(_spacer(4))
	var techniques := bag.card_ids.size() - _club_cards(bag)
	inner.add_child(_label(
		"%d cards  ·  %d of them technique" % [bag.card_ids.size(), techniques],
		Typo.MICRO, Color(Palette.INK, 0.45)))
	return button


func _club_cards(bag: DeckList) -> int:
	var count := 0
	for id in bag.card_ids:
		var card := CardLibrary.template(StringName(id))
		if card != null and card.is_shot():
			count += 1
	return count


func _heading(text: String, point: int, colour: Color) -> Label:
	var label := _label(text, point, colour)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


func _label(text: String, point: int, colour: Color,
		wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font",
		Typo.SEMIBOLD if point >= Typo.STAT else Typo.REGULAR)
	label.add_theme_font_size_override("font_size", point)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(CARD_WIDTH - 40.0, 54.0)
	return label


func _spacer(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
