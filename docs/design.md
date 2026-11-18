# Design

Standing decisions. Changed only from the planning thread; execution sessions follow it.

## Engine

- Godot 4, standard build, GDScript.
- **Pinned version: 4.7.2 stable.** The executables live in `Godot/` at the repository
  root (gitignored, not installed system-wide).

## Scope

- Two human players. Hotseat first, online later. No AI opponent.
- Rules are "Trench Crusade in spirit, as simple as possible to automate" and are
  written down in `docs/rules/`.
- Models are static (no rigging, no animation). They are the existing Tabletop
  Simulator models: OBJ meshes with texture images.

## Architecture

Two layers with a one-way dependency: `game/` knows `core/`, never the reverse.

**`core/` (rules engine)**
- `GameState`: plain data. Models, their positions, markers, whose activation it is.
- Commands: every player action is a small object (`MoveCommand`, `ShootCommand`, …)
  that is validated against the state and then applied. This gives replays, undo and
  networking for free later, because a game is just its seed plus its command list.
- Dice service: one seeded random source. Rolls are computed here; the 3D dice in the
  tray only display a result that already exists.
- Pending decisions: when resolution needs a player choice, core records what it is
  waiting for and who must answer. The UI shows a prompt and answers with a command.

**Rolls are a general pipeline, not special cases**
- A roll is a data object: its kind (success, injury, d6), base dice kept (2 or 3),
  whether it is risky, who rolls, and its context (actor, target, weapon, action).
- Modifiers are collected, not computed inline. Each is a small record: source label,
  dice delta, or a flag change such as "make this roll risky". Profile, weapon
  keywords, situation (long range, elevation), markers, abilities and skills all
  contribute through the same interface.
- New rules are added by registering a modifier provider or a reaction to a roll
  result (for example "on a critical, add +1 die to the injury roll"). The roll
  resolver itself never names a specific weapon, keyword or ability.
- The collected list is what the dice tray shows as the roll breakdown.

**`game/` (presentation)**
- 3D table, camera, selection, movement preview, dice tray, prompts.
- Reads core state, sends commands, plays back the events core emits.
- Each interaction mode (select, move, charge, retreat, and later shoot and fight) is
  its own controller script. `main.gd` only wires them together.

**Compute on demand**
- Compute only what the player is looking at right now, and only when they ask
  for it. Never compute something for every model or every target "in case".
- Cheap checks first (distance, a bounding test), the expensive search only for
  the one thing selected. Searches are goal-directed and stop when they arrive.
- Results are cached against the game state and thrown away when it changes.
- Budgets on the test table: opening a mode under 20 ms; one selected item (a
  route, a sight check) under 100 ms typical, 300 ms worst. The movement area of the
  selected model is the one larger computation, built in the background.
- Precision is chosen to be good enough for play, not exact: a 0.25" grid, a fixed
  set of sight sample points. Anything finer needs a reason.

## Decisions so far

| Topic | Decision |
|---|---|
| Model shape for rules | Every model is a cylinder defined by its base diameter and a height. The visual mesh is never used for rules. |
| Cylinder height | One fixed height per base size, from a single tunable table (values in `docs/rules/line-of-sight.md`). |
| Models and sight | Other models block line of sight, friendly and enemy alike. |
| Line of sight | Any point of the attacker's cylinder to any point of the target's cylinder, against simplified terrain volumes. Cover is deferred. See `docs/rules/line-of-sight.md`. |
| Terrain collision | Hand-blocked simple shapes (boxes, ramps), separate from the visual mesh. Used for both movement and line of sight. |
| Movement | Free, not grid-based. Select a model, see reachable distance, click to move. |
| Terrain data | Terrain is defined as plain data in core (simple shapes). The 3D scene, the navigation mesh and the rules checks are all built from that one definition. |
| Paths | `core/` computes a reach field (where the base centre can legally get to, and the path there) with its own geometry; Godot's navigation is not used. The move command still validates every path it is given. |
| Movement indicator | A selected model shows its reachable area as an outline with a faint fill, XCOM style, drawn from the reach field. The outline marks where the **edge** of the base can reach (the centre's area grown by the base radius). Blue: reachable without a roll. Orange: reachable only through a risky roll (climb or jump). |
| Height | Terrain becomes a layered height field: for each grid cell, the list of floor heights a base can stand on, derived from the terrain data. The reach field runs over (cell, floor) pairs. Walking, open climbs, sheer climbs, drops and gap jumps are all transitions between floors with a cost and, for risky ones, a roll. |
| Terrain marking | Per-piece tags only (none, sheer, ladder, impassable). Untagged pieces are open and their height decides how they are crossed. No trench zones. See `docs/rules/terrain.md`. |
| Stopping vs passing | A position has two tests: passable (base centre supported) and stoppable (half the base area supported, headroom, no overlap). The reach field may route through passable positions but only offers stoppable ones as destinations. |
| Markers | Spent before the roll; cap of 6 per kind per model. |
| Blood markers | When a roll is made, the opponent is prompted whether to spend blood markers on it. |
| Blessing markers | The rolling player is prompted whether to spend blessing markers, if they have any. |
| Modifiers | Weapon and situational modifiers are applied automatically and shown in the roll breakdown. |
| Descent mode | A per-selection toggle, "Drop" or "Climb down", decides how the reach field handles drops of 3" or more. Switching it recomputes the movement area. Default: Drop. |
| Models on slopes | The visual model and its base tilt to sit flush on the surface under them. For line of sight the rules cylinder tilts the same way (core works out the tilt, the view draws it). For movement, support, the melee zone and headroom the cylinder stays vertical. |
| Undo | Every command can be undone, back to the start of the game, by restoring a snapshot of the full state including the dice state. Take-backs are agreed between players, not policed. Online play will need both players to accept an undo. |
| Manual override | A way to set markers or move a model by hand must exist, so games are playable before every rule is automated. |
| Maps | Imported from Tabletop Simulator saves where possible, with collision blocked out by hand. A map editor comes later. |
| Warband builder | Built in, later. Modelled on Trench Companion. |

## Open questions

- Cover mechanics (deferred).
- Table size and whether it varies per scenario.
- Order of the blood and blessing prompts when both players can spend on one roll.
- Going down: climbing down and jumping down from a height.
