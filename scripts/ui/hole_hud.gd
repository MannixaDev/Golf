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
@onready var _shape_row: HBoxContainer = %ShapeRow
@onready var _shape_buttons: Array[Button] = [%DrawButton, %StraightButton,
	%FadeButton]
@onready var _power_title: Label = %PowerTitle
@onready var _prep_label: Label = %PrepLabel
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


func _ready() -> void:
	_result_panel.hide()
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	_hand_view.card_clicked.connect(func(slot: int) -> void: card_clicked.emit(slot))
	# Buttons rather than a keypress: this game is played with a mouse, and a
	# shape you have to know a key for is a shape nobody uses.
	for i in _shape_buttons.size():
		var shape := i - 1
		_shape_buttons[i].pressed.connect(func() -> void: shape_chosen.emit(shape))


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
			_power_title.text = "TIMING  ·  CLICK AT THE LEFT EDGE"
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
func set_shape(available: bool, shape: int, degrees: float) -> void:
	_shape_row.visible = available
	if not available:
		return
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(i - 1 == shape)
	_shape_buttons[0].text = "Draw %d°" % roundi(degrees)
	_shape_buttons[2].text = "Fade %d°" % roundi(degrees)


func set_hand(hand: Array, selected: int, playable: Array) -> void:
	_hand_view.set_hand(hand, selected, playable)


func set_piles(draw_count: int, discard_count: int) -> void:
	_draw_label.text = "BAG  %d" % draw_count
	_discard_label.text = "PLAYED  %d" % discard_count


func set_focus(focus: int, focus_max: int) -> void:
	_focus_label.text = "FOCUS  %d / %d" % [focus, focus_max]


## Techniques attached to the next stroke.
func set_modifiers(names: Array) -> void:
	if names.is_empty():
		_prep_label.text = ""
		_prep_label.hide()
	else:
		_prep_label.text = "SHOT PREP:  " + "  +  ".join(names).to_upper()
		_prep_label.show()


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
