# 008b: Charge corrections and the Down rules

## Goal

Brief 007 built charges on an earlier reading of the rules. The project owner has
since confirmed how charges and Down models work. This brief brings the game in
line, and makes a charge use the same movement machinery as every other move.

Rules reference: "Charge" (including "Details (confirmed)") and "Melee and Retreat"
in `docs/rules/movement.md`; "Down" and "Going Down next to a ledge" in
`docs/rules/markers.md`. Those sections are the source of truth; where
`docs/tasks/007-charge-melee-retreat.md` disagrees, it is out of date.

## Principle: one movement process

Move, Dash, Retreat and Charge must all be the same process with different
settings: the reach field finds routes, the staged move execution carries them out
and makes the rolls. An action only supplies its distance, how enemy 1" zones are
treated, whether routes with rolls are allowed, and its end condition.

Before changing anything, read `core/melee/charge_planner.gd`,
`core/melee/charge_execution.gd` and the move execution from brief 006, and say in
your report where charge currently duplicates what the move execution already does.
Remove that duplication as part of this brief. Do not add a second way of walking a
path or of resolving a climb, jump or drop.

## Rulings for this brief

Follow them, and restate them in your report.

1. **Charges may use rolls.** Brief 007's ruling 5 is withdrawn. A charge route may
   include sheer climbs, gap jumps and drops of 3" or more. Each is rolled when the
   model gets there, exactly as in a Move, with the same marker prompts and the same
   results on failure. A failed roll on the way means the charge has failed.
2. **Route choice:** charge mode has a toggle, "allow climbs and jumps", off by
   default. Off: the shortest roll-free route. On: the shortest route of any kind.
   The existing Drop / Climb down toggle applies as for a Move. The choice is part
   of the declaration and cannot be changed after the D6 is rolled.
3. **Order:** declare (target and route choice), roll the D6, then move; the rolls
   on the route happen during the move, in order.
4. **Not enough distance:** unchanged from 007. The model moves along the route as
   far as its distance allows and stops at the last position where it can legally
   stop outside every enemy's 1" zone. A climb or jump it cannot complete with the
   distance left is not started.
5. **Any visible enemy within 12" can be declared,** including one that cannot be
   reached even with a 6. The label says so ("cannot reach"), the player may charge
   anyway, and ruling 4 applies.
6. **No contact position exists** (the target stands on something no wider than its
   base, or is walled in): the charger heads for the position closest to the target,
   edge to edge, where it can stop. If it ends within 1" of the target it is in
   melee and the target counts as charged.
7. **Base contact:** the two bases touch seen from above, and the two upright
   cylinders overlap in height: the feet of the model standing higher are below the
   top of the model standing lower. The 1" floor difference limit from 007 is
   withdrawn.
8. **Sliding around the target** may change level. It must keep contact (ruling 7)
   the whole way, use no rolls, and end where the model can stop.
9. **Interposing** is unchanged, and is worked out on the chosen route.
10. **Down models cannot move or be moved,** except by falling.
11. **Every success roll made by a Down model gets -1 die,** through a modifier
    provider like the other modifiers.
12. **A model that goes Down during its own activation ends that activation.** In a
    Retreat, if a free attack puts the model Down, it stays where it is, in melee.
    (Free attacks do no damage until brief 009; build and test this with a test
    hook that applies a Down.)
13. **Ledge roll:** see `docs/rules/markers.md`. A ledge is an edge of the floor the
    model stands on with a drop of more than 1". When a standing model suffers a
    Down result with any edge of its base within 1" of a ledge, it makes a success
    roll first, without the Down penalty and not risky. Markers can be spent on it
    as on any success roll. Success: Down where it is. Failure: it falls over the
    nearest ledge using the existing falling rules (landing spot, fall injury roll
    for 3" or more), and is Down where it lands. A model already Down makes no
    ledge roll. One ledge roll per Down result; a Down caused by the fall's own
    injury roll does not trigger another.

## Build

**Core**
- Charge on the shared movement process, with rulings 1 to 9. Core reports for each
  target, for both route choices: the route, its length, the rolls on it, the D6
  needed (none, 1 to 6, or cannot reach), and any interposing model.
- Contact test and sliding per rulings 7 and 8.
- Down rules per rulings 10 to 12.
- Ledge detection as a query on the height field (plain data), and the ledge roll
  as a step in resolving a Down result, using the roll pipeline and pending
  decisions. It must work wherever a Down result comes from.
- Undo, redo and replay keep working across all of it.

**Game**
- Charge mode: the "allow climbs and jumps" toggle (button and hotkey); labels such
  as "certain", "needs 4+", "needs 2+, 1 risky roll", "cannot reach"; the previewed
  route marks risky parts in orange like the movement indicator.
- A failed roll during a charge is shown in the tray as the charge failing.
- The ledge roll appears in the tray with a line saying why it is rolled.
- Building the charge options currently takes 1 to 1.7 s per charger. Do not make
  it slower; say in your report what it takes now with two route choices.
- Test table: a target on a pillar no wider than its base; a target up a sheer wall
  with a longer roll-free way round; a target across a gap; a target on a 2" step
  next to open ground; a model standing within 1" of a ledge of more than 1", and
  one next to a 1" step (no ledge).

**Tests**
- A charge route with a sheer climb, with a gap jump and with a 3" drop: the roll
  happens, success continues to contact, failure has the Move result and the charge
  fails.
- Route toggle: off gives the roll-free route, on gives the shorter risky one; the
  needed D6 differs accordingly.
- Hopeless charge can be declared and stops short outside every zone.
- Pillar case: ends at the closest stoppable position; in melee if within 1".
- Contact across heights: allowed on a 2" step for a model taller than 2", refused
  when the cylinders do not overlap in height. Sliding across a level change.
- A Down model cannot be given any move; its success rolls get -1 die; standing up
  removes the penalty.
- Going Down in its own activation ends the activation, including in a Retreat.
- Ledge: roll made within 1" (measured from the base edge) of a drop over 1"; not
  made at exactly more than 1" away, at a 1" drop, or when already Down; success
  and failure results; fall of 3" or more adds its injury roll; no second ledge
  roll from that.
- Charge, Move, Dash and Retreat all resolve climbs, jumps and drops through the
  same code (a test that would fail if a second implementation were added is
  welcome, a statement in the report is the minimum).
- All existing tests still pass, updated where 007's rulings were withdrawn.

## Test suite speed

The suite now takes about 7 minutes. Report which test scripts take the longest.
If something simple cuts the time a lot without losing coverage (for example
sharing a built reach field between tests), do it; otherwise only report.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (capture tooling, real mouse clicks): a charge up a sheer wall
  with the toggle on, succeeding and failing; the same target charged the long way
  round with the toggle off; a hopeless charge; the pillar case; contact on the 2"
  step; a ledge roll failing and the model falling.
- `core/` has no scene-tree access and no physics queries, the only random calls are
  in the dice service, and the roll resolver names no specific rule.

## Out of scope

Melee and ranged attacks, weapons, armour, Bloodbath, cover, morale, real miniature
models, map import.
