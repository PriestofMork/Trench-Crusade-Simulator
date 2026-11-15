# Turn structure

## Turns and activations

- A game is a series of turns. In a turn, players alternate activating one model at
  a time until every model has activated.
- At the start of a turn, the player with fewer models on the battlefield that are
  not Down chooses which player activates first. On a tie, the players roll off
  (see `rolls.md`) and the winner chooses.

## Activation

1. If the model is Down, it stands up, unless an ability prevents it. Standing up is
   not an action. A model that stood up this activation has all of its movement
   halved for that activation (equivalently, all movement costs are doubled): its
   Move, its Dash, any extra movement it gains from equipment or abilities, and
   the D6 of a charge.
2. The model may take any number of actions, but each action at most once.
3. Move, Charge and Retreat are all **move actions**: a model may take only one of
   them per activation. Dash is a separate action.

## Starting and ending an activation

- A model's activation starts when it takes its first action. Selecting it does not.
- Once a model has started its activation, no other model acts until it ends.
- A player may end an activation at any time, including without acting.
- If a player has no unactivated models left, the other player keeps activating.
- The first-player choice is made at the start of every turn, including turn 1.

## Taking things back

- Any step can be undone. Whether a take-back is acceptable is agreed between the
  players; the game does not police it.
- Undo restores the dice too: repeating the same thing after an undo gives the same
  roll.

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
