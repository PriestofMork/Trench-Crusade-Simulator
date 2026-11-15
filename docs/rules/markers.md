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

## Open questions

1. Infection growth: "start of the turn" is read as the start of the model's own
   activation, not the start of the game turn. (Assumed.)
2. Do infection markers count towards the 6 (or 3) needed for a Bloodbath? (Assumed yes.)
3. What can a model do if it is prevented from standing up?
