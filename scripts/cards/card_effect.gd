## Base class for everything a card can do beyond hitting the ball.
##
## There are two hooks, and a card may use either or both:
##
##   modify_profile()  held until the next stroke, then folded into the shot.
##                     Techniques such as Draw, Fade and Punch live here.
##   on_play()         happens the instant the card is played. Utilities such as
##                     Mulligan and Foot Wedge live here.
##
## Subclasses should stay parameterised rather than specific: one well-exported
## effect class is worth a dozen single-purpose ones, because new cards then cost
## nothing but a .tres file.
class_name CardEffect
extends Resource

## One line of rules text for the card face.
func describe() -> String:
	return ""


## True if this effect should be held until the stroke is played.
func is_shot_modifier() -> bool:
	return false


## Fold this effect into a pending shot. Only called when is_shot_modifier().
func modify_profile(_profile: ShotProfile) -> void:
	pass


## Act on the situation immediately. Call ctx.reject() to refuse the play.
func on_play(_ctx: EffectContext) -> void:
	pass
