# 008c: Charge planning on demand

## Goal

Entering charge mode takes 2 to 3 s per charger because core works out a full route
to every enemy in range up front, including a long search for enemies no D6 can
reach. None of that is needed to declare a charge. Make charge planning cheap:
only the declaration check up front, and a route only for the target the player is
looking at.

The charge rules do not change. `docs/rules/movement.md` ("Charge") and the
rulings of brief 008b stay as they are.

## Rulings for this brief

1. **Declaring needs only two checks:** the enemy is visible and within 12" edge to
   edge. That is all charge mode computes when it opens, for every enemy. No route,
   no reach field.
2. **A route is worked out for one target at a time:** when the player hovers it
   (for the preview and label) and when the charge is declared. Results are cached
   per charger, target, route choice and game state, so hovering back and forth
   costs nothing.
3. **The route is a search to that one target,** not a reach field over the whole
   area: the shortest path to base contact (or, by 008b ruling 6, to the closest
   stoppable position), with the route choice and Drop / Climb down mode. Use a
   goal-directed search (A* or similar with a straight-line distance estimate) on
   the existing height field and transitions, so it stops as soon as it gets there.
   It must share the legality and transition code with the reach field, not copy it.
4. **No distance limit on the search beyond the table.** The 18" cap from 008b is
   dropped: since only one target is searched, there is no need for it.
5. **Interposing** is checked along that route as before; if another enemy replaces
   the target, the search is run again to it.
6. **Labels:** in charge mode every enemy in range shows only whether it can be
   declared ("can charge" / "not visible"). The hovered one also shows the result of
   its route: "certain", "needs 4+", "needs 2+, 1 risky roll", "cannot reach", or the
   interposing model.
7. **The pending move after the roll** uses the same route; nothing is searched
   again.

## Build

- Core: the declaration check (ruling 1) as a cheap query, and the single-target
  route search (rulings 3 to 5), replacing the up-front per-charger planning.
  Whatever is no longer used (the long-range search, per-charger reach field for
  charges) is removed.
- Game: labels per ruling 6; the route for the hovered target is computed on a
  worker thread as now, with the label showing "…" until it is ready.
- Benchmark: add the declaration check and the single-target search to the
  benchmark tool.

## Speed targets

- Opening charge mode: under 20 ms for any charger on the test table.
- One target's route: under 100 ms typical, under 300 ms worst, on the test table.

Report the figures. If a target is not met, say why.

## Tests

- Declaration: visible and within 12" can be declared; not visible or beyond 12"
  cannot; no route is computed for this (a test that fails if it is).
- Single-target routes give the same path length and needed D6 as the 008b
  planning on every charge test case that already exists (keep those tests, now
  run on the new search).
- A target far beyond any D6 still gets a route and "cannot reach"; the failed
  charge moves along it and stops outside every zone.
- Interposing replaces the target and re-routes.
- Cache: hovering the same target twice searches once; a change of game state
  (undo, another model moved) searches again.
- All existing tests still pass.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (capture tooling, real mouse clicks): charge mode opening
  with "can charge" labels; hovering a near, a far and an interposed target;
  a declared charge succeeding and one failing.
- The speed figures are in your report.
- `core/` has no scene-tree access and no physics queries, the only random calls are
  in the dice service, and the roll resolver names no specific rule.

## Out of scope

Any change to the charge rules, the reach field for Move and Dash, attacks.
