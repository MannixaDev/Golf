## The front menu: pick a round length, change your settings, or leave.
##
## Round length is the only real choice here, and it is a genuine one -- a nine
## is a short sharp run where a bad hole is a third of your cut, an eighteen is
## long enough that a deck actually becomes something.
class_name TitleScreen
extends Control

signal round_chosen(holes: int)
signal tour_opened()
signal lesson_opened()
signal settings_opened()

@onready var _learn: Button = %LearnButton
@onready var _tour: Button = %TourButton
@onready var _nine: Button = %NineButton
@onready var _eighteen: Button = %EighteenButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _blurb: Label = %Blurb

const BLURB_DEFAULT := "Nine holes, or the full round."
const BLURBS := {
	"learn": "One guided hole. Fifteen minutes, and nothing about the bag will be a surprise.",
	"tour": "Pick your tour. Better fields, tighter cuts, bigger cheques.",
	"nine": "Nine holes. Short and unforgiving — one bad hole is most of your cut.",
	"eighteen": "Front nine, then the back. Long enough to build a bag worth having.",
	"settings": "Sound and screen.",
	"quit": "Put the clubs away.",
}


func _ready() -> void:
	_blurb.text = BLURB_DEFAULT
	_learn.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		lesson_opened.emit())
	_tour.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		tour_opened.emit())
	_nine.pressed.connect(func() -> void: _choose(MapGenerator.HOLES_PER_NINE))
	_eighteen.pressed.connect(func() -> void: _choose(MapGenerator.HOLES_PER_NINE * 2))
	_settings.pressed.connect(func() -> void:
		Sfx.play(&"card", -4.0)
		settings_opened.emit())
	_quit.pressed.connect(func() -> void: get_tree().quit())

	# Hovering explains what you are about to commit to, without a wall of text
	# sitting on screen while you decide.
	_hint(_learn, "learn")
	_hint(_tour, "tour")
	_hint(_nine, "nine")
	_hint(_eighteen, "eighteen")
	_hint(_settings, "settings")
	_hint(_quit, "quit")

	# A first-timer lands on the lesson; everybody else on the round they came
	# for. The menu should not make someone who knows the game click past a
	# tutorial every time they open it.
	if Settings.has_learned():
		_nine.grab_focus()
	else:
		_learn.grab_focus()


func _hint(button: Button, key: String) -> void:
	var text: String = BLURBS.get(key, BLURB_DEFAULT)
	button.mouse_entered.connect(func() -> void:
		Sfx.play(&"select", -16.0, 0.03)
		_blurb.text = text)
	button.focus_entered.connect(func() -> void: _blurb.text = text)
	button.mouse_exited.connect(func() -> void: _blurb.text = BLURB_DEFAULT)


func _choose(holes: int) -> void:
	Sfx.play(&"whoosh", -3.0)
	round_chosen.emit(holes)
