use starknet::ContractAddress;
// QuestionType enum to support different question types
//#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde, starknet::Store)]
pub enum QuestionType {
    #[default]
    Logical: (),
    CauseEffect: (),
    Scientific: (),
}

// Option pub  for multiple-choice questions
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct options {
    pub id: u32,
    pub content: felt252,
    pub is_correct: bool,
}

// Question struct to represent a single question within a puzzle
#[derive(Drop, Serde, starknet::Store)]
pub struct Question {
    pub id: u32,
    pub content: felt252,
    pub question_type: QuestionType,
    // Additional metadata fields can be added as needed
    pub difficulty: u8,
    pub points: u32,
}

// Puzzle struct to represent a complete puzzle
#[derive(Drop, Serde, PartialEq, starknet::Store, Clone)]
struct Puzzle {
    id: u32,
    title: felt252,
    description: felt252,
    version: u32,
    difficulty_level: u8,
    total_points: u32,
    time_limit: u32,
    creator: ContractAddress,
    creation_timestamp: u64,
    status: PuzzleStatus, // New field
    moderator: ContractAddress, // New field for approver
    approval_timestamp: u64 // New field for approval time
}
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct PlayerAttempt {
    pub attempt_count: u32,
    pub last_attempt_timestamp: u64,
    pub last_reward_amount: u256,
    pub total_rewards_earned: u256,
    pub best_score: u32,
    pub best_time: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct RewardParameters {
    pub base_reward: u256,
    pub time_bonus_factor: u256,
    pub difficulty_multiplier: u256,
    pub perfect_score_bonus: u256,
    pub max_reward_cap: u256,
    pub cooldown_period: u64,
    pub reward_decay_factor: u256,
}


// GameMode enum to define different game modes
#[derive(Drop, Copy, Serde, starknet::Store)]
pub enum GameModeType {
    #[default]
    Practice: (),
    Challenge: (),
    TimeAttack: (),
}

// Game Mode struct to represent a game mode configuration
#[derive(Drop, Serde, starknet::Store)]
pub struct GameMode {
    pub id: u32,
    pub name: felt252,
    pub mode_type: GameModeType,
    pub reward_multiplier: u32, // Base 100, e.g., 150 means 1.5x rewards
    pub time_modifier: u32, // Percentage modification to time limits (100 = no change)
    pub points_threshold: u32, // Minimum points needed for rewards
    pub enabled: bool,
    pub creation_timestamp: u64,
}

// User progress in game modes
#[derive(Drop, Serde, starknet::Store)]
pub struct UserGameModeProgress {
    pub user: ContractAddress,
    pub mode_id: u32,
    pub completed_puzzles: u32,
    pub total_points: u32,
    pub highest_difficulty_completed: u8,
    pub last_played_timestamp: u64,
}

// Player Profile struct to represent a player's profile and progress
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct PlayerProfile {
    pub player_id: u32,
    pub address: ContractAddress,
    pub username: felt252,
    pub level: u32,
    pub total_score: u32,
    pub puzzles_solved: u32,
    pub total_time_spent: u64,
    pub streak_days: u32,
    pub last_active_timestamp: u64,
    pub creation_timestamp: u64,
}

// Puzzle Statistics for a player
#[derive(Drop, Serde, starknet::Store)]
pub struct PuzzleStats {
    pub puzzle_id: u32,
    pub player: ContractAddress,
    pub attempts: u32,
    pub best_score: u32,
    pub best_time: u64,
    pub last_completion_timestamp: u64,
}

// Level Unlock struct to track level unlocking requirements and status
#[derive(Drop, Serde, starknet::Store)]
pub struct LevelUnlock {
    pub level_id: u32,
    pub name: felt252,
    pub description: felt252,
    pub achievement_requirement: u32, // 0 if no achievement required
    pub token_requirement: u256, // 0 if no tokens required
    pub prerequisite_level: u32, // 0 if no prerequisite
    pub creation_timestamp: u64,
}

// Achievement struct for game mode-specific achievements
#[derive(Drop, Serde, starknet::Store)]
pub struct GameModeAchievement {
    pub id: u32,
    pub mode_id: u32,
    pub name: felt252,
    pub description: felt252,
    pub condition_type: u8, // 1=puzzles completed, 2=points earned, 3=difficulty reached
    pub condition_value: u32,
    pub reward_points: u32,
}
