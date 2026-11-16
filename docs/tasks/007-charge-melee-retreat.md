# 007: Charge, the melee zone and Retreat

## Goal

Models can get into melee and out of it. Charge is the only way to come within 1" of
an enemy; a model within 1" of an enemy is in melee and can only leave by
Retreating, which gives the enemies a free attack. Attacks themselves do not exist
yet, so the free attack is a hook that a later brief fills.

Rules reference: "Charge" and "Melee and Retreat" in `docs/rules/movement.md`,
`docs/rules/turn-structure.md`, `docs/rules/rolls.md`.

## Rulings for this brief

These fill gaps in the rules files. Follow them, and restate them in your report so
the project owner can confirm or change them.

1. **Order of a charge:** the player declares the target, then the D6 is rolled,
   then the model moves. The declaration cannot be changed after the roll.
2. **Charge distance:** Movement characteristic + D6, and the whole sum is halved if
   the model stood up this activation.
3. **Charge path:** the shortest legal path from the charger to base contact with
   the target, treating enemy 1" zones as open (bases still block). "As straight as
   possible" means this shortest path; the player does not draw it.
4. **Interposing:** if that path enters within 1" of another enemy model before
   reaching the target, that model becomes the target instead, and the path is
   recomputed to it. The player is told before confirming the declaration.
5. **Charges use no rolls on the way:** a charge path may use walking, open climbs,
   ladders, low obstacles and drops under 3", but not sheer climbs, gap jumps or
   drops of 3" or more. A target that can only be reached with such a roll cannot be
   charged.
6. **Base contact across heights:** the charger must end on a position where it can
   stop, with its base touching the target's base seen from above, and with the two
   floors no more than the low obstacle height (1") apart.
7. **Failed charge:** if the distance is not enough, the model moves along the charge
   path as far as its distance allows and stops at the last position on it where it
   can legally stop outside every enemy's 1" zone.
8. **Multi-charge:** after reaching contact, the player may spend leftover distance
   sliding around the target's base while staying in contact. Wherever the model
   ends, every enemy within 1" of it counts as charged. The game records which
   models were charged, for later rules.
9. **In melee:** a model within 1" of an enemy (edge to edge, measured in 3D between
   the two cylinders) is in melee. Down models count. A model in melee cannot take
   Move, Dash or Charge; of the move actions it can only Retreat.
10. **Retreat:** a move action. First every enemy within 1" gets a free melee attack
    against the retreating model, in an order chosen by the enemy player. Then, if
    the model is still standing, it moves like a normal Move (in steps, same
    budget), and must end outside every enemy's 1" zone. It may not come within 1"
    of any enemy it was not already in melee with.
11. **Sight:** a charge needs the target to be visible. Line of sight does not exist
    yet, so sight is asked through one interface with a temporary implementation
    that always answers yes, clearly marked temporary.
12. **Range to the target:** "within 12 inches" is measured edge to edge in a
    straight line, ignoring terrain.

## Build

**Core: melee zone**
- Queries: which enemies a model is in melee with; whether a model is in melee.
  Action availability follows ruling 9, with a reason the HUD can show.
- The existing rule that Move and Dash may not enter an enemy's 1" zone stays.

**Core: sight interface**
- One small interface answering "can model A see model B" (ruling 11). Everything
  that needs sight goes through it, so brief 008 only replaces the implementation.

**Core: Charge**
- Registered in the action registry as a move action.
- Declaration: legal targets are enemy models that are visible and within 12"
  (ruling 12). For each, core can report: the path, its length, whether an
  interposing model replaces the target, and the D6 result needed (none, a number
  from 1 to 6, or impossible).
- Resolution: the D6 is a plain d6 through the roll pipeline, shown in the tray. No
  marker spending on it. Then either contact is reachable or the charge fails
  (ruling 7).
- Contact positions: the set of positions around the target's base that the charger
  can end on, given the distance left after first contact (ruling 8). The player
  chooses one as a pending decision; first contact is the default. Sliding must
  stay legal the whole way (terrain, other bases, a place to stop at the end).
- Result: the model is in melee; the charged models are recorded on the activation.
- Everything goes through commands, pending decisions and events, and works with
  undo, redo and replay like the staged moves from brief 006. Reuse that machinery.

**Core: Retreat**
- Registered as a move action, available only in melee.
- Free attacks: a hook interface, "resolve a free melee attack by model X against
  model Y", with a temporary implementation that only emits an event saying the
  attack would happen. The order is a pending decision for the enemy player when
  more than one enemy is in range. Brief 009 fills the hook.
- Then the move, as in ruling 10, using the existing move execution with the extra
  end condition.

**Game**
- **Charge mode:** a Charge button (and hotkey). In charge mode every enemy within
  12" is marked with what the charge needs: "certain", "needs 3+", or "out of
  reach", and the charge path is previewed on hover. An interposing model is shown
  clearly: the path stops at it and the label names it as the actual target.
- Clicking a target asks for confirmation, then the D6 rolls in the tray.
- On success, the reachable contact positions are shown as an arc around the
  target's base; other enemies that would also be charged from the hovered position
  are highlighted. Click to choose.
- On failure, the model moves as far as it gets, and the tray says the charge failed.
- **Melee indicator:** models in melee are visibly linked or marked, and the 1" zone
  of enemies is shown faintly while a model is selected for movement, so it is clear
  why the movement area stops short of them.
- **Retreat:** a Retreat button in melee. It lists the free attacks that will
  happen, asks for confirmation, plays them as tray messages (temporary), then
  switches to the normal movement indicator for the retreat move.
- The movement indicator for a model in melee shows nothing for Move, with the HUD
  explaining why.
- Add a few models to the test table placed for these cases: a clear charge, a
  charge with an interposing model, two enemies close enough for a multi-charge, a
  target on a low obstacle, a target on a 2" wall (not chargeable from below without
  a route), and a pair already in melee.

**Tests**
- Melee zone: in and out at exactly 1"; height separation; Down models count;
  action availability in melee.
- Charge declaration: the 12" limit; needed D6 for near, far and impossible targets;
  halving after standing up applies to the sum; a target reachable only by a roll is
  not chargeable (ruling 5).
- Interposing: the target is replaced; no interposer when the path passes more than
  1" away.
- Resolution: success ends in base contact and in melee; failure stops short as in
  ruling 7 and never inside a 1" zone; the D6 goes through the dice service.
- Contact across heights: allowed onto and from a low obstacle, refused across a
  larger height difference.
- Multi-charge: sliding within the leftover distance; sliding blocked by terrain or
  a base; all enemies within 1" at the end are recorded as charged.
- One move action per activation: Charge after Move is refused; Charge after Dash is
  allowed; Dash after a successful Charge is refused.
- Retreat: only in melee; each enemy in range gets one free attack through the hook;
  the order decision when there are several; the move must end outside every zone;
  entering a new enemy's zone is refused.
- Undo, redo and replay across a charge with a contact choice.
- All existing tests still pass.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots with the capture tooling, using real
  mouse clicks for the prompts): a certain charge; a charge that needs a roll,
  succeeding and failing; an interposed charge; a multi-charge chosen on the contact
  arc; a model in melee unable to Move; a Retreat with two free attacks listed and
  the model moving away.
- `core/` has no scene-tree access, the only random calls are in the dice service,
  and the roll resolver names no specific rule.

## Out of scope

Melee and ranged attacks, weapons, armour, Bloodbath, line of sight (only the
interface), morale, game end, difficult and dangerous terrain, real miniature
models, map import.
