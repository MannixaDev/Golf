# Fairway Fiends

A roguelike deckbuilding golf game where the golf course is the enemy.

Built with **Godot 4.7.2**.

## Current state: Milestone 8 — Polish

All eight milestones are in. The course is mown in stripes, bunkers have a lip,
ponds ripple, the ball throws up turf and sand and water where it lands, the
camera takes a knock off the tee, the route draws itself in, and the whole thing
now makes a noise.

Still no binary assets: every shape is drawn and every sound is synthesised at
startup, so the repository remains text only.

## Play it

<https://mannixa.itch.io/fairwayfiends> — plays in the browser, no download.

## Running it

Open `project.godot` in Godot and press **F5**, or:

```bash
godot --path .
```

## Controls

| Input | Action |
| --- | --- |
| Click a stop | Travel there (on the route) |
| Click a card / 1–5 | Choose a shot |
| Mouse | Aim |
| Left mouse / Space | Hold to swing, release to strike |
| Left / Right (or A / D) | Fine aim adjustment |
| Right mouse / Esc | Put the card back |
| Enter | Continue, once a hole is finished |

Pick a card first — nothing aims until you do. Pressing locks your aim line, then
the power meter ping-pongs 0 → 100 → 0. Release to hit at whatever it reads. More
power means more distance *and* more dispersion.

## Architecture

```
Main  (run layer: owns Deck, RunMap and RunState; swaps screens)
 |
 +-- MapScreen ------ MapView            --node_chosen-->  Main
 +-- HoleScreen ----- HoleView + HoleHUD --finished----->  Main
 +-- NoticeScreen -------------------------continued---->  Main

inside a hole:
AimController --shot_requested--> HoleView --launch--> Ball
                                     |
                                     | signals (hand, piles, lie, strokes, ...)
                                     v
                                  HoleHUD --> HandView --> CardView
```

Screens never talk to each other. Each is handed what it needs, does its job and
reports back with one signal, so `Main` is the only thing that knows the shape of
a run. `HoleView` is the only script that knows about both rules and presentation;
`HoleHUD` never reads game state, it only reacts to signals.

### Key pieces

| File | Responsibility |
| --- | --- |
| `scripts/main.gd` | The run layer: deck, route, card, screen swapping |
| `scripts/run/run_state.gd` | The card, the cut, the purse and the equipment |
| `scripts/run/reward_table.gd` | What a hole pays and what it offers afterwards |
| `scripts/run/relic_spec.gd` | Resource: one piece of equipment |
| `scripts/run/relic_effect.gd` | Base class: `modify_profile()` and `try_rescue_ball()` |
| `scripts/run/relic_context.gd` | What equipment may know when deciding to fire |
| `scripts/ui/card_picker_screen.gd` | One screen for every choose-a-card moment |
| `scripts/ui/shop_screen.gd` | The pro shop |
| `scripts/rules/course_rule.gd` | Base class: what a special rule may do |
| `scripts/rules/course_rule_set.gd` | Resource: a named set of rules, plus hole overrides |
| `scripts/rules/effects/` | The three rule behaviours |
| `scripts/events/event_spec.gd` | Resource: one event and its choices |
| `scripts/events/event_outcome.gd` | Resource: what taking a choice does |
| `scripts/audio/sound_bank.gd` | Synthesises every sound effect as PCM |
| `scripts/audio/sfx.gd` | Static sound service (see below) |
| `scripts/golf/shot_effects.gd` | Impact specks, splashes and the holed-out burst |
| `scripts/map/map_node_spec.gd` | Resource: one kind of stop, and where it may appear |
| `scripts/map/map_generator.gd` | Builds the branching route |
| `scripts/map/run_map.gd` | The route, and where the player stands on it |
| `scripts/map/map_view.gd` | Draws the route from node specs. No art |
| `scripts/golf/hole_generator.gd` | Builds a playable hole from a seed and a tier |
| `scripts/golf/hole_data.gd` | Resource: a hole's par, geometry, hazards, wind |
| `scripts/golf/surface_type.gd` | Resource: one kind of ground and all its numbers |
| `scripts/golf/hazard_region.gd` | Resource: a shape plus the surface filling it |
| `scripts/golf/surface_sampler.gd` | Lets the ball ask about ground it cannot name |
| `scripts/golf/club_spec.gd` | Resource: one club's distance and control |
| `scripts/cards/card_data.gd` | Resource: one card |
| `scripts/cards/deck_list.gd` | Resource: a deck as a list of card ids |
| `scripts/cards/deck.gd` | Draw pile, hand, discard, exhaust. No scene deps |
| `scripts/cards/card_effect.gd` | Base class: `modify_profile()` and `on_play()` |
| `scripts/cards/effect_context.gd` | What an instant effect may read and request |
| `scripts/golf/shot_profile.gd` | The card→simulation seam (see below) |
| `scripts/golf/shot_resolver.gd` | Pure function: profile + aim + power → `ShotResult` |
| `scripts/golf/ball.gd` | Two-phase shot execution (flight, then roll) |
| `scripts/golf/hole_view.gd` | Hand, stroke rules, penalties, holing out |
| `scripts/ui/hole_hud.gd` | All screen-space UI for a hole |
| `scripts/ui/hand_view.gd` | Lays the hand out; owns `CardView`s |

### How a shot works

1. You select a card. `ShotProfile.from_card()` combines the card's club with the
   card's own modifiers, then the techniques you played, then your lie.
2. `AimController` emits `shot_requested(direction, power)`.
3. `ShotResolver.resolve()` applies dispersion, distance variance, shape and wind
   to the profile, producing a `ShotResult` with **carry**, **roll** and a
   direction.
4. `Ball` executes it in two phases:
   - **Flight** — to the landing point, bending sideways for shape and weather,
     with a purely visual height arc. Does not interact with the ground.
   - **Roll** — decelerates from the landing point, sampling ground friction as
     it goes.

`ShotProfile` is the important seam. The resolver never sees a card, a club or a
bunker — only a profile. Technique cards, lies and (later) relics all work by
mutating that profile before resolution, so none of them needs a special case in
the golf code.

### How effects work

A `CardEffect` has two hooks and may use either or both:

| Hook | When | Used by |
| --- | --- | --- |
| `modify_profile()` | held, then folded into the next stroke | Draw, Fade, Punch, Full Send, Bawl Grabbur |
| `on_play()` | the instant the card is played | Mulligan, Foot Wedge |

Instant effects never touch the scene. They read an `EffectContext` and write
their intent back into it (`move_ball_to`, `stroke_delta`, or `reject()`);
`HoleView` is the only thing that actually moves the ball or edits the score.

The payoff is the ratio: **twelve cards, three effect scripts.** One
`ProfileTweakEffect` covers Draw, Fade, Punch, Full Send *and* Bawl Grabbur, so
a new technique is a .tres file and nothing else.

### Worked shots are not drawn for you

Draw and Fade originally bent the ball *and* previewed the bend, which made them
identical to simply aiming off -- a card that did nothing a mouse could not.

They now halve dispersion and conceal the curve: a much straighter shot in
exchange for judging the shape yourself. The bend is a consistent tenth of the
shot's carry, so it is learnable rather than random, and the card says so. The
narrowed cone still shows the accuracy you bought. `ShotProfile.conceal_shape`
reverts it if that trade turns out to be no fun.

Wind stays visible, because that is the course's doing and is already announced
in the HUD. Your own manufactured shape is yours to read.

### Sound, without any sound files

The project ships no binary assets, so rather than skip audio the twelve effects
are **synthesised as PCM at startup**: a strike is a low sine under a very short
noise transient, a splash is filtered noise over a falling pitch, a holed putt is
three knocks against the cup and then a chime. It costs a few milliseconds once.

Which sound a club makes is derived from the club's own numbers rather than its
name, so a new club needs no new case:

| Club | Sound |
| --- | --- |
| carry >= 200 yd | `drive` |
| ground shot | `putt` |
| carry <= 100 yd | `chip` |
| everything else | `iron` |

`Sfx` is a **static service rather than an autoload**, and that is deliberate: an
autoload is not visible to scripts launched with `--script`, which is how every
harness in `tools/` runs. Making it one caused `HoleView` to fail to compile the
moment it asked for a sound. As a static class it behaves identically in the
game, the editor and a headless suite, and no-ops where there is nothing to hear.

`audio_check.gd` measures peak and RMS of every effect, because generated audio
fails silently in the most literal sense — a bad envelope produces a stream that
loads, plays, and cannot be heard.

### How special rules work

The brief is explicit that a boss should not simply be a hole with more sand in
it, so a `CourseRule` is a behaviour hook rather than another hazard knob:

| Hook | When |
| --- | --- |
| `on_hole_start()` | once, as the hole begins |
| `before_stroke()` | the weather turns, the groundskeeper moves things |
| `modify_profile()` | last word on the stroke, after card, equipment and lie |

A `CourseRuleSet` also gets to reshape the hole *before* it is generated —
forcing a par, a length, a tighter fairway, extra greenside trouble. The
Impossible Par 3 is 145 yards with **nine hazards ringing its green** against an
ordinary closer's four; it is a hole built differently, not a rule bolted on.

Three behaviours cover seven rule sets. Elite holes draw from the light ones,
the closing hole only ever draws its own. Rules are seeded from the hole, so a
boss reads the same way every time you look at it.

**Rules announce themselves.** They are named on screen before the first stroke,
and a distraction is rolled in `before_stroke()` so the aiming cone already shows
the damage. A boss that quietly changed the game underneath you would just feel
broken.

### How events work

An `EventSpec` is a short scene with two or three `EventOutcome`s, each a bundle
of consequences — winnings, strokes on your card, a card added or removed, a card
upgraded, a piece of equipment. Writing a new one is prose and numbers, never a
script. Options you cannot afford are not offered, and a run will not repeat an
event until the pool is exhausted.

### How equipment works

Equipment uses the same shape as card effects: parameterised sub-resources
authored as .tres. A `RelicEffect` has two hooks:

| Hook | When |
| --- | --- |
| `modify_profile()` | folded into a stroke, after the card, techniques and lie |
| `try_rescue_ball()` | when a ball would be lost, to cancel the penalty |

The ratio again: **six pieces of equipment, two effect scripts.** One
`ConditionalProfileRelic` covers the glove that helps every third swing, the
rangefinder that helps every swing, the caddie who only speaks up from a bad lie
and the handicap that only helps once you are behind — the condition is a field.

**Equipment is applied before the lie, on purpose.** A sand wedge and an angry
caddie both work by *resisting* the ground, which only means anything while the
ground has yet to be applied. `ShotProfile.lie_resistance` eases each of the
lie's multipliers back toward neutral rather than adding a second code path.

### How upgrading works

An upgrade is just more effects. `CardData.upgrade_effects` holds a
`ProfileTweakEffect` that is folded in once `upgraded` is true, so there is no
parallel set of upgraded statistics to keep in step with the base ones. Nothing
reads `effects` or `cost` directly — `active_effects()` and `effective_cost()`
are the only honest answers once a card can be upgraded.

### How hazards attach

Splitting carry from roll is what makes the hazard layer work. Trouble hooks in
at three separate points:

| Point | What happens |
| --- | --- |
| **Lie** (where the ball rests) | The surface's multipliers fold into the *next* shot's profile |
| **Carry** (the landing point) | Water catches the ball out of the air |
| **Roll** | Friction is sampled every frame, so a ball running into rough pulls up short exactly where the ground changes |

The ball never learns what a bunker is. It holds a `SurfaceSampler` and asks two
questions — "how sticky here?" and "am I lost here?" — which keeps the physics
generic and the hole geometry out of it.

**Every friction value is >= 1, deliberately.** An early version scaled launch
speed by the surface so a putt on a slick green would not overrun; that let a ball
pitching into a bunker launch at five times the needed speed, leave the small sand
circle within a few frames, and coast hundreds of yards down the fairway. Sand
must only ever remove energy.

### Wind

Wind drift scales with carry *and* with `arc_factor`, so loft decides how much the
weather gets to interfere:

| Shot | Carry | Arc | Drift |
| --- | --- | --- | --- |
| Driver | 250 yd | 0.50 | 6.9 yd |
| 9 Iron | 130 yd | 0.95 | 6.8 yd |
| Punched 9 Iron | 110 yd | 0.28 | **1.7 yd** |

That is what turns Punch from a flat trade-off into a situational tool.

### How the route is generated

Several walks are carved from the first tee to the closing hole, each step only
moving to a node that sits close by in the next column. That guarantees the route
is connected and playable, keeps the lines readable, and still produces real
branches and merges. Anything the walks never touched is pruned.

Nodes are **positioned before the routes are carved**, and connections are chosen
by actual vertical distance rather than by slot index. Columns hold different
numbers of nodes, so comparing indices produced long diagonal jumps that read as a
tangle; comparing pixels does not.

Tuned by measurement to about **1.9 live choices per stop** — branching without
becoming a mesh where every route is the same.

### Fairness rules the generator enforces

Two things are checked rather than hoped for:

- **Nothing may sit on the green.** Hazards are pushed outwards rather than
  deleted, so greenside sand still hugs the edge and a pond still guards the
  approach -- they simply stop covering ground you have to putt across. Water on
  the green is not a hard hole, it is a broken one. An irregular pond reports its
  true extent rather than its nominal radius, because the two differ by 22%.
- **Deep rough is sized in fairway widths, not absolute yards.** Sized absolutely,
  a rough patch on a short par 3 came out wider than the hole and swallowed the
  fairway.

`map_check.gd` samples a ring around every generated pin and fails if anything
unputtable is found there.

### How holes are generated

Everything is placed relative to the line of play rather than scattered: the
fairway is a band around a spine from tee to pin, and hazards are positioned by
how far down that spine they sit and how far off it. A generated hole therefore
always has a route, and its trouble is always trouble you could have avoided.

Scale is per hole. Every hole spans the same screen width, so a short par 3 is
drawn zoomed in and a long par 5 zoomed out, with `pixels_per_yard` carrying the
difference. Everything in the generator is authored in yards.

Difficulty scales through **fairway width** more than through hazard count. Sand
beside the line of play barely troubles someone aiming down it, but a tight
fairway turns ordinary dispersion into a rough lie, and a rough lie is shorter and
wilder.

| Tier | Fairway | Length bonus | Wind |
| --- | --- | --- | --- |
| 0 gentle | 21 yd | −15 yd | calm |
| 2 tough | 15 yd | +20 yd | breezy |
| 4 closer | 11 yd | +50 yd | howling |

## The cut

Your score against par carries across the whole run. Go further over than the cut
allows and the run ends. Bogeys are damage, birdies heal, and the closing hole
hits hard because par on it is genuinely difficult.

**The cut is currently +8 and is the first number to tune from real play.** The
robot golfer never comes close to it, but the robot has perfect club selection and
perfect distance judgement, which no human on a ping-pong power meter does.
Tightening it on the robot's evidence would make it punishing for a person.

## Builds

```bash
# Single-file Windows executable -> build/windows/FairwayFiends.exe
godot --headless --path . --export-release "Windows Desktop" build/windows/FairwayFiends.exe

# Web build -> build/web/
godot --headless --path . --export-release "Web" build/web/index.html
```

The Web preset exports with **thread support off**, so the build runs on plain
static hosting with no special headers. See `deploy/` for the server config and
the reasoning. `build/` carries a `.gdignore` so the editor does not re-import
its own output as project content, which otherwise makes each export bloat the
next.

Both presets exclude `tools/*`, so the test harnesses never ship.

## Adding content without touching code

- **A new club**: drop a `ClubSpec` `.tres` into `resources/clubs/`. Picked up
  automatically and sorted by `sort_order`.
- **A new card**: drop a `CardData` `.tres` into `resources/cards/`, then add its
  id to a `DeckList`. Several cards can share one `ClubSpec` and differ only by
  their multipliers.
- **A new technique**: a `CardData` whose `effects` holds one `ProfileTweakEffect`
  sub-resource. No script changes at all.
- **A new hazard type**: drop a `SurfaceType` `.tres` into `resources/surfaces/`.
  Indexed by id, so holes refer to it by name and never by reference.
- **A new kind of stop on the route**: drop a `MapNodeSpec` `.tres` into
  `resources/map_nodes/`. It carries its own colour, shape, spawn weight and
  placement rules, so neither the generator nor the map drawing needs changing.
- **A new piece of equipment**: drop a `RelicSpec` `.tres` into
  `resources/relics/` holding a `ConditionalProfileRelic` sub-resource. Its
  condition, its numbers, its price and its spawn weight are all fields.
- **An upgrade for a card**: fill in `upgrade_effects`, `upgraded_name` and
  `upgrade_note` on the card. No script changes.
- **A new starting deck**: edit `resources/decks/starting_deck.tres`. Just a list
  of card ids, with repeats.

## Dev tools

None of these ship in a build; all are run from the command line.

```bash
# Assert every card effect does what its rules text claims.
godot --headless --path . --script res://tools/effects_test.gd

# Assert routes are connected and generated holes are playable.
godot --headless --path . --script res://tools/map_check.gd

# Play whole runs with the robot golfer over generated holes.
godot --headless --path . --script res://tools/run_sim.gd

# Assert the hand rules: duplicate cap, and a playable tee shot.
godot --headless --path . --script res://tools/hand_check.gd

# Assert equipment fires only on its condition, and the payouts are sane.
godot --headless --path . --script res://tools/relic_check.gd

# Assert special rules change the hole, and events resolve cleanly.
godot --headless --path . --script res://tools/rules_check.gd

# Assert every synthesised sound effect actually contains sound.
godot --headless --path . --script res://tools/audio_check.gd

# Play 40 rounds on the fixed reference hole and print the scores.
godot --headless --path . --script res://tools/smoke_test.gd

# Probe the surface map, the wind model and the real driver landing zone.
godot --headless --path . --script res://tools/hazard_check.gd

# Boot the game, walk the run flow, and save PNGs of each screen.
godot --path . --script res://tools/screenshot.gd

# List every card and how its resource parsed.
godot --headless --path . --script res://tools/card_check.gd
```

`run_sim.gd` is the balance harness for a whole run. It steps the ball by hand
rather than waiting on engine frames, so a few hundred generated holes take
seconds. The robot golfer currently reads:

| Tier | 0 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- | --- |
| Average to par | −0.86 | −0.77 | −0.67 | −0.56 | −0.36 |

The separation came back when the starting bag was trimmed for Milestone 6. It
had been stuffed with support cards so every effect could be seen without a shop;
now there is a shop, the bag is mostly clubs and the holes get to do the talking.

Two caveats on those numbers. The robot has perfect club selection and perfect
distance judgement, so it is a generous read. And it carries **no equipment and
never buys a card**, so this measures the run's opening difficulty only, not what
it feels like once a power curve exists.

`map_check.gd` asserts the structural things: every node reachable from the first
tee, every node leading somewhere, every route exactly as long as the map is wide,
and every generated hole having a tee you can stand on and a cup that is not
underwater.

`hazard_check.gd` simulates 200 tee shots to report where drives actually finish.
Bunker placement on the reference hole was set from that measurement rather than
by eye.

`effects_test.gd` is the one that matters for correctness: it asserts that Draw
bends left and Fade bends right, that techniques stack rather than overwrite, that
Mulligan refuses on the tee, that Foot Wedge refuses from tap-in range, and that
Ball Retriever actually keeps the ball in bounds.

## Hand rules, and why they exist

Both of these came out of a playtest rather than a spec, and both are asserted in
`hand_check.gd` because they are easy to regress:

- **At most two copies of a card in hand.** You need a putter about once a hole,
  so with a retained hand the spares piled up and the hand stopped being a
  decision. Cards passed over go back to the bottom of the pile rather than being
  lost.
- **The tee shot always has something long enough.** If nothing in the opening
  hand reaches 45% of the hole, the longest club in the bag is swapped in and the
  game says so. Standing on a 500 yard tee holding three wedges is not an
  interesting decision, it is a hole lost before you have swung. The threshold is
  deliberately low: on a long par 5 only a driver clears it, but on a par 4 a mid
  iron does, so playing one from the back of the bag is still a disadvantage.

## Card rules as they currently stand

- You hold a hand of **5**, topped back up before every shot.
- Playing a shot card costs a stroke. **Unplayed cards stay in your hand** — one
  stroke consumes exactly one card. It is your bag, and you keep a club until you
  actually use it.
- This started out the other way round, discarding the whole hand each shot. That
  burned five cards a stroke, so a 14-card deck cycled completely every two
  strokes: the draw pile visibly reset over and over and the deck meant nothing.
  `HoleView.discard_hand_each_shot` flips it back if we ever want that pressure
  with a much larger deck.
- **Focus** is 3 per stroke. A shot card costs 1; techniques and utilities cost 1
  or 2. One focus is always reserved for the stroke itself, so you can play at
  most two supporting cards before a swing.
- Support cards **do not cost a stroke** and **replace themselves in hand**, so
  spending focus digs through the bag instead of thinning your options.
- If a hand contains nothing you can legally play from your current lie, the bag
  is re-rummaged. Without that the hole deadlocks: you cannot swing, and the hand
  only refills after a swing.
- `HoleView.can_play()` is the single source of truth for both the greying-out of
  cards and the click handler, so the hand can never show a card as available and
  then refuse it.

## The stops, and what each one does

| Stop | What happens |
| --- | --- |
| Hole | Pays winnings by score, then offers 1 of 3 cards |
| Pro Shop | Three cards and two pieces of equipment at a price, plus paid removal |
| Driving Range | Upgrade one card, free |
| Clubhouse | Remove one card, free |
| Lost and Found | Loose change, and sometimes equipment somebody left behind |
| Halfway House | Take 2 strokes off your card, or groove a club |
| Caddie | Her recommendation: one of two cards, free |
| Event | A short scene with two or three ways out |
| Championship Hole | An ordinary hole plus one twist |
| Signature Hole | The closing hole, under its own rules |

## Known simplifications

- One course of nine columns per run. Multiple courses of rising difficulty,
  and meta-progression between runs, are still to come.
- The cut is +8 and the robot golfer never approaches it. It is the first number
  to tune from real play.
- There is no music, only effects. A synthesised ambient bed would be the next
  audio step.
- Everything is still drawn from primitives. That is a deliberate choice rather
  than a gap, but it does mean the game has a diagram-like look that real
  artwork would change completely.
- Every run uses one course of nine columns. Multiple courses of rising difficulty
  come later.
- Card upgrades are modelled in the data (`upgraded`, `upgraded_name`) but nothing
  can upgrade a card yet — Milestone 6.
- There are no trees or vertical obstacles, so Draw and Fade shape the ball around
  hazards on the ground rather than around anything overhead.
- Wind is constant for a hole. Wind that shifts every stroke is a boss rule.
- Input reads raw keycodes rather than named input actions. A proper InputMap and
  rebinding belongs in the polish milestone.
- The cup is far larger than a real one would be at this scale, because a
  realistic cup would be sub-pixel and unputtable.
