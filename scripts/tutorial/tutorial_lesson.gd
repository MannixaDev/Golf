## An ordered lesson, as data.
##
## A thin wrapper around an array of steps, so the whole thing is one .tres and
## the wording can be rewritten without touching a line of code -- which matters
## here more than anywhere else in the project, because the wording *is* the
## feature.
class_name TutorialLesson
extends Resource

@export var display_name: String = "Lesson"
@export var steps: Array[TutorialStep] = []


## The steps, minus any that were left empty. An empty panel is worse than no
## panel: it stops the lesson dead waiting for a condition nobody was told about.
func playable_steps() -> Array[TutorialStep]:
	var kept: Array[TutorialStep] = []
	for step in steps:
		if step != null and step.text.strip_edges() != "":
			kept.append(step)
	return kept
