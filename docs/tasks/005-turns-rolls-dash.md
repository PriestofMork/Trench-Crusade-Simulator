# 005: Turns, activations, the roll pipeline, the dice tray and Dash

## Goal

The sandbox becomes a game loop. Two players take turns activating models; each
action can be used once per activation; rolls go through one general pipeline and are
shown in a dice tray with marker prompts; Dash is the first action that rolls.

Rules reference: `docs/rules/turn-structure.md`, `docs/rules/rolls.md`,
`docs/rules/markers.md`, and "Move" and "Dash" in `docs/rules/movement.md`.
Design reference: "Rolls are a general pipeline" and "Pending decisions" in
`docs/design.md`. Hard rules 3 and 4 in `CLAUDE.md` matter most here.

## Rulings for this brief

These fill gaps in the rules files. Follow them, and list them in your report so the
project owner can confirm or change them.

1. A Move action may be made in several steps: the model can move part of its
   distance, then more, as long as the total stays within the action's budget. The
   action is finished as soon as the model does anything else (starts another action
   or ends its activation); movement left over is then lost. The same applies to the
   move granted by a successful Dash.
2. A model's activation starts when it takes its first action, not when it is
   selected. Selecting only previews. Once a model has started its activation, no
   other model can act until that activation ends.
3. A player may end an activation at any time, including without acting.
4. If a player has no unactivated models left, the other player keeps activating.
5. The choice of who activates first is made at the start of every turn, turn 1
   included.
6. A model that stood up this activation has all of its movement halved for that
   activation: Move, Dash, any extra movement it gains from other rules, and later
   the D6 of a charge. Apply the halving in one place that every movement budget
   passes through.
7. Marker prompts: the opponent decides on blood markers first, then the rolling
   player decides on blessing markers, seeing the opponent's choice. A prompt is
   skipped when there is nothing to spend.

## Build

**Core: turn and activation state**
- `GameState` tracks: turn number, which player is to act, which model (if any) is
  mid-activation, which models have activated this turn, and per activation which
  actions have been used.
- Start of turn: the player with fewer models that are not Down chooses who
  activates first; on a tie there is a roll-off first. Both the choice and the
  roll-off are pending decisions answered by commands.
- Actions are data: an id, whether it is a move action, whether it is risky. Each
  action once per activation; only one move action per activation. Build this as a
  registry so later briefs add Charge, Retreat, attacks and ability actions without
  touching the activation code.
- Commands: choose first player, begin an action, end activation. Every command
  checks whose decision it is and rejects anything else.
- `ModelState` gains: Down flag, and marker counts for blood, blessing and
  infection (cap from `markers.md`). Standing up at the start of an activation and
  the halved movement follow `turn-structure.md`.
- Remove `ResetMovementCommand`. Movement budgets now come from the action being
  taken, not from a per-model counter that is reset by hand.
- The turn ends when every model has activated; the next turn begins with the
  first-player choice. No morale and no game end yet.

**Core: roll pipeline**
- A roll request is data: kind (success roll, injury roll, plain d6, roll-off),
  how many dice are kept (2 or 3), whether it is risky, who rolls, and its context
  (model, target, action, weapon; unused parts empty).
- Modifiers are collected from providers, never computed inside the resolver. A
  modifier is a record: a label for the breakdown, a dice delta, or a flag change
  such as "this roll is risky". This brief registers providers for: spent blood
  markers, spent blessing markers, and "all success rolls are risky" as a
  warband-level flag (set only by the override command for now, for testing).
- Resolution: cancel plus against minus dice, roll through the dice service, keep
  the highest or lowest dice, total, and classify (success at 7+; critical only when
  the request allows criticals). The result records every die rolled, which were
  kept, the modifiers applied and the outcome.
- Reactions: other rules can register to act on a result. This brief uses it for
  "a failed risky roll ends the activation". Nothing in the resolver names a specific
  action, weapon or ability.
- Marker spending is a sequence of pending decisions before the dice are rolled, in
  the order of ruling 7. Spending removes the markers. Core never blocks: it exposes
  the pending decision and continues when the answering command arrives.
- Only success rolls and roll-offs are exercised in this brief. Injury rolls must be
  representable (3 dice kept, modifiers both ways) and unit-tested at the resolver
  level, but nothing triggers one yet.

**Core: events**
- Applying a command returns a list of events describing what happened in order
  (activation started, roll requested, decision needed, roll resolved, model moved,
  activation ended, turn started). The game layer plays these back; it does not
  inspect state changes to guess what happened.

**Core: actions in this brief**
- **Move:** as built, now as an action, with the budget from the Movement
  characteristic (halved after standing up), spent over one or more steps as in
  ruling 1. The indicator shows what is left after each step.
- **Dash:** a risky success roll. On success the model gets a move of up to its
  Movement characteristic (halved after standing up), chosen like a normal move. On
  failure the activation ends. The player may decline the move after a success.

**Core: undo**
- Players can take things back; whether a take-back is acceptable is agreed between
  them, not enforced. Provide undo of the last command, repeatable back to the start
  of the game, and redo.
- Undo is not a rule command. It lives beside the command log: keep a snapshot of
  the full game state, including the dice service's state, before each command, and
  restore it. Because the dice state is restored too, repeating the same command
  after an undo gives the same dice, so undo cannot be used to fish for a better
  roll. Pending decisions are part of the state and are restored with it.
- Undoing a step of a multi-step Move gives that distance back.

**Core: manual override**
- Override commands, clearly separated from rule commands: set a model's markers,
  set or clear Down, set the "all success rolls risky" flag for a player. These are
  the start of the manual override required by `docs/design.md`.

**Game: HUD and flow**
- A HUD showing the turn number, whose decision it is (in the player's colour), and
  for the selected model: its markers, Down state, and action buttons (Move, Dash,
  End activation) with used or unavailable actions greyed out and a reason on hover.
- Selecting an own, unactivated model with Move available shows the movement
  indicator as before; clicking a destination takes the Move action. Models that
  have activated are visibly marked on the table.
- Both players use the same screen and mouse (hotseat). Every prompt names the
  player who must answer it.
- A start-of-turn prompt for the first-player choice, with the roll-off shown in the
  dice tray when it happens.

**Game: dice tray**
- A tray panel that appears for every roll and shows, in order: what is being rolled
  and by whom; the modifier breakdown as a list of labelled lines (cancelled plus
  and minus dice shown as cancelled); the marker prompts; then the dice.
- Dice are drawn as dice, tumble briefly and land on the values core already
  rolled. Kept dice are highlighted, dropped dice dimmed. Then the total and the
  outcome (success, failure, critical; "activation ends" for a failed risky roll).
- The tray is driven only by events. It must never roll or decide anything itself.
- Keep it quick: a roll with no prompts should take about two seconds, and a click
  or key skips the animation.
- A simple, clean 2D panel is fine. 3D physics dice are out of scope.

**Game: override panel**
- Undo and redo buttons in the HUD, also on Ctrl+Z and Ctrl+Y, always available to
  whoever is at the screen.
- A panel toggled with a key that sends the override commands for the selected
  model. It is how blood and blessing prompts get tested in this brief.

**Tests**
- Turn order: fewer standing models chooses; tie leads to a roll-off, repeated on a
  drawn roll-off; alternation; the other player continuing when one runs out; the
  turn ending and the next beginning.
- Activation: starts on first action, blocks other models, each action once, one
  move action only, ending early, commands from the wrong player rejected.
- Standing up: a Down model stands at activation start and moves at half distance.
- Resolver: plus and minus cancel; keep highest and keep lowest; 2 and 3 dice kept
  (a 3d6 roll at +1 rolls four and keeps three); 7+ succeeds; critical only when
  allowed; a fixed seed gives a fixed result.
- Markers: spending is offered in the order of ruling 7, skipped when empty, capped
  by what the model has, removes the markers, and changes the dice as expected.
- Risky: a failed Dash ends the activation; a successful one grants the move; the
  warband flag makes a normally safe success roll risky.
- Events: a full Dash with a blood prompt produces the expected event sequence.
- Multi-step Move: two steps within the budget are accepted, a third beyond it is
  rejected, and starting Dash closes the Move with its remainder lost.
- Undo and redo: undoing a move restores position and budget; undoing a resolved
  roll restores markers, activation state and dice state, and repeating the command
  gives the identical roll; undoing back through a pending decision restores it.
- Replay: the same seed and the same command list give the same final state.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots with the capture tooling): a full turn
  can be played by two players in hotseat; a Dash shows the tray with breakdown,
  dice and outcome; with blood and blessing markers set through the override panel,
  both prompts appear in order and change the roll; a failed Dash ends the
  activation.
- `core/` has no scene-tree access, the only random calls are in the dice service,
  and the roll resolver contains no reference to Dash, blood or blessing by name.

## Out of scope

Charge, retreat, attacks, injury effects, sheer climbs, jumps, falling, morale, game
end, infection growth, real miniature models, online play, 3D dice.
