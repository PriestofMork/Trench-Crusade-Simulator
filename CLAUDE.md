# Trench Crusade Simulator

A digital, rules-enforcing version of the Trench Crusade skirmish game: XCOM-style
automation (movement, line of sight, dice, modifiers) on a free-movement 3D table.
Two human players; no AI opponent. Private fan project.

## Where things are decided

- `docs/design.md` — architecture and standing decisions. Read before any non-trivial work.
- `docs/rules/` — the rules this game implements (a simplified take on Trench Crusade).
  **This is the source of truth for rules, not the official rulebook and not your memory
  of it.** If a rule you need is missing or ambiguous, stop and say so in your report
  instead of guessing.
- `docs/tasks/` — one brief per piece of work. Implement exactly the brief you were given;
  note anything out of scope you noticed in your report rather than doing it.

## Stack

- Godot 4, standard build (not .NET). Exact version is pinned in `docs/design.md`.
- GDScript only, with static typing everywhere (`var x: int`, typed arrays, typed returns).
- Tests: GUT, vendored in `addons/gut/`.

## Layout

```
core/     rules engine: game state, commands, dice, LOS maths. No Node/scene dependencies.
game/     3D scenes, camera, input, UI. Displays core state and sends commands to it.
data/     unit, weapon and warband definitions (data files, not code)
assets/   models, textures, terrain
tools/    import and conversion scripts
tests/    GUT tests, mirroring core/
docs/     design, rules, task briefs (ignored by the Godot importer)
```

## Hard rules

1. **`core/` never touches the scene tree.** Classes there extend `RefCounted` or `Resource`,
   never `Node`. No `get_tree()`, no physics queries, no input. Geometry it needs
   (positions, base sizes, terrain volumes) is passed in as plain data.
2. **All state changes go through commands** applied to the game state in `core/`.
   `game/` never mutates state directly.
3. **All randomness goes through the single seeded dice service in `core/`.**
   Never call `randi()` or similar anywhere else.
4. **Core never waits on the UI.** When a player decision is needed mid-resolution
   (e.g. spend blood markers on this roll?), core exposes a pending decision and
   resumes when a command answers it.
5. **Units: 1 Godot unit = 1 inch.** Base sizes are stored in millimetres in data and
   converted once.
6. **Every rule implemented in `core/` gets a test.**

## Running

Godot 4.7.2 is not installed system-wide. The executables are in `Godot/` at the root of
the main checkout (gitignored, so a git worktree will not contain them; use the main
checkout's copy). Use the `_console` executable from a shell so output is captured:

```bash
./Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Run the tests before reporting a task as done, and include the result in the report.

## Repository

- The GitHub repo is **public**. Never commit third-party or copyrighted material:
  miniature models, Tabletop Simulator rips, or verbatim official rules text.
  Those live in `assets/private/`, which is gitignored.
- Commit in small steps with clear messages. Do not push unless asked.
