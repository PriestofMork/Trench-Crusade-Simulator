# Line of sight

Status: **draft**. Not to be implemented until the open questions are closed.

## Principle

Models are cylinders, as in Kill Team and Star Wars: Legion. The sculpt is ignored:
a raised sword or a banner never gives or blocks line of sight.

## Model volume

- A model's volume is a vertical cylinder standing on its base.
- Diameter = the model's base size.
- Height = one fixed value per base size. The table of values is still to be set.

## Visibility

- A target is visible if a straight, unblocked line exists from any point of the
  attacker's cylinder to any point of the target's cylinder.

## Terrain

- Only the simplified collision shapes of terrain count, never the visual mesh.
- Each terrain shape is either blocking or not blocking for line of sight.

## Open questions

1. **Height values.** The actual height in inches for each base size.
2. **Cover.** Deferred on purpose; to be discussed later. Visibility (yes/no) can be
   implemented without it.
3. **Other models.** Do models block line of sight to models behind them, give cover,
   or neither?
4. **Height advantage.** Any effect from shooting from higher ground?
