## Wraps one playable hole: the golf scene plus its HUD, wired together.
##
## This is the wiring that used to live in Main. Pulling it out means the run
## layer only ever deals in "play this hole, tell me the score".
class_name HoleScreen
extends Node2D

signal finished(strokes: int, par: int)

@onready var _hole_view: HoleView = $HoleView
@onready var _hud: HoleHUD = $UI/HoleHUD

var _reported: bool = false
var _carried: Array[RelicSpec] = []


func _ready() -> void:
	_hole_view.hole_started.connect(_hud.set_hole)
	_hole_view.strokes_changed.connect(_hud.set_strokes)
	_hole_view.distance_changed.connect(_hud.set_distance)
	_hole_view.power_changed.connect(_hud.set_power)
	_hole_view.status_message.connect(_hud.set_status)
	_hole_view.hole_completed.connect(_on_hole_completed)
	_hole_view.apex_changed.connect(_hud.set_apex)
	_hole_view.swing_changed.connect(_hud.set_swing)
	_hole_view.slope_changed.connect(_hud.set_slope)
	_hole_view.hand_changed.connect(_hud.set_hand)
	_hole_view.piles_changed.connect(_hud.set_piles)
	_hole_view.focus_changed.connect(_hud.set_focus)
	_hole_view.modifiers_changed.connect(_hud.set_modifiers)
	_hole_view.lie_changed.connect(_hud.set_lie)
	_hole_view.conditions_changed.connect(_hud.set_hole)
	_hole_view.rules_announced.connect(_hud.set_rules)
	_hole_view.shape_changed.connect(_hud.set_shape)

	_hud.restart_pressed.connect(_on_continue)
	_hud.card_clicked.connect(_hole_view.activate_card)
	_hud.shape_chosen.connect(_hole_view.set_shot_shape)
	# Where a finger is the only pointer, the course is for aiming and the swing
	# gets a control of its own.
	var aim: AimController = _hole_view.get_node("AimController")
	_hud.swing_pressed.connect(aim.swing_pressed)
	_hud.swing_released.connect(aim.swing_released)
	_apply_input_mode()


## Checked every frame rather than settled once, because the first finger may
## not land until the player is already stood on a tee -- and a control that
## only appears on the next hole is a hole they could not play.
func _process(_delta: float) -> void:
	_apply_input_mode()


func _apply_input_mode() -> void:
	var touch := Settings.touch_only()
	_hud.set_touch_ui(touch)
	(_hole_view.get_node("AimController") as AimController).set_touch_ui(touch)


## Called by the run layer before this screen enters the tree.
func setup(hole: HoleData, deck: Deck) -> void:
	# HoleView reads `hole` in its own _ready, which has not run yet when the
	# run layer calls this, so assigning directly is safe and keeps the scene
	# usable standalone with its default hole.
	$HoleView.hole = hole
	$HoleView.setup_deck(deck)


## Equipment and the current card, both of which belong to the run rather than
## to this hole.
func setup_run(relics: Array[RelicSpec], score_to_par: int) -> void:
	$HoleView.setup_run(relics, score_to_par)
	_carried = relics


func setup_rules(rules: CourseRuleSet, rule_seed: int) -> void:
	$HoleView.setup_rules(rules, rule_seed)


func begin() -> void:
	_reported = false
	_hud.set_relics(_carried)
	_hole_view.start_hole()


func _on_hole_completed(strokes: int, par: int, holed: bool) -> void:
	_hud.show_result(strokes, par, holed)


func _on_continue() -> void:
	if _reported:
		return
	_reported = true
	finished.emit(_hole_view.strokes, _hole_view.hole.par)


func _unhandled_input(event: InputEvent) -> void:
	# Enter or Space moves on once the hole is done, so the player never has to
	# reach for the mouse to leave a finished hole.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _hole_view._finished:
			_on_continue()
			get_viewport().set_input_as_handled()
