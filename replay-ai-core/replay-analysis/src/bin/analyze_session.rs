use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::io::{self, Read, Write};
use std::time::{Duration, Instant};

use cold_clear::evaluation::{Evaluator, Standard};
use libtetris::{
    Board, FallingPiece, LockResult, Piece, PieceState, PlacementKind, RotationState, TspinStatus,
};
use replay_analysis::{
    make_board, rank_current_moves, recommend_plan, AnalysisState, PlanStep, RankedMove,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const STORAGE_PROTOCOL: &str = "TETRIS_STORAGE_V1";
const MAX_INPUT_BYTES: u64 = 1_000_000_000;
const MAX_OUTPUT_BYTES: u64 = 64_000_000;
const MAX_SNAPSHOTS: usize = 10_000;
const MAX_SECONDS: u64 = 120;

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
    storage_protocol: u32,
    analysis_revision: u32,
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
    if args.len() == 2 && args[1] == "--storage-protocol" {
        println!("{}", STORAGE_PROTOCOL);
        return Ok(());
    }
    if args.len() < 3 {
        eprintln!("Usage: analyze_session <session_json> <output_json> [--top N]");
        std::process::exit(2);
    }

    let session_path = &args[1];
    let output_path = &args[2];
    let top_moves = parse_top_moves(&args[3..]).unwrap_or(DEFAULT_TOP_MOVES).min(DEFAULT_TOP_MOVES);
    let budget_root = required_option(&args[3..], "--budget-root")?;
    let reservation = required_option(&args[3..], "--reservation")?;
    let parent_pid: u32 = required_option(&args[3..], "--parent-pid")?.parse()?;
    let output_limit = validate_reservation(&budget_root, &reservation, output_path, parent_pid)?;
    start_parent_watchdog(parent_pid);
    let canonical_root = fs::canonicalize(&budget_root)?;
    if !fs::canonicalize(session_path)?.starts_with(&canonical_root) {
        return Err("input is outside the reserved game data directory".into());
    }
    let session_text = read_limited(Path::new(session_path), MAX_INPUT_BYTES)?;
    let session: Session = serde_json::from_slice(&session_text)?;
    let total_steps = session.snapshots.len();
    if total_steps > MAX_SNAPSHOTS {
        return Err("session exceeds the 10000-snapshot analysis limit".into());
    }
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
        // No progress sidecar: every file output must have reserved capacity.
    }

    let output = Output {
        storage_protocol: 1,
        analysis_revision: 2,
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
        total_steps,
    };

    // create_new prevents accidental replacement of any existing replay/output.
    // Count before each write, including buffered output: the cap cannot overshoot.
    let file = fs::OpenOptions::new().write(true).create_new(true).open(output_path)?;
    let mut writer = LimitedWriter { inner: io::BufWriter::new(file), written: 0, limit: output_limit };
    serde_json::to_writer_pretty(&mut writer, &output)?;
    writer.flush()?;
    writer.inner.get_ref().sync_all()?;
    println!("Analysis complete: {} steps", output.total_steps);
    println!("Result saved: {}", output_path);
    Ok(())
}

fn parse_top_moves(args: &[String]) -> Option<usize> {
    args.windows(2)
        .find(|pair| pair[0] == "--top")
        .and_then(|pair| pair[1].parse::<usize>().ok())
}

fn parse_option_value(args: &[String], option: &str) -> Option<String> {
    args.windows(2)
        .find(|pair| pair[0] == option)
        .map(|pair| pair[1].clone())
}

fn required_option(args: &[String], name: &str) -> Result<String, io::Error> {
    parse_option_value(args, name).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, format!("missing {}", name)))
}

fn read_limited(path: &Path, limit: u64) -> io::Result<Vec<u8>> {
    let file = fs::File::open(path)?;
    if file.metadata()?.len() > limit {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "input file exceeds its byte limit"));
    }
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "input file grew beyond its byte limit"));
    }
    Ok(bytes)
}

fn canonical_new_path(path: &Path) -> io::Result<PathBuf> {
    let parent = path.parent().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "output has no parent"))?;
    let name = path.file_name().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "output has no filename"))?;
    Ok(fs::canonicalize(parent)?.join(name))
}

fn validate_reservation(root: &str, token: &str, output: &str, parent_pid: u32) -> Result<u64, Box<dyn std::error::Error>> {
    if token.len() != 32 || !token.bytes().all(|b| b.is_ascii_hexdigit()) || parent_pid == 0 {
        return Err("invalid storage reservation".into());
    }
    let root = fs::canonicalize(root)?;
    let marker = root.join(".reservations").join(format!("{}.json", token));
    if !fs::canonicalize(&marker)?.starts_with(&root) {
        return Err("reservation escapes the data directory".into());
    }
    let data: Value = serde_json::from_slice(&read_limited(&marker, 2048)?)?;
    let reserved_path = data.get("path").and_then(Value::as_str).ok_or("reservation has no path")?;
    let limit = data.get("max_bytes").and_then(Value::as_u64).ok_or("reservation has no limit")?;
    let canonical_output = canonical_new_path(Path::new(output))?;
    if data.get("protocol").and_then(Value::as_u64) != Some(1)
        || data.get("parent_pid").and_then(Value::as_u64) != Some(parent_pid as u64)
        || limit == 0 || limit > MAX_OUTPUT_BYTES
        || canonical_output != canonical_new_path(Path::new(reserved_path))?
        || !canonical_output.starts_with(&root)
        || canonical_output.exists()
    {
        return Err("output does not match the granted storage reservation".into());
    }
    Ok(limit)
}

struct LimitedWriter<W: Write> { inner: W, written: u64, limit: u64 }
impl<W: Write> Write for LimitedWriter<W> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() as u64 > self.limit.saturating_sub(self.written) {
            return Err(io::Error::new(io::ErrorKind::Other, "analysis output byte limit reached"));
        }
        let count = self.inner.write(bytes)?;
        self.written += count as u64;
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> { self.inner.flush() }
}

// The analyzer never creates child processes. If Godot crashes or is killed,
// this independent watchdog stops analysis even while model code is running.
fn start_parent_watchdog(parent_pid: u32) {
    std::thread::spawn(move || {
        let started = Instant::now();
        loop {
            if started.elapsed() >= Duration::from_secs(MAX_SECONDS) || !parent_alive(parent_pid) {
                std::process::exit(124);
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    });
}

#[cfg(windows)]
fn parent_alive(pid: u32) -> bool {
    use std::ffi::c_void;
    #[link(name = "kernel32")]
    extern "system" {
        fn OpenProcess(access: u32, inherit: i32, pid: u32) -> *mut c_void;
        fn WaitForSingleObject(handle: *mut c_void, milliseconds: u32) -> u32;
        fn CloseHandle(handle: *mut c_void) -> i32;
    }
    unsafe {
        let handle = OpenProcess(0x0010_0000, 0, pid); // SYNCHRONIZE only
        if handle.is_null() { return false; }
        let alive = WaitForSingleObject(handle, 0) == 0x0000_0102; // WAIT_TIMEOUT
        CloseHandle(handle);
        alive
    }
}

#[cfg(unix)]
fn parent_alive(pid: u32) -> bool {
    extern "C" { fn kill(pid: i32, signal: i32) -> i32; }
    unsafe { kill(pid as i32, 0) == 0 }
}

#[cfg(not(any(windows, unix)))]
fn parent_alive(_pid: u32) -> bool { false }

#[cfg(test)]
mod storage_tests {
    use super::*;
    #[test]
    fn input_limit_accepts_exact_size_and_rejects_oversize() {
        let path = env::temp_dir().join(format!("tetris-input-limit-{}.json", std::process::id()));
        let mut file = fs::OpenOptions::new().write(true).create_new(true).open(&path).unwrap();
        file.write_all(b"12345").unwrap();
        drop(file);
        let exact = read_limited(&path, 5);
        let oversized = read_limited(&path, 4);
        fs::remove_file(&path).unwrap();
        assert_eq!(exact.unwrap(), b"12345");
        assert_eq!(oversized.unwrap_err().kind(), io::ErrorKind::InvalidData);
    }
    #[test]
    fn output_limit_rejects_before_writing() {
        let mut writer = LimitedWriter { inner: Vec::new(), written: 0, limit: 4 };
        writer.write_all(b"1234").unwrap();
        assert!(writer.write_all(b"5").is_err());
        assert_eq!(writer.inner, b"1234");
    }
    #[test]
    fn output_limit_rejects_an_oversized_first_chunk() {
        let mut writer = LimitedWriter { inner: Vec::new(), written: 0, limit: 4 };
        assert!(writer.write_all(b"12345").is_err());
        assert!(writer.inner.is_empty());
    }
}

#[cfg(test)]
mod coordinate_tests {
    use super::*;

    // Read the production GDScript tables so future shape changes cannot leave
    // the analyzer or replay preview silently using a second geometry system.
    const GODOT_SHAPES: &str = include_str!("../../../../scripts/core/piece_data.gd");
    const REPLAY_SHAPES: &str = include_str!("../../../../scripts/ui/replay_system.gd");

    fn table_cells(source: &str, table: &str, piece: &str, rotation: &str) -> Vec<(i32, i32)> {
        let table = source.split(table).nth(1).expect("shape table");
        let piece = table.split(piece).nth(1).expect("piece entry");
        let line = piece.lines().find(|line| line.trim_start().starts_with(rotation)).expect("rotation entry");
        line.split("Vector2(").skip(1).map(|cell| {
            let numbers = cell.split(')').next().unwrap();
            let mut values = numbers.split(',').map(|value| value.trim().parse::<i32>().unwrap());
            (values.next().unwrap(), values.next().unwrap())
        }).collect()
    }

    #[test]
    fn every_godot_orientation_preserves_occupied_cells_in_the_analyzer() {
        for name in ["I", "O", "T", "S", "Z", "J", "L"].iter() {
            for (rotation, label) in ["SPAWN", "R", "TWO", "L"].iter().enumerate() {
                let snapshot = json!({"col": 4, "row": 30, "rotation": rotation});
                let placement = falling_piece_from_snapshot(&snapshot, parse_piece(name).unwrap()).unwrap();
                let mut actual = placement.cells().iter().map(|&(x, y)| (x, 39 - y)).collect::<Vec<_>>();
                let mut expected = table_cells(GODOT_SHAPES, "const SHAPES: Dictionary = {",
                    &format!("Type.{}: {{", name), &format!("RotationState.{}:", label))
                    .into_iter().map(|(x, y)| (4 + x, 30 + y)).collect::<Vec<_>>();
                actual.sort(); expected.sort();
                assert_eq!(actual, expected, "Godot {} rotation {}", name, label);
            }
        }
    }

    #[test]
    fn every_replay_preview_orientation_matches_libtetris_cells() {
        for name in ["I", "O", "T", "S", "Z", "J", "L"].iter() {
            for (index, rotation) in [RotationState::North, RotationState::East, RotationState::South, RotationState::West].iter().enumerate() {
                let mut expected = PieceState(parse_piece(name).unwrap(), *rotation).cells()
                    .iter().map(|&(x, y)| (x, -y)).collect::<Vec<_>>();
                let mut actual = table_cells(REPLAY_SHAPES, "const CC_SHAPES: Dictionary = {",
                    &format!("\"{}\": {{", name), &format!("{}:", index));
                actual.sort(); expected.sort();
                assert_eq!(actual, expected, "replay {} rotation {}", name, index);
            }
        }
    }
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
    // Godot uses fixed bounding-box pivots for I and O. libtetris rotates all
    // pieces around an integer cell, so these orientations need a translation
    // in its upward-positive coordinates to preserve the same occupied cells.
    let (offset_x, offset_y) = match (piece, rotation) {
        (Piece::I, RotationState::East) => (1, 0),
        (Piece::I, RotationState::South) => (1, -1),
        (Piece::I, RotationState::West) => (0, -1),
        (Piece::O, RotationState::East) => (0, 1),
        (Piece::O, RotationState::South) => (1, 1),
        (Piece::O, RotationState::West) => (1, 0),
        _ => (0, 0),
    };
    Some(FallingPiece {
        kind: PieceState(piece, rotation),
        x: col + offset_x,
        y: 39 - godot_row + offset_y,
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
