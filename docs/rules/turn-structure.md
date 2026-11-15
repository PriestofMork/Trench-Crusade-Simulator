# Turn structure

## Turns and activations

- A game is a series of turns. In a turn, players alternate activating one model at
  a time until every model has activated.
- At the start of a turn, the player with fewer models on the battlefield that are
  not Down chooses which player activates first.

## Activation

1. If the model is Down, it stands up, unless an ability prevents it. Standing up is
   not an action. A model that stood up this activation has its movement halved
   (equivalently, all movement costs are doubled).
2. The model may take any number of actions, but each action at most once.
3. Move, Charge and Retreat are all **move actions**: a model may take only one of
   them per activation. Dash is a separate action.

## Actions

| Action | Type | See |
|---|---|---|
| Move | move action | `movement.md` |
| Charge | move action | `movement.md` |
| Retreat | move action | `movement.md` |
| Dash | risky | `movement.md` |
| Ranged attack | | `attacks.md` |
| Melee attack | | `attacks.md` |
| Ability actions (e.g. Aim) | per ability | per ability |

## Open questions

1. Tie on non-Down model count: who chooses?
2. When one player has no unactivated models left, does the other activate all of
   theirs in a row? (Assumed yes.)
3. Is the first-activation choice made every turn, including turn 1? (Assumed every
   turn; scenarios may override turn 1.)
