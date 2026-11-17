# Markers and states

## General

- A model can hold at most 6 markers of each kind.
- Markers are spent before the dice are rolled, never after seeing the result.

## Blood markers

- Placed on a model by injury rolls against it.
- Spent by the opposing player:
  - +1 die per marker on an injury roll against the marked model.
  - -1 die per marker on a success roll made by the marked model (assumed).
  - 6 markers (3 if the model is Down) for a Bloodbath (see `attacks.md`).

## Blessing markers

The reverse of blood markers. Spent by the model's own player:

- +1 die per marker on a success roll made by the model.
- -1 die per marker on an injury roll made against the model.

## Infection markers

- Spent exactly like blood markers, by the opposing player, on the same rolls and
  with the same effect. In a prompt, blood and infection markers on the model are
  offered together, and the player chooses how many of each to spend.
- Placed only by specific effects, never by ordinary injury rolls.
- At the start of a model's activation, if it has at least one infection marker, it
  gains one more (up to the cap).
- Infection markers count together with blood markers towards a Bloodbath.

## Sin markers

- Faction-specific. To be defined much later.

## Prompts in the digital game

- When a roll is about to be made in the dice tray, the opponent is asked whether to
  spend blood markers on it, and the rolling player is asked whether to spend
  blessing markers, if any are available. The dice are rolled only after both have
  answered.
- Order: the opponent decides on blood markers first; then the rolling player
  decides on blessing markers, seeing the opponent's choice.

## Down

- A Down model stands up at the start of its activation unless an ability prevents
  it; its movement is halved for that activation.
- Melee injury rolls against a Down model get +1 die.
- A Down result against a Down model places one extra blood marker instead.
- Down models do not count as standing for morale or for choosing who activates first.
- A Down model is otherwise an ordinary model: it is in melee with enemies within 1"
  and makes free attacks against retreating models.
- A Down model cannot move or be moved. The only exception is falling.
- Every success roll made by a Down model gets -1 die.
- A model that goes Down during its own activation ends that activation.

### Going Down next to a ledge

- A ledge is the edge of the floor the model stands on where the drop is more than
  1".
- When a standing model suffers a Down result while any edge of its base is within
  1" of a ledge, it first makes a success roll. The roll is made before the model is
  Down, so without the Down penalty.
- On a success it goes Down where it is.
- On a failure it falls over the nearest ledge, following the falling rules in
  `movement.md` (including the injury roll for a fall of 3" or more), and is Down
  where it lands.
- A model that is already Down makes no ledge roll.

## Open questions

1. What can a model do if it is prevented from standing up?
