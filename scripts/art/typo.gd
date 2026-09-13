## The type system: four weights and six sizes, and nothing else.
##
## The game used to draw text at eight arbitrary sizes in Godot's built-in
## fallback font. Default-font-at-whatever-size is the single loudest signal that
## something is unfinished, and having no fixed scale meant no two panels agreed
## on what "small" meant.
##
## Controls inside a scene get all of this for free from the project theme; these
## constants exist for the Node2D renderers, which draw text directly and have no
## theme to ask. `Control.get_theme_font()` does not exist on Node2D, which is
## exactly the mistake this class stops the next person making.
class_name Typo
extends RefCounted

## Display numbers only, 20px and up. Below that it goes to mush.
const LIGHT := preload("res://resources/fonts/Lato-Light.ttf")
## Body text, descriptions, flavour.
const REGULAR := preload("res://resources/fonts/Lato-Regular.ttf")
## Labels, buttons, anything that reads as interface rather than as prose.
const SEMIBOLD := preload("res://resources/fonts/Lato-Semibold.ttf")
## Headings, and the one number on screen that matters most.
const BOLD := preload("res://resources/fonts/Lato-Bold.ttf")

## The scale. Steps are wide enough that two adjacent sizes are never mistaken
## for a rendering accident, which is what happens when you use 13 and 14.
const MICRO := 11
const SMALL := 13
const BODY := 15
const STAT := 19
const HEADING := 24
const DISPLAY := 34
