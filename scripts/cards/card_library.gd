## Loads every CardData resource in a folder and indexes it by id.
##
## Dropping a new .tres into res://resources/cards/ makes that card exist. No
## registration step, no code change.
class_name CardLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/cards"

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true

	for res in ResourceFolder.load_all(dir_path):
		if res is CardData:
			var card: CardData = res
			if _by_id.has(card.id):
				push_warning("CardLibrary: duplicate card id '%s'" % card.id)
			_by_id[card.id] = card
		else:
			push_warning("CardLibrary: %s is not a CardData" % res.resource_path)


## The shared template for an id. Never put a template into a deck: use copy().
static func template(id: StringName) -> CardData:
	ensure_loaded()
	if not _by_id.has(id):
		push_error("CardLibrary: unknown card id '%s'" % id)
		return null
	return _by_id[id]


## An independent instance, safe to upgrade without affecting other copies.
static func copy(id: StringName) -> CardData:
	var source := template(id)
	if source == null:
		return null
	# Shallow on purpose: every copy gets its own upgrade state, but they all
	# keep pointing at the same shared ClubSpec.
	return source.duplicate()


static func all_ids() -> Array:
	ensure_loaded()
	return _by_id.keys()
