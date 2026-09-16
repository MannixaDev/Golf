## Every bag a run can start from.
##
## Scanned from a folder like the cards, relics and surfaces are, so adding a
## golfer is a .tres and nothing else. The tutorial's bag deliberately lives
## elsewhere: it is six cards chosen to make a lesson deterministic, not a way
## anybody should have to play nine holes.
class_name DeckLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/decks"

static var _bags: Array[DeckList] = []
static var _loaded := false


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true
	for resource in ResourceFolder.load_all(dir_path):
		if resource is DeckList:
			_bags.append(resource)
	# Billing first, then name, so the order on the picker is authored rather
	# than whatever order the filesystem happened to hand back.
	_bags.sort_custom(func(a: DeckList, b: DeckList) -> bool:
		if a.billing != b.billing:
			return a.billing < b.billing
		return a.display_name < b.display_name)


static func all() -> Array[DeckList]:
	ensure_loaded()
	return _bags


## The bag somebody who has not chosen gets. First billing, and the one the rest
## of the game falls back on if a folder scan ever comes back empty in a build.
static func default_bag() -> DeckList:
	ensure_loaded()
	return _bags[0] if not _bags.is_empty() else null


static func by_name(display_name: String) -> DeckList:
	ensure_loaded()
	for bag in _bags:
		if bag.display_name == display_name:
			return bag
	return null


static func clear_cache() -> void:
	_bags.clear()
	_loaded = false
