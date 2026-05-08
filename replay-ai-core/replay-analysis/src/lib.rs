use cold_clear::evaluation::{Evaluator, Standard};
use cold_clear::{BotState, Options};
use enumset::EnumSet;
use libtetris::{
    find_moves, Board, FallingPiece, LockResult, Move, MovementMode, Piece, PlacementKind,
    SpawnRule,
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug)]
pub struct AnalysisState {
    pub field: [[bool; 10]; 40],
    pub next: Vec<Piece>,
    pub hold: Option<Piece>,
    pub bag_remain: EnumSet<Piece>,
    pub b2b: bool,
    pub combo: u32,
    pub movement_mode: MovementMode,
    pub spawn_rule: SpawnRule,
    pub use_hold: bool,
}

impl Default for AnalysisState {
    fn default() -> Self {
        Self {
            field: [[false; 10]; 40],
            next: Vec::new(),
            hold: None,
            bag_remain: EnumSet::all(),
            b2b: false,
            combo: 0,
            movement_mode: MovementMode::ZeroG,
            spawn_rule: SpawnRule::Row19Or20,
            use_hold: true,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PlayedMove {
    pub placement: FallingPiece,
    pub used_hold: bool,
    pub move_time: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PlacementScore {
    pub score: i32,
    pub delta_from_previous: Option<i32>,
    pub board_value: i32,
    pub attack_value: i32,
    pub spike: i32,
    pub garbage_sent: u32,
    pub placement_kind: PlacementKind,
    pub lock: LockResult,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RankedMove {
    pub placement: FallingPiece,
    pub used_hold: bool,
    pub move_time: u32,
    pub rank: usize,
    pub score: PlacementScore,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PlanStep {
    pub mv: Move,
    pub lock: Option<LockResult>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Recommendation {
    pub steps: Vec<PlanStep>,
    pub searched_nodes: u32,
    pub depth: u32,
}

pub fn make_board(state: &AnalysisState) -> Board {
    let mut board = Board::new_with_state(
        state.field,
        state.bag_remain,
        state.hold,
        state.b2b,
        state.combo,
    );
    for &piece in &state.next {
        board.add_next_piece(piece);
    }
    board
}

pub fn score_placement(
    state: &AnalysisState,
    played: PlayedMove,
    previous_score: Option<i32>,
    weights: &Standard,
) -> Option<PlacementScore> {
    let mut board = make_board(state);
    apply_queue_and_hold(&mut board, played.placement, played.used_hold)?;
    let lock = board.lock_piece(played.placement);
    if lock.locked_out {
        return None;
    }

    let (value, reward) =
        weights.evaluate(&lock, &board, played.move_time, played.placement.kind.0);
    let score = value.value() + reward.value();

    Some(PlacementScore {
        score,
        delta_from_previous: previous_score.map(|prev| score - prev),
        board_value: value.value(),
        attack_value: reward.value(),
        spike: value.spike(),
        garbage_sent: lock.garbage_sent,
        placement_kind: lock.placement_kind,
        lock,
    })
}

pub fn rank_current_moves(
    state: &AnalysisState,
    previous_score: Option<i32>,
    weights: &Standard,
) -> Vec<RankedMove> {
    let board = make_board(state);
    let mut moves = Vec::new();
    if let Some(next) = board.get_next_piece().ok() {
        let mut play_board = board.clone();
        play_board.advance_queue();
        add_ranked_moves(
            &mut moves,
            &play_board,
            next,
            false,
            state.movement_mode,
            state.spawn_rule,
            previous_score,
            weights,
        );
    }

    if state.use_hold {
        let mut hold_board = board.clone();
        if let Some(next) = hold_board.advance_queue() {
            let hold_piece = hold_board
                .hold(next)
                .unwrap_or_else(|| hold_board.advance_queue().unwrap());
            add_ranked_moves(
                &mut moves,
                &hold_board,
                hold_piece,
                true,
                state.movement_mode,
                state.spawn_rule,
                previous_score,
                weights,
            );
        }
    }

    moves.sort_by(|a, b| b.score.score.cmp(&a.score.score));
    for (rank, mv) in moves.iter_mut().enumerate() {
        mv.rank = rank + 1;
    }
    moves
}

pub fn recommend_plan(
    state: &AnalysisState,
    weights: Standard,
    think_nodes: u32,
    incoming_garbage: u32,
    max_steps: usize,
) -> Option<Recommendation> {
    let mut options = Options::default();
    options.mode = state.movement_mode;
    options.spawn_rule = state.spawn_rule;
    options.use_hold = state.use_hold;
    options.speculate = false;
    options.min_nodes = think_nodes;
    options.max_nodes = think_nodes;
    options.threads = 1;
    options.pcloop = None;

    let mut bot = BotState::new(make_board(state), options);
    for _ in 0..think_nodes {
        match bot.think() {
            Ok(thinker) => {
                let result = thinker.think(&weights);
                bot.finish_thinking(result);
            }
            Err(_) => break,
        }
    }

    let (mv, info) = bot.suggest_move(&weights, None, incoming_garbage)?;
    let mut board = make_board(state);
    let mut steps = Vec::new();
    let plan = info.plan();
    for (index, (placement, lock)) in plan.iter().take(max_steps).enumerate() {
        let hold = consume_piece_for_plan(&mut board, *placement, state.use_hold).unwrap_or(false);
        let inputs = if index == 0 && placement.same_location(&mv.expected_location) {
            mv.inputs.clone()
        } else {
            Default::default()
        };
        steps.push(PlanStep {
            mv: Move {
                inputs,
                expected_location: *placement,
                hold,
            },
            lock: Some(lock.clone()),
        });
        let _ = board.lock_piece(*placement);
    }

    if steps.is_empty() {
        steps.push(PlanStep { mv, lock: None });
    }

    let (searched_nodes, depth) = match info {
        cold_clear::Info::Normal(info) => (info.nodes, info.depth),
        cold_clear::Info::PcLoop(info) => (0, info.depth),
        cold_clear::Info::Book => (0, 0),
    };

    Some(Recommendation {
        steps,
        searched_nodes,
        depth,
    })
}

fn consume_piece_for_plan(
    board: &mut Board,
    placement: FallingPiece,
    use_hold: bool,
) -> Option<bool> {
    let next = board.advance_queue()?;
    if next == placement.kind.0 {
        return Some(false);
    }
    if !use_hold {
        return None;
    }
    let held = board
        .hold(next)
        .unwrap_or_else(|| board.advance_queue().unwrap());
    if held == placement.kind.0 {
        Some(true)
    } else {
        None
    }
}

fn apply_queue_and_hold(board: &mut Board, placement: FallingPiece, used_hold: bool) -> Option<()> {
    let next = board.advance_queue()?;
    if used_hold {
        let held = board
            .hold(next)
            .unwrap_or_else(|| board.advance_queue().unwrap());
        if held != placement.kind.0 {
            return None;
        }
    } else if next != placement.kind.0 {
        return None;
    }
    Some(())
}

fn add_ranked_moves(
    moves: &mut Vec<RankedMove>,
    board: &Board,
    piece_to_place: Piece,
    used_hold: bool,
    movement_mode: MovementMode,
    spawn_rule: SpawnRule,
    previous_score: Option<i32>,
    weights: &Standard,
) {
    let spawned = match spawn_rule.spawn(piece_to_place, board) {
        Some(spawned) => spawned,
        None => return,
    };

    for placement in find_moves(board, spawned, movement_mode) {
        let mut result = board.clone();
        let lock = result.lock_piece(placement.location);
        let can_be_hd = board.above_stack(&placement.location)
            && board.column_heights().iter().all(|&y| y < 18);
        if lock.locked_out || can_be_hd && lock.placement_kind == PlacementKind::MiniTspin {
            continue;
        }

        let move_time = placement.inputs.time + u32::from(used_hold);
        let (value, reward) = weights.evaluate(&lock, &result, move_time, piece_to_place);
        let score = value.value() + reward.value();
        moves.push(RankedMove {
            placement: placement.location,
            used_hold,
            move_time,
            rank: 0,
            score: PlacementScore {
                score,
                delta_from_previous: previous_score.map(|prev| score - prev),
                board_value: value.value(),
                attack_value: reward.value(),
                spike: value.spike(),
                garbage_sent: lock.garbage_sent,
                placement_kind: lock.placement_kind,
                lock,
            },
        });
    }
}
