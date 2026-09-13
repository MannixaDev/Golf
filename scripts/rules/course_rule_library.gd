## Loads every CourseRuleSet and picks one appropriate to a hole's difficulty.
class_name CourseRuleLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/rules"

static var _sets: Array[CourseRuleSet] = []
static var _loaded: bool = false


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(dir_path):
		if res is CourseRuleSet:
			_sets.append(res)
		else:
			push_warning("CourseRuleLibrary: %s is not a CourseRuleSet" % res.resource_path)
	_sets.sort_custom(func(a: CourseRuleSet, b: CourseRuleSet) -> bool: return a.id < b.id)


static func all() -> Array[CourseRuleSet]:
	ensure_loaded()
	return _sets


static func by_id(id: StringName) -> CourseRuleSet:
	ensure_loaded()
	for rule_set in _sets:
		if rule_set.id == id:
			return rule_set
	return null


## A rule set suitable for this difficulty, or null for an ordinary hole.
## Deterministic for a given seed, so a hole shows the same rules every time it
## is looked at.
static func pick(difficulty: int, hole_seed: int) -> CourseRuleSet:
	ensure_loaded()
	var pool: Array[CourseRuleSet] = []
	var total := 0.0
	for rule_set in _sets:
		if rule_set.weight <= 0.0 or difficulty < rule_set.min_difficulty:
			continue
		# The closing hole should feel like a closing hole, so it never draws the
		# lighter rules that elites use.
		if difficulty >= 4 and rule_set.min_difficulty < 4:
			continue
		pool.append(rule_set)
		total += rule_set.weight

	if pool.is_empty():
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = hole_seed
	var roll := rng.randf() * total
	for rule_set in pool:
		roll -= rule_set.weight
		if roll <= 0.0:
			return rule_set
	return pool[pool.size() - 1]
