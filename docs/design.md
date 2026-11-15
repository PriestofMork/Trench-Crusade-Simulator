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

**`game/` (presentation)**
- 3D table, camera, selection, movement preview, dice tray, prompts.
- Reads core state, sends commands, plays back the events core emits.

## Decisions so far

| Topic | Decision |
|---|---|
| Model shape for rules | Every model is a cylinder defined by its base diameter and a height. The visual mesh is never used for rules. |
| Cylinder height | One fixed height per base size, from a single tunable table (values in `docs/rules/line-of-sight.md`). |
| Models and sight | Other models block line of sight, friendly and enemy alike. |
| Line of sight | Any point of the attacker's cylinder to any point of the target's cylinder, against simplified terrain volumes. Cover is deferred. See `docs/rules/line-of-sight.md`. |
| Terrain collision | Hand-blocked simple shapes (boxes, ramps), separate from the visual mesh. Used for both movement and line of sight. |
| Movement | Free, not grid-based. Select a model, see reachable distance, click to move. |
| Blood markers | When a roll is made, the opponent is prompted whether to spend blood markers on it. |
| Blessing markers | The rolling player is prompted whether to spend blessing markers, if they have any. |
| Modifiers | Weapon and situational modifiers are applied automatically and shown in the roll breakdown. |
| Manual override | A way to set markers or move a model by hand must exist, so games are playable before every rule is automated. |
| Maps | Imported from Tabletop Simulator saves where possible, with collision blocked out by hand. A map editor comes later. |
| Warband builder | Built in, later. Modelled on Trench Companion. |

## Open questions

- Cover mechanics (deferred).
- Table size and whether it varies per scenario.
- Order of the blood and blessing prompts when both players can spend on one roll.
- Vertical movement: climbing, jumping and falling.
