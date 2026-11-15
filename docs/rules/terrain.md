# Terrain

How terrain is classified for movement. Line-of-sight effects are in
`line-of-sight.md`.

## Tunable values

Kept in one place in the code, like the cylinder heights.

| Value | Start |
|---|---|
| Low obstacle: highest thing that is free to cross | 1" |
| Open climb: highest wall climbed without a roll | 3" |
| Steep slope: a slope steeper than this is a wall | 70° |

## Tags

Every terrain piece starts untagged, which means open terrain. A piece can be tagged:

| Tag | Effect |
|---|---|
| (none) | Open. Its height decides how it is crossed, as below. |
| Sheer | Always needs a climb roll, whatever its height. |
| Ladder | Never needs a climb roll, whatever its height (ladders, stairs, ropes). |
| Impassable | Cannot be crossed, climbed or stood on. |

## Slopes

- A slope of up to the steep angle is walked. The cost is the distance along the slope.
- A steeper slope is a wall, and is treated by its height like any other wall.

## Walls and steps (going up)

The height of a wall is the vertical distance from the floor the model is on to the
top it is climbing to.

- **Up to the open climb height (3"):** an open climb. No roll. The model touches
  the wall, pays the height in movement, arrives on top directly above the point it
  touched, and carries on with its remaining movement in one smooth move.
- **Higher, or tagged Sheer:** a sheer surface. Climbing it is a risky roll as
  described in `movement.md`.
- In both cases the model must have enough movement to reach the top; it never ends
  part-way up.

## Low obstacles

- A low obstacle is anything up to 1" high (boxes, sandbags).
- A model that crosses a low obstacle and comes down off it in the same move pays
  nothing for it.
- A model that ends its move on top of a low obstacle pays the obstacle's height.
  In practice: crossing low obstacles is free, and stopping on one adds its height
  to the cost of the move. A model that started the move on that obstacle pays nothing.

## Going down

- A drop of less than 3" is a free jump down with no effect.
- A drop of 3" or more is handled in `movement.md` (jump down and fall, or climb down).

## Where a model can be

**While moving**
- The centre of the base must be over the floor the model is moving on.
- The base may overhang a drop freely.
- The base may not overlap terrain higher than its floor, except the wall it is
  climbing at that moment. (Assumed.)
- So a model can climb at a corner or cross a narrow beam, even where it could not
  stop.

**Where the move ends**
- At least half of the base's area must be over the floor the model stands on.
- Headroom: the gap between the floor and anything above it must be at least the
  model's cylinder height.
- The base may not overlap another model's base or terrain higher than its floor.
- A low obstacle or ledge top that is too small to hold half the base can be crossed
  but not stopped on.
- If a failed roll or a fall would leave a model where it cannot stop, it is moved
  to the closest position where it can.

## Open questions

1. May a base on the ground overlap a low obstacle next to it (for example sandbags
   under the rim of the base)? (Assumed: no.)
2. Climbing down a wall of 3" or more instead of jumping: allowed, paying the height,
   with a roll only if the wall is sheer? (Assumed: yes.)
3. Difficult and dangerous terrain.
