# Rolls

The roll system is a general base that every other rule plugs into. Nothing about a
specific weapon, ability or keyword is hard-coded in it (see `docs/design.md`).

## Success roll

- Roll 2d6. A total of 7 or more is a success; less is a failure.

## Criticals

- A total of 12 or more is a critical, but only on ranged and melee attack success
  rolls, and wherever an ability explicitly refers to criticals.
- A critical ranged or melee attack gives +1 die on the resulting injury roll.

## Plus and minus dice

- All "+1" and "-1" modifiers on rolls are dice modifiers unless a rule says otherwise.
- Plus and minus dice cancel one for one first.
- Each remaining +1 die adds a die to the roll; keep the highest dice.
- Each remaining -1 die adds a die to the roll; keep the lowest dice.
- The number of dice kept is the base size of the roll: 2 for a normal roll, 3 for a
  Bloodbath injury roll. Example: a 3d6 roll at +1 rolls 4 dice and keeps the highest 3.

## Risky rolls

- If a risky success roll fails, the model's activation ends immediately.
- Dash, climbing and jumping are risky. After a first failed morale test, all of
  that warband's success rolls are risky (see `morale.md`).

## Marker spending

- Blood and blessing markers are spent before the dice are rolled (see `markers.md`).

## Roll-off

- Both players roll a d6; the higher roll wins. Ties are rolled again.
