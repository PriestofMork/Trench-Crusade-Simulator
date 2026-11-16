# Line of sight

Status: visibility (yes or no) is implemented by brief 008. Cover is still open.

## Principle

Models are cylinders, as in Kill Team and Star Wars: Legion. The sculpt is ignored:
a raised sword or a banner never gives or blocks line of sight.

## Model volume

- A model's volume is a vertical cylinder standing on its base.
- Diameter = the model's base size.
- Height = one fixed value per base size:

| Base | Height |
|---|---|
| 25 mm | 1.7" |
| 32 mm | 1.9" |
| 40 mm | 2.2" |
| 50 mm | 2.6" |
| 60 mm | 3.0" |

These values are first estimates and will be tuned. They must live in one data table,
never be hard-coded where they are used.

## Other models

- Models block line of sight: the cylinder of any model other than the attacker and
  the target blocks sight lines exactly like blocking terrain. This applies to
  friendly and enemy models alike.

## Tilt on slopes

- For sight and for being seen or hit, a model's cylinder is tilted to sit flush on
  the surface it stands on, exactly as the model is drawn. There is no cap on the
  tilt.
- Everything else keeps the upright cylinder and the base seen from above:
  movement, support, the 1" melee zone and headroom.

## Visibility

- A target is visible if a straight, unblocked line exists from any point of the
  attacker's cylinder to any point of the target's cylinder.

## Terrain

- Only the simplified collision shapes of terrain count, never the visual mesh.
- Each terrain shape is either blocking or not blocking for line of sight.

## Open questions

1. **Cover.** Deferred on purpose; to be discussed later. Visibility (yes/no) can be
   implemented without it.
2. **Height advantage.** Any effect from shooting from higher ground?
