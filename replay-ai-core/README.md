# Replay AI Core

This folder is a reduced Cold Clear extraction for replay analysis.

It keeps only the parts needed to:

- evaluate a played placement,
- compare the score with the previous step,
- rank all legal current placements,
- recommend a short AI plan from a board, hold piece, and next queue.

## Crates

- `libtetris`: board, pieces, movement search, locking, line clear, T-spin, combo, B2B, garbage.
- `opening-book`: required by `cold-clear`; optional for opening book suggestions.
- `bot`: Cold Clear search and evaluation logic.
- `replay-analysis`: thin API wrapper for replay analysis use.

## Main API

Use `replay_analysis::AnalysisState` as input state.

Important functions:

- `score_placement(state, played, previous_score, weights)`
- `rank_current_moves(state, previous_score, weights)`
- `recommend_plan(state, weights, think_nodes, incoming_garbage, max_steps)`

## License

This extraction includes Cold Clear code and remains under MPL-2.0.
Keep `LICENSE` with redistributed copies. If you modify MPL-covered source files and distribute
the result, provide the modified source files under MPL-2.0.
