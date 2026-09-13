## One card on screen.
##
## Presentation only. It reads a CardData and reports clicks; it never decides
## whether a card may be played.
class_name CardView
extends Control

signal clicked(slot: int)

const LIFT_SELECTED := 34.0
const LIFT_HOVER := 16.0
const SETTLE_SPEED := 14.0
## A chosen card sits slightly proud of the rest of the hand.
const SCALE_SELECTED := 1.05
const SCALE_HOVER := 1.02

## Wrapping width available to the two body labels, matching their minimum width
## in the scene.
const TEXT_WIDTH := 114.0
## Vertical room those two labels have to share, once the header, the type line
## and the separations have taken their cut of the card. A shot card also spends
## some on its yardage, so it has less to play with. Both figures are measured
## from a laid-out card by `tools/card_space_probe.gd`, not estimated -- and they
## are font-specific, so re-run that probe after any change to the type system.
## Switching from the built-in fallback to Lato gave every card room back.
const TEXT_BUDGET_SHOT := 75.0
const TEXT_BUDGET_SUPPORT := 98.0
## Rules text may shrink to this before flavour gets sacrificed instead.
const DETAIL_SIZE := 12
const DETAIL_SIZE_MIN := 10
const DESCRIPTION_SIZE := 11
const DESCRIPTION_SIZE_MIN := 8

## Background tint per card type, so a hand reads at a glance.
const TYPE_COLOURS := {
	CardData.CardType.SHOT: Color("#1a2e1f"),
	CardData.CardType.TECHNIQUE: Color("#18283a"),
	CardData.CardType.UTILITY: Color("#302518"),
}
const TYPE_ACCENTS := {
	CardData.CardType.SHOT: Palette.ACCENT_SHOT,
	CardData.CardType.TECHNIQUE: Palette.ACCENT_TECHNIQUE,
	CardData.CardType.UTILITY: Palette.ACCENT_UTILITY,
}
const TYPE_NAMES := {
	CardData.CardType.SHOT: "SHOT",
	CardData.CardType.TECHNIQUE: "TECHNIQUE",
	CardData.CardType.UTILITY: "UTILITY",
}

@onready var _background: Panel = $Background
@onready var _art: CardArt = $Art
@onready var _cost: Label = $Body/Column/Header/Cost
@onready var _name: Label = $Body/Column/Header/Name
@onready var _type: Label = $Body/Column/Type
@onready var _stat: Label = $Body/Column/Stat
@onready var _detail: Label = $Body/Column/Detail
@onready var _description: Label = $Body/Column/Description

var card: CardData = null
var slot: int = -1
var selected: bool = false
var playable: bool = true

var home_position: Vector2 = Vector2.ZERO
## Held back before this card starts moving, so a fresh hand deals in one card
## at a time rather than arriving as a block.
var settle_delay: float = 0.0
var _hovered: bool = false
var _style: StyleBoxFlat = null
## Set by whatever is laying these out, so a compact grid and a hand can share
## the same hover and selection behaviour without fighting over `scale`.
var _layout_scale: float = 1.0


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	# Own the stylebox so tinting this card does not tint every other card.
	var base: StyleBox = _background.get_theme_stylebox("panel")
	_style = (base.duplicate() as StyleBoxFlat) if base is StyleBoxFlat else StyleBoxFlat.new()
	_background.add_theme_stylebox_override("panel", _style)
	_refresh()


## Base size for this card, before hover and selection are applied on top.
func set_layout_scale(value: float) -> void:
	_layout_scale = value
	scale = Vector2.ONE * value


func setup(new_card: CardData, new_slot: int) -> void:
	card = new_card
	slot = new_slot
	if is_node_ready():
		_refresh()


func set_state(is_selected: bool, is_playable: bool) -> void:
	selected = is_selected
	playable = is_playable
	if is_node_ready():
		_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		Sfx.play(&"card" if playable else &"select", -4.0)
		clicked.emit(slot)
		accept_event()


func _process(delta: float) -> void:
	if settle_delay > 0.0:
		settle_delay -= delta
		return

	var lift := 0.0
	var target_scale := 1.0
	if selected:
		lift = LIFT_SELECTED
		target_scale = SCALE_SELECTED
	elif _hovered:
		lift = LIFT_HOVER
		target_scale = SCALE_HOVER

	var weight := clampf(SETTLE_SPEED * delta, 0.0, 1.0)
	position = position.lerp(home_position - Vector2(0.0, lift), weight)

	# Scaled about the middle of the bottom edge, so a card grows upward out of
	# the hand rather than drifting sideways.
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = scale.lerp(Vector2.ONE * target_scale * _layout_scale, weight)


func _refresh() -> void:
	if card == null:
		hide()
		return
	show()

	_cost.text = str(card.effective_cost())
	_name.text = card.title()
	# An upgraded card takes a new name, which on its own tells you nothing --
	# "Big Dog" and "Driver" look like two different clubs rather than one club
	# and its better self. It says so now, and wears a gold border to match.
	_type.text = TYPE_NAMES.get(card.type, "CARD")
	if card.upgraded:
		_type.text += "  ·  UPGRADED"
	_description.text = card.description

	if card.is_shot():
		# Shot cards lead with the number that matters: how far it goes.
		_stat.show()
		_stat.text = card.stat_line()
		_detail.text = card.detail_line()
	else:
		# Techniques and utilities lead with what they do.
		_stat.hide()
		_detail.text = card.effect_text()
	_fit_body_text(card.is_shot())

	var accent: Color = TYPE_ACCENTS.get(card.type, Color.WHITE)
	# The border carries the upgrade, the accent still carries the card type, so
	# a hand reads as both "what kind of card" and "which of these are better".
	var edge: Color = Palette.GOLD if card.upgraded else accent
	_style.bg_color = TYPE_COLOURS.get(card.type, Color("#242424"))
	_style.border_color = edge if selected else edge.darkened(0.35)
	var border := 3 if (selected or card.upgraded) else 2
	_style.border_width_left = border
	_style.border_width_top = border
	_style.border_width_right = border
	_style.border_width_bottom = border

	_art.setup(card, Palette.GOLD if card.upgraded else accent)
	_type.add_theme_color_override("font_color",
		Palette.GOLD if card.upgraded else accent.darkened(0.15))
	_stat.add_theme_color_override("font_color", accent.lightened(0.35))

	modulate = Color.WHITE if playable else Color(0.55, 0.55, 0.58, 0.85)


## Make the words fit the card rather than hoping they do.
##
## Cards are authored as data, so nobody writing a new one should have to count
## characters to keep it inside its own border. The rules text shrinks first, and
## if that is still not enough the flavour line is dropped: what a card *does* is
## worth more than the joke underneath it.
func _fit_body_text(is_shot: bool) -> void:
	var budget := TEXT_BUDGET_SHOT if is_shot else TEXT_BUDGET_SUPPORT
	var detail_size := DETAIL_SIZE
	var description_size := DESCRIPTION_SIZE

	while detail_size > DETAIL_SIZE_MIN:
		if _text_height(_detail, _detail.text, detail_size) <= budget:
			break
		detail_size -= 1

	var used := _text_height(_detail, _detail.text, detail_size)
	var remaining := budget - used

	while description_size > DESCRIPTION_SIZE_MIN:
		if _text_height(_description, _description.text, description_size) <= remaining:
			break
		description_size -= 1

	# Still no room: the flavour goes, the rules stay.
	_description.visible = _text_height(
		_description, _description.text, description_size) <= remaining

	_detail.add_theme_font_size_override("font_size", detail_size)
	_description.add_theme_font_size_override("font_size", description_size)


## How tall this text wraps to at a given size, measured rather than guessed.
##
## The font tells you how tall the glyphs are; the Label then adds its own
## `line_spacing` between every pair of lines. Measuring the font alone
## under-reports by a few pixels per line, which is invisible on two lines and
## pushes a seven-line card straight out through its own bottom edge.
func _text_height(label: Label, text: String, font_size: int) -> float:
	if text == "":
		return 0.0
	# The label's own font, never ThemeDB's fallback: the game ships Lato, and
	# measuring one typeface while drawing another put text through the border.
	var font := label.get_theme_font("font")
	if font == null:
		return 0.0

	var measured := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, TEXT_WIDTH, font_size)
	var line_height := maxf(font.get_height(font_size), 1.0)
	var lines := maxi(1, int(round(measured.y / line_height)))
	return measured.y + label.get_theme_constant("line_spacing") * (lines - 1)


## Height the body text actually occupies as currently laid out, and the room it
## was given. Used by the fit check so it measures the same thing this does.
func measured_body_height() -> float:
	var used := _text_height(_detail, _detail.text,
		_detail.get_theme_font_size("font_size"))
	if _description.visible:
		used += _text_height(_description, _description.text,
			_description.get_theme_font_size("font_size"))
	return used


func body_budget() -> float:
	if card != null and card.is_shot():
		return TEXT_BUDGET_SHOT
	return TEXT_BUDGET_SUPPORT
