use std::env;
use std::fs;
use std::path::Path;

use cold_clear::evaluation::{Evaluator, Standard};
use libtetris::{
    Board, FallingPiece, LockResult, Piece, PieceState, PlacementKind, RotationState, TspinStatus,
};
use replay_analysis::{
    make_board, rank_current_moves, recommend_plan, AnalysisState, PlanStep, RankedMove,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const VISIBLE_ROWS: usize = 20;
const BOARD_COLS: usize = 10;
const DEFAULT_TOP_MOVES: usize = 3;
const DEFAULT_PLAN_STEPS: usize = 6;
const DEFAULT_PLAN_NODES: u32 = 8_000;

#[derive(Debug, Deserialize)]
struct Session {
    #[serde(default)]
    session_id: String,
    #[serde(default)]
    snapshots: Vec<Value>,
}

#[derive(Debug, Serialize)]
struct Output {
    session_id: String,
    ai_model_used: String,
    score_method: String,
    recommendation_method: String,
    plan_steps_requested: usize,
    plan_nodes: u32,
    ai_scores: Vec<i32>,
    ai_details: Vec<Value>,
    recommendations: Vec<Value>,
    total_steps: usize,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: analyze_session <session_json> <output_json> [--top N]");
        std::process::exit(2);
    }

    let session_path = &args[1];
    let output_path = &args[2];
    let top_moves = parse_top_moves(&args[3..]).unwrap_or(DEFAULT_TOP_MOVES);

    let session_text = fs::read_to_string(session_path)?;
    let session: Session = serde_json::from_str(&session_text)?;
    let weights = Standard::default();

    let mut previous_board: Option<Vec<Vec<bool>>> = None;
    let mut previous_score: Option<i32> = None;
    let mut scores = Vec::with_capacity(session.snapshots.len());
    let mut details = Vec::with_capacity(session.snapshots.len());
    let mut recommendations = Vec::with_capacity(session.snapshots.len());

    for (index, snap) in session.snapshots.iter().enumerate() {
        let board_before = previous_board.clone().unwrap_or_else(empty_visible_board);
        let current_piece = piece_from_snapshot(snap);
        let mut state = build_state(&board_before, snap, current_piece);

        let actual = current_piece.and_then(|piece| falling_piece_from_snapshot(snap, piece));
        let ranked = rank_current_moves(&state, previous_score, &weights);

        let actual_ranked = actual.and_then(|placement| {
            ranked
                .iter()
                .find(|mv| mv.placement.same_location(&placement))
                .cloned()
        });

        let direct = if actual_ranked.is_none() {
            actual.and_then(|placement| {
                direct_score(&state, snap, placement, previous_score, &weights)
            })
        } else {
            None
        };

        let best = ranked.first();
        let best_score = best.map(|mv| mv.score.score).unwrap_or(0);
        let actual_score = actual_ranked
            .as_ref()
            .map(|mv| mv.score.score)
            .or_else(|| direct.as_ref().map(|(score, _)| score.score))
            .unwrap_or(best_score);

        let score_loss = best_score - actual_score;
        let rank = actual_ranked.as_ref().map(|mv| mv.rank);
        let quality = if actual_ranked.is_none() && direct.is_none() {
            "unknown"
        } else {
            quality_label(score_loss, rank)
        };

        scores.push(actual_score);

        let actual_lock = actual_ranked
            .as_ref()
            .map(|mv| lock_json(&mv.score.lock))
            .or_else(|| direct.as_ref().map(|(_, lock)| lock_json(lock)));

        details.push(json!({
            "step": index,
            "score": actual_score,
            "delta_from_previous": previous_score.map(|prev| actual_score - prev),
            "rank": rank,
            "legal_moves": ranked.len(),
            "best_score": best_score,
            "score_loss": score_loss,
            "quality": quality,
            "actual": actual.map(placement_json),
            "actual_lock": actual_lock,
            "best": best.map(ranked_move_json),
        }));

        recommendations.push(json!({
            "step": index,
            "method": "cold-clear-search-visible-queue",
            "uses_visible_queue_only": true,
            "known_queue": state.next.iter().map(|piece| piece.to_char().to_string()).collect::<Vec<_>>(),
            "plan": recommend_plan(
                &state,
                Standard::default(),
                DEFAULT_PLAN_NODES,
                0,
                DEFAULT_PLAN_STEPS,
            )
            .map(recommendation_json),
            "top_moves": ranked.iter().take(top_moves).map(ranked_move_json).collect::<Vec<_>>(),
        }));

        previous_score = Some(actual_score);
        previous_board = board_after_clear(snap);

        // If the snapshot did not include enough queue information for hold search, keep future
        // steps alive by still moving to the next reconstructed board.
        state.next.clear();
    }

    let output = Output {
        session_id: if session.session_id.is_empty() {
            Path::new(session_path)
                .file_stem()
                .and_then(|v| v.to_str())
                .unwrap_or("unknown")
                .to_owned()
        } else {
            session.session_id
        },
        ai_model_used: "cold-clear-standard".to_owned(),
        score_method: "single-step-cold-clear-standard-evaluation".to_owned(),
        recommendation_method: "cold-clear-search-visible-queue".to_owned(),
        plan_steps_requested: DEFAULT_PLAN_STEPS,
        plan_nodes: DEFAULT_PLAN_NODES,
        ai_scores: scores,
        ai_details: details,
        recommendations,
        total_steps: session.snapshots.len(),
    };

    let rendered = serde_json::to_string_pretty(&output)?;
    fs::write(output_path, rendered)?;
    println!("Analysis complete: {} steps", output.total_steps);
    println!("Result saved: {}", output_path);
    Ok(())
}

fn parse_top_moves(args: &[String]) -> Option<usize> {
    args.windows(2)
        .find(|pair| pair[0] == "--top")
        .and_then(|pair| pair[1].parse::<usize>().ok())
}

fn build_state(
    board_before: &[Vec<bool>],
    snap: &Value,
    current_piece: Option<Piece>,
) -> AnalysisState {
    let mut state = AnalysisState::default();
    state.field = visible_to_cold_field(board_before);
    state.combo = snap
        .get("combo")
        .and_then(Value::as_i64)
        .map(|v| v.max(0) as u32)
        .unwrap_or(0);
    state.b2b = snap
        .get("b2b")
        .and_then(Value::as_i64)
        .map(|v| v > 0)
        .unwrap_or(false);
    state.hold = snap
        .get("hold_piece")
        .and_then(Value::as_str)
        .and_then(parse_piece);
    if let Some(piece) = current_piece {
        state.next.push(piece);
    }
    if let Some(next) = snap.get("next_pieces").and_then(Value::as_array) {
        for item in next
            .iter()
            .filter_map(Value::as_str)
            .filter_map(parse_piece)
        {
            state.next.push(item);
        }
    }
    state
}

fn direct_score(
    state: &AnalysisState,
    snap: &Value,
    placement: FallingPiece,
    previous_score: Option<i32>,
    weights: &Standard,
) -> Option<(replay_analysis::PlacementScore, LockResult)> {
    if !placement
        .cells()
        .iter()
        .all(|&(x, y)| (0..10).contains(&x) && (0..40).contains(&y))
    {
        return None;
    }

    let mut board: Board = make_board(state);
    let mut placement = placement;
    if snap
        .get("is_t_spin")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        placement.tspin = TspinStatus::Full;
    }
    let lock = board.lock_piece(placement);
    if lock.locked_out {
        return None;
    }
    let move_time = snap
        .get("key_presses_this_piece")
        .and_then(Value::as_u64)
        .unwrap_or(0) as u32;
    let (value, reward) = weights.evaluate(&lock, &board, move_time, placement.kind.0);
    let score = value.value() + reward.value();
    let placement_score = replay_analysis::PlacementScore {
        score,
        delta_from_previous: previous_score.map(|prev| score - prev),
        board_value: value.value(),
        attack_value: reward.value(),
        spike: value.spike(),
        garbage_sent: lock.garbage_sent,
        placement_kind: lock.placement_kind,
        lock: lock.clone(),
    };
    Some((placement_score, lock))
}

fn piece_from_snapshot(snap: &Value) -> Option<Piece> {
    snap.get("piece_type")
        .and_then(Value::as_str)
        .and_then(parse_piece)
}

fn parse_piece(name: &str) -> Option<Piece> {
    match name {
        "I" => Some(Piece::I),
        "O" => Some(Piece::O),
        "T" => Some(Piece::T),
        "S" => Some(Piece::S),
        "Z" => Some(Piece::Z),
        "J" => Some(Piece::J),
        "L" => Some(Piece::L),
        _ => None,
    }
}

fn falling_piece_from_snapshot(snap: &Value, piece: Piece) -> Option<FallingPiece> {
    let col = snap.get("col")?.as_i64()? as i32;
    let godot_row = snap.get("row")?.as_i64()? as i32;
    let rotation = match snap
        .get("rotation")
        .and_then(Value::as_i64)
        .unwrap_or(0)
        .rem_euclid(4)
    {
        0 => RotationState::North,
        1 => RotationState::East,
        2 => RotationState::South,
        _ => RotationState::West,
    };
    Some(FallingPiece {
        kind: PieceState(piece, rotation),
        x: col,
        y: 39 - godot_row,
        tspin: if snap
            .get("is_t_spin")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            TspinStatus::Full
        } else {
            TspinStatus::None
        },
    })
}

fn board_after_clear(snap: &Value) -> Option<Vec<Vec<bool>>> {
    let board = snap
        .get("board_state_after_clear")
        .or_else(|| snap.get("board_state"))
        .and_then(Value::as_array)?;
    Some(json_board_to_bool(board))
}

fn json_board_to_bool(rows: &[Value]) -> Vec<Vec<bool>> {
    rows.iter()
        .take(VISIBLE_ROWS)
        .map(|row| {
            row.as_array()
                .map(|cols| {
                    cols.iter()
                        .take(BOARD_COLS)
                        .map(|cell| cell.as_i64().unwrap_or(0) != 0)
                        .collect::<Vec<_>>()
                })
                .unwrap_or_else(|| vec![false; BOARD_COLS])
        })
        .collect()
}

fn empty_visible_board() -> Vec<Vec<bool>> {
    vec![vec![false; BOARD_COLS]; VISIBLE_ROWS]
}

fn visible_to_cold_field(visible: &[Vec<bool>]) -> [[bool; 10]; 40] {
    let mut field = [[false; 10]; 40];
    for (visible_row, row) in visible.iter().take(VISIBLE_ROWS).enumerate() {
        let y = VISIBLE_ROWS - 1 - visible_row;
        for (x, occupied) in row.iter().take(BOARD_COLS).enumerate() {
            field[y][x] = *occupied;
        }
    }
    field
}

fn quality_label(score_loss: i32, rank: Option<usize>) -> &'static str {
    if rank == Some(1) || score_loss <= 0 {
        "best"
    } else if score_loss <= 120 {
        "good"
    } else if score_loss <= 320 {
        "ok"
    } else if score_loss <= 700 {
        "mistake"
    } else {
        "blunder"
    }
}

fn ranked_move_json(mv: &RankedMove) -> Value {
    json!({
        "rank": mv.rank,
        "used_hold": mv.used_hold,
        "move_time": mv.move_time,
        "placement": placement_json(mv.placement),
        "score": mv.score.score,
        "board_value": mv.score.board_value,
        "attack_value": mv.score.attack_value,
        "spike": mv.score.spike,
        "garbage_sent": mv.score.garbage_sent,
        "placement_kind": placement_kind_name(mv.score.placement_kind),
        "lock": lock_json(&mv.score.lock),
    })
}

fn recommendation_json(recommendation: replay_analysis::Recommendation) -> Value {
    json!({
        "searched_nodes": recommendation.searched_nodes,
        "depth": recommendation.depth,
        "steps": recommendation.steps.iter().enumerate().map(|(index, step)| {
            plan_step_json(index, step)
        }).collect::<Vec<_>>(),
    })
}

fn plan_step_json(index: usize, step: &PlanStep) -> Value {
    json!({
        "step": index,
        "used_hold": step.mv.hold,
        "input_count": step.mv.inputs.len(),
        "inputs": step.mv.inputs.iter().map(|input| format!("{:?}", input)).collect::<Vec<_>>(),
        "placement": placement_json(step.mv.expected_location),
        "lock": step.lock.as_ref().map(lock_json),
    })
}

fn placement_json(placement: FallingPiece) -> Value {
    json!({
        "piece": placement.kind.0.to_char().to_string(),
        "x": placement.x,
        "y": placement.y,
        "col": placement.x,
        "row": 39 - placement.y,
        "visible_row": 19 - placement.y,
        "rotation": rotation_index(placement.kind.1),
        "tspin": format!("{:?}", placement.tspin),
    })
}

fn lock_json(lock: &LockResult) -> Value {
    json!({
        "placement_kind": placement_kind_name(lock.placement_kind),
        "locked_out": lock.locked_out,
        "b2b": lock.b2b,
        "perfect_clear": lock.perfect_clear,
        "combo": lock.combo,
        "garbage_sent": lock.garbage_sent,
        "cleared_lines": lock.cleared_lines.iter().copied().collect::<Vec<_>>(),
    })
}

fn rotation_index(rotation: RotationState) -> i32 {
    match rotation {
        RotationState::North => 0,
        RotationState::East => 1,
        RotationState::South => 2,
        RotationState::West => 3,
    }
}

fn placement_kind_name(kind: PlacementKind) -> &'static str {
    kind.name()
}
