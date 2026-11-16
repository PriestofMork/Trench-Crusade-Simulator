# 008: Line of sight

## Goal

The game knows whether one model can see another. Models are cylinders, tilted to
sit flush on slopes; terrain and other models block. This replaces the temporary
"always yes" answer behind `GameState.rules.sight` (`core/sight/`), so charges now
need a visible target, and brief 009 can build shooting on it.

Only visibility, yes or no. Cover and height advantage are not part of this brief.

Rules reference: `docs/rules/line-of-sight.md`.

## Rulings for this brief

These fill gaps in the rules file. Follow them, and restate them in your report so
the project owner can confirm or change them.

1. **Sight cylinder:** a model's sight cylinder has its base diameter and the height
   from the base size table. Its underside sits on the floor under the model's
   centre, and its axis is the normal of that floor: upright on flat ground, tilted
   on a ramp. No cap on the tilt. Movement, support, melee and headroom keep the
   upright cylinder and are not touched.
2. **One tilt for drawing and sight:** the tilt is worked out in `core/` from the
   terrain data. The model view must use that same value, so what is drawn is what
   is tested. (Today `game/views/model_view.gd` gets a floor normal through a
   callable; make core the source.)
3. **Visible means:** some straight segment from a point of the viewer's cylinder to
   a point of the target's cylinder is not blocked. Tested with a fixed set of
   sample points on each cylinder (for example rings on the top, middle and bottom,
   plus the axis). The sample set is one tunable definition, not scattered numbers.
   This is an approximation and that is accepted; choose the set so that a target
   showing a sliver about 0.25" wide is still found.
4. **What blocks:** every terrain piece (box or ramp, as the solid described in
   `core/terrain_piece.gd`), and the sight cylinder of every model other than the
   viewer and the target, friendly or enemy. The tabletop itself blocks.
5. **See-through terrain:** terrain pieces get a `blocks_sight` flag, default true,
   readable from the table data. Nothing on the test table needs to be see-through
   except one piece added to test it.
6. **Touching is not blocking:** a segment that only grazes a surface or an edge is
   clear. Use one small tolerance, defined once. In particular the floor a model
   stands on must not hide the bottom of its own cylinder from a viewer on the same
   floor.
7. **Symmetric:** if A sees B then B sees A. The sample sets must make this true
   exactly, and a test checks it.
8. **Down models:** a Down model keeps the same sight cylinder, both for seeing,
   being seen and blocking.
9. **Out of Action models** are not on the table: they neither block nor can be seen.
10. **Interposing charges:** a model that interposes becomes the target without
    needing to be visible or within 12"; it is in the way, so it is reached. Only
    the declared target needs sight and range.

## Build

**Core: geometry**
- Segment against a box piece and against a ramp piece (both are convex solids over
  a rotated rectangle), segment against a tilted cylinder, segment against the
  tabletop. Pure functions on plain data, in `core/sight/`.

**Core: sight**
- A real implementation of the `Sight` interface, installed as the default in
  `core/ruleset.gd`. Remove the temporary one, or keep it only as a test helper.
- Besides the yes/no answer, core can return a result object for the game layer: the
  clear segment that was found (two end points), or, when blocked, nothing. Keep
  this object easy to extend, since cover will later ask how much of the target is
  visible. Do not build cover.
- A query that takes positions as plain data rather than only the models' current
  positions, so that "what would I see from there" can be asked later without
  moving anything. Only the query; no UI for it in this brief.
- Speed: one viewer against every enemy on the test table in well under a frame
  (aim for under 5 ms in total). Add it to the benchmark tool. Use a cheap bounding
  test before the exact one if needed.

**Core: charge**
- Charge declaration already asks the interface; check that an unseen enemy is not a
  legal target, with a reason the HUD can show, and apply ruling 10.

**Game**
- **Sight on hover:** with a model selected, hovering an enemy draws the clear
  segment as a thin line between the two models, or marks the enemy "not visible".
- **Sight overview:** a toggle (button and hotkey) that marks every enemy the
  selected model can see and dims the ones it cannot.
- **Charge mode:** enemies within 12" that cannot be seen are labelled "not visible"
  and cannot be chosen.
- **Debug view:** a toggle that draws the sight cylinders, tilted, so the tilt can be
  checked by eye against the drawn model.
- Results are cached per game state in the game layer, like the reach field, and
  never computed by the view itself.
- Add to the test table: a wall that hides a model; a low wall a model can be seen
  over; a model standing between two others; a model on a ramp; a model on a raised
  floor looking down; one see-through piece.

**Tests**
- Geometry: segment against box, ramp, tilted cylinder and tabletop, including
  grazing cases and segments starting on a surface.
- Open ground: two models see each other.
- A wall taller than both blocks; a wall lower than the models does not.
- A model exactly between two others blocks; moved aside by more than its radius it
  does not. Friendly and enemy blockers behave the same.
- A sliver: a target mostly behind a wall with 0.25" showing is visible.
- Tilt: a model on a ramp has a tilted cylinder; a case where the tilted cylinder is
  visible and the upright one would not be, and the reverse.
- Height: a model on a raised floor sees a model below over the floor's edge, and
  does not see one tucked directly under the edge.
- A model under a bridge and a model on top of it do not see each other through it.
- See-through piece does not block.
- Symmetry over a set of varied positions.
- Down keeps its cylinder; Out of Action neither blocks nor is seen.
- Charge: unseen target refused; interposer needs no sight (ruling 10).
- The tilt used by the view equals the tilt used by sight.
- All existing tests still pass.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots with the capture tooling, using real
  mouse clicks): the sight line on hover; a blocked enemy marked not visible; the
  overview toggle; a model hidden by another model; a model on the ramp with its
  debug cylinder matching the drawn model; a charge refused for lack of sight.
- The benchmark figure for sight is in your report.
- `core/` has no scene-tree access and no physics queries, the only random calls are
  in the dice service, and the roll resolver names no specific rule.

## Out of scope

Cover, height advantage, ranged and melee attacks, weapons, range bands, sight
preview from a planned move destination, real miniature models, map import.
