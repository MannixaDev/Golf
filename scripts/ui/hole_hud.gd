## All screen-space UI for a hole.
##
## Purely a listener: it never reaches into the golf simulation, it only reacts
## to the signals HoleView publishes. The one thing it sends back is which card
## the player clicked.
class_name HoleHUD
extends Control

signal restart_pressed()
signal card_clicked(slot: int)
## The player asked for a draw, a straight one, or a fade. -1, 0, 1.
signal shape_chosen(shape: int)
## The on-screen swing control, for devices with no button to hold.
signal swing_pressed()
signal swing_released()

@onready var _hole_label: Label = %HoleLabel
@onready var _par_label: Label = %ParLabel
@onready var _strokes_label: Label = %StrokesLabel
@onready var _distance_label: Label = %DistanceLabel
@onready var _draw_label: Label = %DrawLabel
@onready var _discard_label: Label = %DiscardLabel
@onready var _focus_label: Label = %FocusLabel
@onready var _relic_row: HBoxContainer = %RelicRow
@onready var _rules_panel: PanelContainer = %RulesPanel
@onready var _rules_title: Label = %RulesTitle
@onready var _rules_body: Label = %RulesBody
@onready var _power_meter: PowerMeter = %PowerMeter
@onready var _apex_label: Label = %ApexLabel
@onready var _swing_button: Button = %SwingButton
@onready var _help_label: Label = %HelpLabel
@onready var _shape_row: HBoxContainer = %ShapeRow
@onready var _shape_buttons: Array[Button] = [%DrawButton, %StraightButton,
	%FadeButton]
@onready var _power_title: Label = %PowerTitle
@onready var _prep_label: Label = %PrepLabel
## The swing meter, so the two lines above it can be kept off it. Its height
## changes with whether the selected club can be worked, so a fixed offset gets
## it wrong half the time -- and the prep line was already being drawn straight
## across the meter before any of this.
@onready var _power_panel: Control = $PowerPanel
## Built here rather than in the scene so the prep line keeps its own layout and
## this one simply sits above it.
@onready var _combo_label: Label = _make_combo_label()
## The lesson's panel. Built here rather than in the scene because it only exists
## during the tutorial, and a node the other ninety-nine per cent of the game
## carries around hidden is a node somebody will eventually wonder about.
var _lesson_panel: PanelContainer = null
var _lesson_label: Label = null
@onready var _lie_label: Label = %LieLabel
@onready var _lie_summary: Label = %LieSummary
@onready var _slope_row: HBoxContainer = %SlopeRow
@onready var _slope_arrow: WindArrow = %SlopeArrow
@onready var _slope_label: Label = %SlopeLabel
@onready var _wind_arrow: WindArrow = %WindArrow
@onready var _wind_label: Label = %WindLabel
@onready var _status_label: Label = %StatusLabel
@onready var _hand_view: HandView = %HandView
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_title: Label = %ResultTitle
@onready var _result_detail: Label = %ResultDetail
@onready var _restart_button: Button = %RestartButton

var _status_tween: Tween
## Whether a finger is the only pointer, so the prompts say the right thing.
var _touch_ui: bool = false


func _ready() -> void:
	_result_panel.hide()
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	_hand_view.card_clicked.connect(func(slot: int) -> void: card_clicked.emit(slot))
	# Buttons rather than a keypress: this game is played with a mouse, and a
	# shape you have to know a key for is a shape nobody uses.
	for i in _shape_buttons.size():
		var shape := i - 1
		_shape_buttons[i].pressed.connect(func() -> void: shape_chosen.emit(shape))

	# Held and released rather than clicked: the power meter charges for as long
	# as you hold, which is the same gesture with a thumb as with a mouse.
	_swing_button.button_down.connect(func() -> void: swing_pressed.emit())
	_swing_button.button_up.connect(func() -> void: swing_released.emit())



func set_hole(hole: HoleData) -> void:
	_hole_label.text = "HOLE %d  ·  %s" % [hole.hole_number, hole.hole_name.to_upper()]
	_par_label.text = "PAR %d" % hole.par
	_wind_arrow.set_wind(hole.wind_direction, hole.wind_yards_per_100)
	_wind_label.text = "%s  ·  %.0f yd drift" % [
		hole.wind_description(), hole.wind_yards_per_100] if hole.has_wind() else "Calm"
	_result_panel.hide()


## The ground the ball is sitting on, and what it will do to the next stroke.
func set_lie(surface: SurfaceType) -> void:
	_lie_label.text = "LIE  %s" % surface.display_name.to_upper()
	_lie_summary.text = surface.summary
	# Trouble is coloured so it is obvious without reading a word of it.
	_lie_label.add_theme_color_override("font_color",
		Color(1.0, 0.72, 0.45) if surface.modifies_play() else Color(0.94, 0.98, 0.88))


## The read on the green. Hidden everywhere else, because a slope readout on a
## tee shot is one more thing to learn to ignore.
func set_slope(fall: Vector2, note: String) -> void:
	var on_green := fall.length() > 0.02
	_slope_row.visible = on_green
	if not on_green:
		return
	# Reused from the wind, which is the same problem: a direction and a
	# strength, drawn small enough to sit in a corner.
	_slope_arrow.set_wind(fall.normalized(), fall.length() * 12.0)
	_slope_label.text = note


func set_strokes(strokes: int) -> void:
	_strokes_label.text = "STROKES %d" % strokes


## Just the number. The caption beside it never changes, so it is set in the
## scene and left alone -- the distance is the one figure on screen worth reading
## at a glance, and it cannot be that if it is buried in a sentence.
func set_distance(yards: float) -> void:
	_distance_label.text = str(roundi(yards))


func set_power(power_pct: float) -> void:
	_power_meter.set_power(power_pct)


## The meter does two jobs, so it says which one it is doing. A player who has
## to remember what stage the bar is in is a player who mistimes it.
func set_swing(phase: int, power: float, marker: float, band: float) -> void:
	_power_meter.set_swing(phase, power, marker, band)
	match phase:
		AimController.Phase.POWER:
			_power_title.text = "SWING POWER  ·  RELEASE TO SET"
			_power_title.add_theme_color_override("font_color",
				Color(0.949, 0.961, 0.925, 0.55))
		AimController.Phase.TIMING:
			# "Click" is wrong on a phone, and the prompt is the only instruction
			# a player gets at the one moment the shot can still be ruined.
			_power_title.text = "TIMING  ·  %s AT THE LEFT EDGE" % (
				"TAP SWING" if _touch_ui else "CLICK")
			_power_title.add_theme_color_override("font_color", Palette.GOOD)
		_:
			_power_title.text = "SWING POWER"
			_power_title.add_theme_color_override("font_color",
				Color(0.949, 0.961, 0.925, 0.45))


## How high the shot flies, next to how hard it is hit. Only shown once there is
## something to report, so it does not sit at zero the whole time you are not
## swinging.
func set_apex(yards: float, blocked: bool) -> void:
	if yards < 0.5:
		_apex_label.text = ""
		return
	_apex_label.text = "%d yd high  ·  into the branches" % roundi(yards) \
		if blocked else "%d yd high" % roundi(yards)
	_apex_label.add_theme_color_override("font_color",
		Color(0.878, 0.416, 0.329) if blocked else Color(0.949, 0.961, 0.925, 0.5))


## Only shown when the staged club can actually work the ball, which is one
## club in the game. Everything else leaves the row out entirely rather than
## greying three buttons out at you every single stroke.
## The on-screen swing control appears only where there is no button to hold.
func set_touch_ui(on: bool) -> void:
	_touch_ui = on
	_swing_button.visible = on
	# The keyboard-and-mouse crib sheet is wrong on a phone and just clutter.
	_help_label.visible = not on


func set_shape(available: bool, shape: int, degrees: float) -> void:
	_shape_row.visible = available
	if not available:
		return
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(i - 1 == shape)
	_shape_buttons[0].text = "Draw %d°" % roundi(degrees)
	_shape_buttons[2].text = "Fade %d°" % roundi(degrees)


func set_hand(hand: Array, selected: int, playable: Array,
		combining: Array = []) -> void:
	_hand_view.set_hand(hand, selected, playable, combining)


func set_piles(draw_count: int, discard_count: int) -> void:
	_draw_label.text = "BAG  %d" % draw_count
	_discard_label.text = "PLAYED  %d" % discard_count


func set_focus(focus: int, focus_max: int) -> void:
	_focus_label.text = "FOCUS  %d / %d" % [focus, focus_max]


## Stack the prep line and the combination line above the swing meter.
##
## Both are anchored to the bottom of the screen, so an offset is measured from
## there: position.y is parent_height + offset_top, which rearranges to the line
## below. Done every time they are shown because the meter grows a row of shape
## buttons on a club that can be worked.
func _place_above_the_meter() -> void:
	var parent := _prep_label.get_parent() as Control
	if parent == null or _power_panel == null:
		return
	const LINE := 26.0
	const GAP := 10.0
	var prep_top := _power_panel.position.y - GAP - LINE - parent.size.y
	_prep_label.offset_top = prep_top
	_prep_label.offset_bottom = prep_top + LINE
	_combo_label.offset_left = _prep_label.offset_left
	_combo_label.offset_right = _prep_label.offset_right
	_combo_label.offset_top = prep_top - LINE
	_combo_label.offset_bottom = prep_top


func _make_combo_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Typo.SEMIBOLD)
	label.add_theme_font_size_override("font_size", Typo.SMALL)
	label.add_theme_color_override("font_color", Palette.GOLD)
	# Both lines are drawn straight onto the course, which is bright green in the
	# middle of a fairway and near black under a tree. An outline is what makes
	# them legible on either.
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.05, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.hide()
	_prep_label.get_parent().add_child(label)
	# Same anchoring as the prep line; _place_above_the_meter does the rest.
	label.anchor_left = _prep_label.anchor_left
	label.anchor_right = _prep_label.anchor_right
	label.anchor_top = _prep_label.anchor_top
	label.anchor_bottom = _prep_label.anchor_bottom
	label.grow_horizontal = _prep_label.grow_horizontal
	return label


## What the tutorial is saying, or "" to take the panel away.
##
## Persistent on purpose, unlike set_status, which fades after two and a half
## seconds. A status message is commentary on something that already happened; a
## lesson is an instruction that has to stay put until it is followed.
func set_lesson(text: String) -> void:
	if _lesson_panel == null:
		_build_lesson_panel()
	var wanted := text.strip_edges() != ""
	_lesson_label.text = text
	if wanted == _lesson_panel.visible:
		return
	_lesson_panel.visible = wanted
	# Faded in rather than snapped, so a new line reads as a new line.
	if wanted:
		_lesson_panel.modulate.a = 0.0
		create_tween().tween_property(_lesson_panel, "modulate:a", 1.0, 0.35)


func _build_lesson_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.06, 0.93)
	style.border_color = Color(Palette.GOLD, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 15.0
	style.content_margin_bottom = 15.0

	_lesson_panel = PanelContainer.new()
	_lesson_panel.add_theme_stylebox_override("panel", style)
	_lesson_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lesson_panel.hide()
	add_child(_lesson_panel)

	_lesson_label = Label.new()
	_lesson_label.add_theme_font_override("font", Typo.REGULAR)
	_lesson_label.add_theme_font_size_override("font_size", Typo.STAT)
	_lesson_label.add_theme_color_override("font_color", Palette.INK)
	_lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lesson_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lesson_label.custom_minimum_size = Vector2(660.0, 0.0)
	_lesson_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lesson_panel.add_child(_lesson_label)

	# Below the status line rather than above it. At 92 the panel ran straight
	# through StatusLabel, which sits at 116 -- so "Draw played." printed across
	# the sentence telling you to play Draw. Under it there is nothing until the
	# swing meter, which lives near the bottom of the screen.
	_lesson_panel.anchor_left = 0.5
	_lesson_panel.anchor_right = 0.5
	_lesson_panel.anchor_top = 0.0
	_lesson_panel.anchor_bottom = 0.0
	_lesson_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lesson_panel.grow_vertical = Control.GROW_DIRECTION_END
	_lesson_panel.offset_top = 162.0


## Techniques attached to the next stroke, and any combination they are setting
## off between them.
##
## The combination line is the whole point of the conditional cards. Without it
## they worked and nobody could tell: the prep line named the cards, the numbers
## moved a little, and the game never said a combination had happened. It is
## drawn in gold, on its own line, because it is a thing you made happen rather
## than a thing you are carrying.
func set_modifiers(names: Array, combinations: PackedStringArray = PackedStringArray()) -> void:
	if names.is_empty() and combinations.is_empty():
		_prep_label.hide()
		_combo_label.hide()
		return

	if _prep_label.get_theme_constant("outline_size") < 4:
		_prep_label.add_theme_color_override("font_outline_color",
			Color(0.05, 0.08, 0.05, 0.9))
		_prep_label.add_theme_constant_override("outline_size", 5)
	_place_above_the_meter()
	_prep_label.visible = not names.is_empty()
	if not names.is_empty():
		_prep_label.text = "SHOT PREP:  " + "  +  ".join(names).to_upper()

	_combo_label.visible = not combinations.is_empty()
	if not combinations.is_empty():
		# Names, so they read as things that happened rather than as arithmetic.
		_combo_label.text = "COMBINING:  " + "   ·   ".join(combinations).to_upper()


## Equipment carried into this hole, so a relic that fires on the third stroke
## is something you can see rather than something you have to remember.
func set_relics(relics: Array) -> void:
	for child in _relic_row.get_children():
		child.queue_free()
	for relic in relics:
		# A pill rather than bare text, tinted by the relic's own colour, so a row
		# of equipment reads as a row of objects instead of a run-on word.
		var style := StyleBoxFlat.new()
		style.bg_color = Color(relic.colour, 0.22)
		style.border_color = Color(relic.colour, 0.55)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 7.0
		style.content_margin_right = 7.0
		style.content_margin_top = 3.0
		style.content_margin_bottom = 3.0

		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", style)
		pill.tooltip_text = "%s\n%s" % [relic.display_name, relic.effect_text()]
		pill.mouse_filter = Control.MOUSE_FILTER_STOP

		var chip := Label.new()
		chip.text = relic.short_label
		chip.add_theme_font_override("font", Typo.SEMIBOLD)
		chip.add_theme_font_size_override("font_size", Typo.SMALL)
		chip.add_theme_color_override("font_color", relic.colour)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

		pill.add_child(chip)
		_relic_row.add_child(pill)


## The special rules a hole plays under, named up front. A boss that quietly
## changed the game underneath you would just feel broken.
func set_rules(rule_set: CourseRuleSet) -> void:
	if rule_set == null:
		_rules_panel.hide()
		return
	_rules_panel.show()
	_rules_title.text = rule_set.display_name.to_upper()
	_rules_body.text = rule_set.rules_text()
	_rules_title.add_theme_color_override("font_color", rule_set.colour)


func set_status(text: String) -> void:
	_status_label.text = text
	_status_label.modulate.a = 1.0
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(2.6)
	_status_tween.tween_property(_status_label, "modulate:a", 0.0, 0.8)


func show_result(strokes: int, par: int, holed: bool = true) -> void:
	_result_title.text = HoleView.score_name(strokes, par).to_upper() if holed else "PICKED UP"
	_result_detail.text = ("Holed out in %d.  Par %d." if holed
		else "Took the maximum %d.  Par %d.") % [strokes, par]
	_result_panel.show()
	_restart_button.grab_focus()

	# Scale from the centre, so the panel lands rather than blinks into place.
	_result_panel.pivot_offset = _result_panel.size * 0.5
	_result_panel.scale = Vector2(0.86, 0.86)
	_result_panel.modulate.a = 0.0
	var pop := create_tween().set_parallel(true)
	var land := pop.tween_property(_result_panel, "scale", Vector2.ONE, 0.28)
	land.set_trans(Tween.TRANS_BACK)
	land.set_ease(Tween.EASE_OUT)
	pop.tween_property(_result_panel, "modulate:a", 1.0, 0.18)
