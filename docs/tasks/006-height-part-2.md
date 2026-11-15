# 006: Height, part 2: sheer climbs, gap jumps, falling, and the orange area

## Goal

Movement that needs a roll. Models can climb sheer surfaces, jump gaps and drop from
heights, with the rolls resolved in the dice tray in the middle of a move. The
movement indicator shows in orange everything that can only be reached that way.
Falling brings in the injury roll and its results. Infection markers are completed.

Rules reference: `docs/rules/movement.md` (Climb, Jump over a gap, Jump down,
Falling), `docs/rules/terrain.md` (all), `docs/rules/attacks.md` (Injury roll only),
`docs/rules/markers.md`, `docs/rules/rolls.md`.

## Rulings for this brief

These fill gaps in the rules files. Follow them, and restate them in your report so
the project owner can confirm or change them.

1. Injury results are a data table, not code: total 2 to 6 places one blood marker;
   7 to 8 places one blood marker and the model goes Down; 9 or more takes the model
   Out of Action. These bands are provisional.
2. A Down result on a model that is already Down places one extra blood marker
   (two in total for that roll).
3. An Out of Action model is removed from the table and no longer activates, blocks
   or counts as standing. Its record stays in the game state.
4. A model that goes Down during its own activation ends that activation.
5. Jump limit: the gap may be at most half the model's Movement characteristic,
   using the halved characteristic if the model stood up this activation.
6. A drop of 3" or more is shown in orange like a risky roll, because it forces an
   injury roll, even though it cannot fail as such.
7. Orange destinations need a confirmation before the move starts.
8. When the same destination can be reached both safely and with rolls, the safe
   route is always the one offered, even if it is longer. Among routes that need
   rolls, the one with the fewest rolls is offered, then the cheapest.
9. Armour does not exist on models yet, so it is not applied to injury rolls here.
   The pipeline must allow it to be added as an ordinary modifier provider.
10. Bloodbath is out of scope; it comes with attacks.

## Build

**Core: injury rolls and their results**
- Trigger injury rolls through the existing pipeline (kind: injury, two dice kept).
- Outcome table as data (ruling 1), applied by a reaction to the result: place
  markers up to the cap, set Down, or take the model Out of Action.
- Marker spending on an injury roll, before the dice, in the established prompt
  order: the opponent of the injured model may spend its blood and infection markers
  for +1 die each; then the injured model's player may spend its blessing markers
  for -1 die each.
- Out of Action handling throughout: turn order, the first-player count, the reach
  field, the 1" rule and the views.

**Core: infection markers**
- Complete them as in `markers.md`: spent like blood on the same rolls, offered
  together with blood in one prompt with separate counts; +1 at the start of the
  model's activation if it has at least one; capped. The override command can
  already set them.

**Core: risky transitions**

Add to the transition table from brief 004:

| Transition | Cost | Roll |
|---|---|---|
| Sheer climb up or down (wall higher than the open climb height and not a ladder, or tagged sheer) | horizontal distance + wall height | risky success roll at the wall |
| Jump a gap (no floor between two ledges) | horizontal distance; if the far side is higher, the extra height is added to the gap width | risky success roll at the ledge |
| Drop of 3" or more | horizontal distance only | injury roll at +1 die per full 3" |

- **Sheer climb:** the model needs enough movement to clear the whole surface before
  it may attempt it. Success: it arrives directly above (or below) the touch point
  and carries on. Failure: it stays at the foot (or top) where it attempted the
  climb, and its activation ends.
- **Gap jump:** legal only if the effective gap width is within the jump limit
  (ruling 5) and within the movement the model has left. If the far side is lower,
  a successful jump also applies the drop rules for the height difference. Success:
  the model is on the far side and carries on. Failure: it falls into the gap and
  its activation ends.
- **Falling:** the model lands on the first surface beneath the point it fell from,
  at the closest position where it can stop. A fall of 3" or more causes the injury
  roll; less has no effect.
- **Drop:** costs nothing extra. After the injury roll the model carries on if it is
  still standing.
- Wherever a failure or a fall would leave a model in a place where it cannot stop,
  it is moved to the closest position where it can.

**Core: executing a move with rolls in it**
- A move step whose path contains risky transitions is executed in stages. Core
  moves the model to the first roll point, raises the roll (with its marker prompts
  as pending decisions), and on the result either continues along the path to the
  next roll point or stops as the rules say. Movement spent so far stays spent.
- All of this goes through the existing command, pending-decision and event
  machinery. A move with rolls must be undoable step by step and as a whole, and
  must replay identically from the seed and command list.
- `MoveCommand` validation covers such paths fully: every roll point, the "enough
  movement to clear the surface" rule, jump limits, and a stoppable end.

**Core: reach field with rolls**
- The field now answers, for every destination: reachable without any roll,
  reachable only with rolls, or not reachable; and for the second kind, the list of
  rolls on the offered route in order (kind, and for drops the injury dice).
- Route choice follows ruling 8. A simple way: build the safe field first, then a
  second field that may use risky transitions, and use the second only where the
  first has no answer.
- The consistency guarantee extends to these routes: every route the field offers
  is accepted by `MoveCommand.validate`.
- Give the reach field build time for the test table in your report. It runs on a
  worker thread already; keep selection responsive.

**Game**
- **Orange area:** the movement indicator draws destinations that need rolls in
  orange, with the same smooth outline and faint fill as the blue area, on whatever
  surface they are. Blue and orange must be clearly distinguishable where they meet.
- **Path preview for orange destinations:** the path shows a marker at each roll
  point, and the label lists what will be rolled in order, for example
  "Climb 4.0 (risky) - Drop 5.0 (injury +1)", together with the total cost.
- **Confirmation (ruling 7):** clicking an orange destination pins the preview and
  asks for confirmation (a button and Enter; Escape cancels). Blue destinations
  still move on a single click.
- **Playback:** the model climbs straight up or down the wall, jumps in an arc, and
  falls visibly. The dice tray appears at each roll point and the move resumes or
  stops according to the result. Injury results are shown in the tray in words.
- Down models are shown lying down or clearly marked; Out of Action models are
  removed. The HUD shows blood, blessing and infection counts.
- **Test table additions:** a 4" block climbable only as sheer; a 2" wall tagged
  sheer; two platforms 4" high with a 2.5" gap between them; a pair of ledges of
  unequal height with a gap; a 5" high platform to drop from; a gap too wide to jump.

**Tests**
- Injury: each band of the table; Down on Down; Out of Action removal and its effect
  on turn order and the first-player count; the cap on markers; Down during own
  activation ends it.
- Injury spending: blood and infection add dice, blessing removes them, the prompt
  order holds, and markers are removed when spent.
- Infection: grows at activation start only when at least one is present; capped;
  spent together with blood.
- Sheer climb: success continues the move with the height paid; failure stays put
  and ends the activation; not offered without enough movement to clear the wall;
  climbing down works the same way; a wall tagged sheer needs the roll at any height.
- Gap jump: the limit of half the Movement characteristic, halved again after
  standing up; the far side higher adds to the width; the far side lower by 3" or
  more also causes the injury roll; failure falls into the gap, lands on the first
  surface beneath, and ends the activation.
- Falling: under 3" nothing; 3" to 5" at +1; 6" to 8" at +2; landing position moved
  to the closest stoppable place when needed.
- Reach field: a destination reachable both ways is offered by the safe route; the
  top of the 4" block is reachable only with a roll; the far platform is reachable
  by jumping only if the gap is within the limit; the consistency test passes with
  risky routes included.
- Staged execution, undo and replay: a move with a climb and a drop produces the
  expected event sequence; undo in the middle restores the pending roll; the same
  seed and commands give the same result.
- All existing tests still pass.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots with the capture tooling): the top of
  the 4" block is orange and can be climbed with a roll; a failed climb ends the
  activation at the foot of the wall; a model jumps the 2.5" gap; a failed jump
  falls and takes an injury roll; a drop from the 5" platform takes an injury roll
  and the model carries on if it survives standing; a model goes Down and stands up
  at half movement in its next activation; a model is taken Out of Action and
  removed.
- `core/` has no scene-tree access, the only random calls are in the dice service,
  and the roll resolver still names no specific action, marker or terrain rule.

## Out of scope

Charge, retreat, attacks, Bloodbath, armour, morale, game end, line of sight,
difficult and dangerous terrain, real miniature models, map import.
