## Draw pile, hand, discard pile and exhaust pile.
##
## Deliberately a plain RefCounted with no scene dependencies: the deck survives
## between holes, and the hole scene only ever reads it. The run layer owns it.
class_name Deck
extends RefCounted

signal changed()

## The player's whole collection for the run, in no particular order.
var cards: Array[CardData] = []

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []

## Copies of one card you may hold at once. You need a putter about once a hole,
## so without a cap a retained hand silently fills with spares you will never
## play, and the hand stops being a decision.
##
## Clubs are capped harder than techniques, because you play exactly one club a
## stroke: a second copy of one is not a worse option, it is no option at all.
## Two techniques is different -- focus buys two a stroke, and stacking a pair
## of Draws to bend it twice as far is a real thing to want.
##
## This mattered little at a hand of five and matters a lot now equipment can
## deal you six: "hold one more club" turning into "hold one more putter" makes
## the relic worse than not owning it.
const MAX_CLUB_COPIES_IN_HAND := 1
const MAX_COPIES_IN_HAND := 2

var _rng := RandomNumberGenerator.new()


func _init(starting_cards: Array[CardData] = []) -> void:
	_rng.randomize()
	cards = starting_cards.duplicate()


## Deal from a known shuffle instead of a random one.
##
## For harnesses only. `run_sim` is the instrument the whole project's balance is
## measured with, and it was not reproducible: the deck randomized itself on
## construction, so two runs of identical code came back -7.5 and -7.1 with
## fifteen balls out of bounds and then six. Every before-and-after comparison
## made with it was really two samples from the same distribution, and small
## differences read as changes that had not happened.
##
## The game itself must keep randomizing -- a real run that dealt the same hands
## every time would be no run at all -- so this is opt-in rather than the default.
func shuffle_from(seed_value: int) -> void:
	_rng.seed = seed_value


# --- Collection (persists across holes) -----------------------------------

func add_card(card: CardData) -> void:
	cards.append(card)
	changed.emit()


func remove_card(card: CardData) -> void:
	cards.erase(card)
	changed.emit()


func total_cards() -> int:
	return cards.size()


## Anything in the bag that can actually be putted with.
##
## A putt is a stroke played along the ground, so this asks the club rather than
## matching on a name: a future putter under any other id still counts, and a
## wedge never does however short you try to swing it.
func putters() -> int:
	var found := 0
	for card in cards:
		if card != null and card.club != null and card.club.is_ground_shot:
			found += 1
	return found


## True if losing this card would leave you with no way to putt at all.
##
## Worth guarding because the putter is a starter card: shops and prizes both
## draw from the common and uncommon pools, so nothing in the game can ever give
## you another one. Losing the last was not bad luck, it was unrecoverable, and
## a run could be effectively over four holes before it ended.
func is_last_putter(card: CardData) -> bool:
	if card == null or card.club == null or not card.club.is_ground_shot:
		return false
	return putters() <= 1


# --- Per-hole state -------------------------------------------------------

## Gather everything back up and shuffle. Call at the start of a hole.
func reset_for_hole() -> void:
	draw_pile = cards.duplicate()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	shuffle_draw_pile()
	changed.emit()


func shuffle_draw_pile() -> void:
	# Fisher-Yates against our own RNG so runs stay reproducible if we ever seed.
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


## Top both hands back up, from the one bag.
##
## A club is mandatory and a technique is optional -- you play exactly one club
## every stroke and you need never play a technique at all -- and dealing them
## from a single shared hand meant the mandatory one sometimes did not turn up.
## "No legal move" is not difficulty, it is a dead end, and the game had grown
## four separate mechanisms to paper over it: a per-hand cap on club copies, a
## guarantee on your last putter, a shop rescue for it, and a routine in HoleView
## that reached into this pile mid-hole and swapped a card behind the player's
## back. Two hands and the problem is gone rather than hidden.
##
## Still one deck and one draw pile. What changed is only that a club you have
## not drawn can no longer be crowded out by a technique you have.
func deal_up_to(clubs: int, extras: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	drawn.append_array(_draw_kind(true, clubs - clubs_in_hand()))
	drawn.append_array(_draw_kind(false, extras - extras_in_hand()))
	if not drawn.is_empty():
		changed.emit()
	return drawn


func clubs_in_hand() -> int:
	return _held(true)


func extras_in_hand() -> int:
	return _held(false)


func _held(shots: bool) -> int:
	var count := 0
	for card in hand:
		if card != null and card.is_shot() == shots:
			count += 1
	return count


func _draw_kind(shots: bool, count: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	for _i in maxi(count, 0):
		var card := _take_one(shots)
		if card == null:
			break
		hand.append(card)
		drawn.append(card)
	return drawn


## The topmost card of this kind, lifted out of the pile where it lies.
##
## Deliberately not pop-and-put-back. The old draw took from the top and pushed
## anything it could not use to the bottom, which is fine when every card is a
## candidate -- but filling a four club hand that way would shove every technique
## in the pile underneath them, and the extras hand would starve by the second
## hole. Taking the card out from where it sits leaves the rest of the order
## exactly as it was.
func _take_one(shots: bool) -> CardData:
	# Twice: once through the pile as it stands, and once more after taking the
	# discard back, for the hole where every wedge you own is already played.
	for pass_number in 2:
		for i in range(draw_pile.size() - 1, -1, -1):
			var card: CardData = draw_pile[i]
			if card == null or card.is_shot() != shots:
				continue
			if copies_in_hand(card.id) >= _copy_limit(card):
				continue
			draw_pile.remove_at(i)
			return card
		if pass_number == 0:
			recycle_discard_into_draw()
	return null


func copies_in_hand(id: StringName) -> int:
	var count := 0
	for card in hand:
		if card.id == id:
			count += 1
	return count


## How many of this card the hand will hold at once.
##
## Clubs stay capped at one copy even now they have a hand of their own: you play
## exactly one club a stroke, so a second putter is not a worse option, it is a
## quarter of your club hand spent on no option at all.
func _copy_limit(card: CardData) -> int:
	return MAX_CLUB_COPIES_IN_HAND if card.is_shot() else MAX_COPIES_IN_HAND




func recycle_discard_into_draw() -> void:
	if discard_pile.is_empty():
		return
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	shuffle_draw_pile()


## Move a card out of the hand and onto the discard pile. Returns the card, or
## null if the index was not valid.
func play_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var card: CardData = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)
	changed.emit()
	return card


func discard_hand() -> void:
	if hand.is_empty():
		return
	discard_pile.append_array(hand)
	hand.clear()
	changed.emit()


func exhaust_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var card: CardData = hand[index]
	hand.remove_at(index)
	exhaust_pile.append(card)
	changed.emit()
	return card


## Take a specific card out of the draw pile and into the hand, discarding a card
## you are holding to make room. Used to guarantee a tee shot.
func swap_from_draw_pile(hand_index: int, draw_index: int) -> bool:
	if hand_index < 0 or hand_index >= hand.size():
		return false
	if draw_index < 0 or draw_index >= draw_pile.size():
		return false
	var incoming: CardData = draw_pile[draw_index]
	draw_pile.remove_at(draw_index)
	discard_pile.append(hand[hand_index])
	hand[hand_index] = incoming
	changed.emit()
	return true


func has_playable_shot(focus: int) -> bool:
	for card in hand:
		if card.is_shot() and card.effective_cost() <= focus:
			return true
	return false
