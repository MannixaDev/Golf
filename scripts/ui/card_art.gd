## The picture on a card: the shot it plays, drawn side on.
##
## Cards were well-set type in a coloured box, which is legible and lifeless.
## The obvious fix is an illustration per card, and the obvious problem with that
## is that it means nineteen drawings nobody has made.
##
## So the picture is derived from the card's own numbers instead. Carry, roll and
## arc are already on every shot profile, and side on they *are* a shape: a
## driver is a long high parabola with a run-out, a putter is a flat line, a
## wedge is a steep lob that stops dead. Every card gets a unique illustration
## for free, it can never disagree with the card's stats, and a new card drawn
## tomorrow arrives with its own.
##
## Techniques show what they change: the plain shot is ghosted behind and the
## modified one drawn over it, so Punch is visibly a flatter arc than the shot it
## replaces rather than a sentence claiming to be.
##
## Drawn as a watermark behind the text rather than in a panel of its own. A card
## this size has no room to give up, and the text fitting was hard-won.
class_name CardArt
extends Control

## Reference maxima, so every card is drawn to the same scale and a driver
## visibly out-flies a wedge instead of both filling their own box.
const REF_TOTAL_YARDS := 300.0
const REF_APEX_YARDS := 34.0
## Share of the card the highest shot in the game climbs.
const APEX_HEIGHT := 0.22
## The club a technique is shown modifying. A mid iron, because the shape of the
## change reads most clearly on something with an ordinary flight.
const REFERENCE_CLUB := &"iron_9"

var card: CardData = null
var tint: Color = Color.WHITE


func setup(new_card: CardData, accent: Color) -> void:
	card = new_card
	tint = accent
	queue_redraw()


func _draw() -> void:
	if card == null or size.x < 4.0 or size.y < 4.0:
		return

	var shot := _profile_for(card)
	if shot == null:
		_draw_emblem()
		return

	# Techniques are shown against the shot they alter.
	if not card.is_shot():
		var plain := _reference()
		if plain != null:
			_draw_flight(plain, Color(tint, 0.08), true)

	_draw_flight(shot, Color(tint, 0.26), false)


## The flight this card produces, or null for a card that does not hit anything.
func _profile_for(source: CardData) -> ShotProfile:
	if source.is_shot() and source.club != null:
		return ShotProfile.from_card(source)
	var modifiers := source.shot_modifiers()
	if modifiers.is_empty():
		return null
	var base := _reference()
	if base == null:
		return null
	base.apply_effects(modifiers)
	return base


func _reference() -> ShotProfile:
	var club := CardLibrary.copy(REFERENCE_CLUB)
	if club == null:
		return null
	return ShotProfile.from_card(club)


## One shot, side on: the carry as a parabola and the run-out along the ground.
func _draw_flight(shot: ShotProfile, colour: Color, ghost: bool) -> void:
	var carry := shot.carry_yards_max
	var roll := carry * shot.roll_ratio
	if shot.is_ground_shot:
		# A putt has no carry at all, so it is all run.
		carry = 0.0
		roll = shot.carry_yards_max

	var total := maxf(carry + roll, 1.0)
	var ground := size.y * 0.90
	var left := size.x * 0.07
	var usable := size.x * 0.86
	# Floored, so a wedge is a small steep arc rather than a dot.
	var span := usable * clampf(total / REF_TOTAL_YARDS, 0.45, 1.0)

	var landing := left + span * (carry / total)
	var stop := left + span
	# Height is compressed hard against distance on purpose. A 9 iron really does
	# fly nearly as high as a driver and less than half as far, so drawn to a
	# true scale on a card this shape every iron came out as a spike. The
	# flattening keeps the *ordering* honest -- a wedge still climbs higher than
	# a stinger -- while letting each one read as a flight.
	var apex := size.y * APEX_HEIGHT * clampf(
		shot.apex_yards() / REF_APEX_YARDS, 0.0, 1.0)

	var width := 1.5 if ghost else 2.5
	if carry > 0.0:
		var path := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			path.append(Vector2(
				lerpf(left, landing, t), ground - apex * sin(PI * t)))
		draw_polyline(path, colour, width, true)

	if roll > 0.5:
		_draw_run(Vector2(landing, ground), Vector2(stop, ground), colour, width)

	# The ground it all happens on, and where the ball ends up.
	draw_line(Vector2(left - 3.0, ground), Vector2(left + usable, ground),
		Color(colour, colour.a * 0.5), 1.0)
	if not ghost:
		draw_circle(Vector2(stop, ground - 2.0), 2.6, Color(colour, colour.a * 1.6))


## Run-out, dashed, so it reads as rolling rather than as more flying.
func _draw_run(from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	var total := from.distance_to(to)
	if total < 0.5:
		return
	var step := (to - from) / total
	var travelled := 0.0
	while travelled < total:
		var finish := minf(travelled + 4.0, total)
		draw_line(from + step * travelled, from + step * finish, colour, width, true)
		travelled = finish + 3.0


## For cards that never touch the ball -- a Mulligan, a Foot Wedge -- there is no
## flight to draw, so they get a flag instead. Still a picture, still no art.
func _draw_emblem() -> void:
	var colour := Color(tint, 0.18)
	var foot := Vector2(size.x * 0.5, size.y * 0.86)
	var top := foot + Vector2(0.0, -size.y * 0.46)
	draw_line(foot, top, colour, 2.5, true)
	draw_colored_polygon(PackedVector2Array([
		top,
		top + Vector2(size.x * 0.24, size.y * 0.07),
		top + Vector2(0.0, size.y * 0.15),
	]), colour)
	draw_circle(foot + Vector2(size.x * 0.16, -3.0), 3.0, colour)
