## The tournament you are actually playing in.
##
## The field plays every hole alongside you and the board re-sorts afterwards, so
## a good hole is not a number going down, it is four names going past you. That
## is the difference between a score and a position, and it is why a leaderboard
## does the job the cut could not: the cut was a line at +8 that a bad round
## still cleared, whereas a position moves whether you played well or not.
##
## The field is deterministic in the tournament seed. Play the same seed twice and
## the same man leads after four -- which is the point of giving the rivals a
## fixed skill rather than a die: you can learn that Woodlouse is going to be
## there and plan a round that beats him.
class_name Leaderboard
extends RefCounted

const LIBRARY_PATH := "res://resources/rivals"
## How many of the field turn up to a given tournament. Fewer than the roster, so
## the names change between runs without the good ones ever being missing.
const FIELD_SIZE := 11
## The best players always tee it up. Below this many, the field is drawn at
## random from everyone else.
const ALWAYS_PLAYING := 4

## One line of the board.
class Entry extends RefCounted:
	var name: String = ""
	var short_name: String = ""
	var colour: Color = Color.WHITE
	var flavour: String = ""
	var to_par: int = 0
	var holes: int = 0
	var is_player: bool = false
	## Who this line actually is. Held on the entry rather than in a parallel
	## array beside it: the board is re-sorted every hole, and an index into a
	## list that gets shuffled is a mapping that quietly stops being true. It did
	## exactly that -- every rival was scored with somebody else's form from the
	## second hole onwards, which made the whole field behave like a dice roll
	## however carefully the skills were set.
	var spec: RivalSpec = null
	## Where they stood before this hole, so the board can show the movement.
	var previous_place: int = 0
	var place: int = 0

	func moved() -> int:
		if previous_place <= 0:
			return 0
		return previous_place - place


var entries: Array[Entry] = []
var holes_played: int = 0

var _rivals: Array[RivalSpec] = []
## The tour's handicap on the whole field. Negative means everyone can play.
var _skill_delta: float = 0.0
var _player: Entry = null
var _seed: int = 0

static var _roster: Array[RivalSpec] = []
static var _loaded := false


static func ensure_roster_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(LIBRARY_PATH):
		if res is RivalSpec:
			_roster.append(res)
	# Strongest first, so picking the top few is just taking off the front.
	_roster.sort_custom(func(a: RivalSpec, b: RivalSpec) -> bool:
		return a.skill < b.skill)


static func roster() -> Array[RivalSpec]:
	ensure_roster_loaded()
	return _roster


func _init(tournament_seed: int, skill_delta: float = 0.0,
		player_name: String = "You") -> void:
	ensure_roster_loaded()
	_seed = tournament_seed
	_skill_delta = skill_delta

	var rng := RandomNumberGenerator.new()
	rng.seed = tournament_seed

	# The best few always play. The rest of the field is drawn from everyone
	# else, so no two tournaments have quite the same names in the middle.
	var pool := _roster.duplicate()
	_rivals = []
	for i in mini(ALWAYS_PLAYING, pool.size()):
		_rivals.append(pool.pop_front())
	while _rivals.size() < FIELD_SIZE and not pool.is_empty():
		_rivals.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))

	for rival in _rivals:
		var entry := Entry.new()
		entry.spec = rival
		entry.name = rival.display_name
		entry.short_name = rival.short_name
		entry.colour = rival.colour
		entry.flavour = rival.flavour
		entries.append(entry)

	_player = Entry.new()
	_player.name = player_name
	_player.short_name = player_name.to_upper()
	_player.colour = Palette.GOLD
	_player.is_player = true
	entries.append(_player)
	_sort()


## Play one hole: the player's score goes in, the field plays the same hole, and
## the board re-sorts.
func record_hole(player_to_par: int) -> void:
	for entry in entries:
		# Nobody has moved on the first hole. Everyone starts level and therefore
		# tied for the lead, so carrying that forward showed the whole field
		# tumbling down the board before a ball had been struck.
		entry.previous_place = entry.place if holes_played > 0 else 0

	_player.to_par += player_to_par
	_player.holes += 1

	for entry in entries:
		if entry.spec == null:
			continue
		# Contention is measured before the hole, so a leader tightening up is
		# reacting to leading rather than to having already been caught.
		var pressure := _pressure_on(entry)
		entry.to_par += entry.spec.score_for_hole(
			hash([_seed, holes_played]), pressure, _skill_delta)
		entry.holes += 1

	holes_played += 1
	_sort()


## Move the player up or down the board without a hole being played.
##
## Anything that edits the card after the fact has to come through here, or the
## two numbers the game shows you stop agreeing. Resting at the halfway house
## took strokes off the card and left the board untouched, which meant the stop
## sold as a way back into a run moved you precisely nowhere -- and the cut is
## decided on position.
func adjust_player(to_par_delta: int) -> void:
	if to_par_delta == 0:
		return
	for entry in entries:
		entry.previous_place = entry.place
	_player.to_par += to_par_delta
	_sort()


## How much this player feels the occasion: full for the leader, nothing outside
## the top few.
func _pressure_on(entry: Entry) -> float:
	if holes_played < 2 or entry.place <= 0:
		return 0.0
	return clampf(1.0 - (entry.place - 1) / 3.0, 0.0, 1.0)


## Ties share a place, the way a real board shows them.
func _sort() -> void:
	entries.sort_custom(func(a: Entry, b: Entry) -> bool:
		if a.to_par != b.to_par:
			return a.to_par < b.to_par
		# A tie between you and the field shows you first: it is your board.
		return a.is_player and not b.is_player)

	var place := 0
	var last_score := 0
	for i in entries.size():
		if i == 0 or entries[i].to_par != last_score:
			place = i + 1
			last_score = entries[i].to_par
		entries[i].place = place


func player() -> Entry:
	return _player


func player_place() -> int:
	return _player.place


func field_size() -> int:
	return entries.size()


## True if the player is sharing their position with somebody.
func player_is_tied() -> bool:
	for entry in entries:
		if entry != _player and entry.place == _player.place:
			return true
	return false


## "3rd of 12", or "T3rd of 12" when shared.
func player_position_text() -> String:
	return "%s%s of %d" % [
		"T" if player_is_tied() else "", ordinal(_player.place), entries.size()]


static func ordinal(place: int) -> String:
	if place % 100 >= 11 and place % 100 <= 13:
		return "%dth" % place
	match place % 10:
		1: return "%dst" % place
		2: return "%dnd" % place
		3: return "%drd" % place
	return "%dth" % place


## Score against par as a leaderboard shows it.
static func to_par_text(to_par: int) -> String:
	if to_par == 0:
		return "E"
	return "%+d" % to_par
