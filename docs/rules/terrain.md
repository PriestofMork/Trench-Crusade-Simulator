# Terrain

How terrain is classified for movement. Line-of-sight effects are in
`line-of-sight.md`.

## Tunable values

Kept in one place in the code, like the cylinder heights.

| Value | Start |
|---|---|
| Open step: highest step that is simply walked | 1" |
| Trench wall: highest wall treated as open inside a trench zone | 3" |
| Steep slope: steepest slope that can be walked | 45° (proposed) |

## What geometry decides automatically

- **Step up or down of at most the open step:** open terrain, walked freely.
- **Slope up to the steep angle:** walked. The cost is the distance along the slope.
- **Slope steeper than the steep angle, or a step higher than the open step:**
  a sheer surface. It must be climbed (a risky roll), or jumped down.

## What is marked when a map is blocked out

Geometry cannot tell a trench wall from any other wall, so these are marked by hand
(proposed approach, not yet confirmed by the project owner):

- **Trench zone:** an area drawn on the map. Inside it, walls up to the trench wall
  height are open terrain.
- **Per-piece override:** a single piece can be forced to "trench wall",
  "impassable" (cannot be stood on or crossed) or "cannot be climbed".
- **Ladder or stairs link:** a connection between a bottom point and a top point
  that counts as open terrain.

## Standing on terrain

- A model stands on a floor: the table, or the top of a terrain piece.
- It needs headroom: the gap between its floor and anything above it must be at
  least the model's cylinder height.
- The centre of its base must be supported by the floor. The base may overhang a
  drop, but may not overlap terrain that rises more than the open step above its
  floor.

## Open questions

1. Confirm the marking approach and the 45° starting value.
2. Movement cost of an open step or trench wall: none beyond the horizontal distance?
   (Assumed: none.)
3. Difficult and dangerous terrain.
