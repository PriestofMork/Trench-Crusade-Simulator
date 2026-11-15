# Movement

## Move

- The model moves up to its Movement characteristic in inches.
- Climbing and jumping are done as part of a move.
- A model may only come within 1" of an enemy model by charging.
- A model may move through friendly models' bases freely, but may not end its
  movement with its base overlapping another base.
- A model may not move through enemy models' bases.

## Open terrain, walls and low obstacles

See `terrain.md`. In short: walls up to 3" are climbed without a roll by paying
their height; low obstacles up to 1" are free to cross; anything higher, or tagged
Sheer, is a sheer surface and needs the climb below.

## Climb

- A model whose base touches a sheer surface may attempt to climb up or down it.
  (The tabletop rule allows 1" of slack; the digital game does not need it.)
- It must have enough movement left to clear the whole surface; it can never end
  part-way up.
- Make a risky success roll when the model reaches the surface.
  - Success: the model is moved to the top or bottom of the surface, with its base
    placed directly above (or below) the point where it touched the surface. If the
    surface is slanted, it is placed at the closest point on the top (or bottom).
    It may carry on moving with whatever movement it has left. It may pass through a
    spot where it could not stop (such as a corner), but must end the move somewhere
    it can (see "Where a model can be" in `terrain.md`).
  - Failure: the model stays where it attempted the climb, and its activation ends.
- Cost: the vertical distance climbed, in inches of movement.

## Jump over a gap

- Declared as part of a move. The model's base must be at the ledge.
- The gap may be no wider than half the model's Movement characteristic, and the
  distance moved to the ledge plus the gap width may not exceed what the model can
  move.
- Make a risky success roll at the ledge.
  - Success: the model is moved to the far side and may continue with any movement
    it has left.
  - Failure: the model falls, and its activation ends.
- **Ledges of unequal height:**
  - Far side lower: on a successful jump, also apply the rules for jumping down.
  - Far side higher: add the extra height to the gap width. If that total is more
    than the model can jump or move, the jump is impossible.

## Jump down

- A model may jump down as part of a move. It costs no movement.
- A drop of 3" or more counts as falling: make the injury roll, and then the model
  may carry on with its move.

## Falling

- The model is moved to the closest space it can legally occupy on the first flat
  surface beneath the position it fell from.
- A fall of less than 3" has no effect.
- A fall of 3" or more causes an injury roll against the model at +1 die for every
  full 3" fallen (3–5" is +1, 6–8" is +2, 9–11" is +3).

## Dash

- A risky success roll. On a success the model moves up to its Movement
  characteristic again.

## Charge

- Target: an enemy model the charger can see, within 12".
- The charger moves up to its Movement characteristic + d6 inches.
- The path must be as straight as possible, but may bend to avoid things such as
  dangerous terrain.
- The charge ends when the charger's base touches the target's base.
- If the distance is not enough to reach the target, the charger stops where its
  movement runs out, along the charge path.
- **Interposing:** if the path would bring the charger within 1" of a different enemy
  model, the charger must charge that model instead.
- **Multi-charge:** after touching the target's base, the charger may spend remaining
  movement sliding around that base while staying in contact. If that brings it
  within 1" of further enemy models, it may stop there and counts as having charged
  every enemy model it is now within 1" of.

## Melee and Retreat

- A model is in melee while within 1" of an enemy model.
- Retreat is a move action that lets the model leave the 1" zone. Before it leaves,
  every enemy model within 1" makes a free melee attack action against it.

## Open questions

1. Does a model in melee have any way to move other than Retreat? (Assumed: no.)
2. A model that goes Down from a fall mid-move: its move ends there. (Assumed.)
3. Difficult and dangerous terrain.

Slopes, steps and what counts as a sheer surface are defined in `terrain.md`.
