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

// Option struct for multiple-choice questions
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
pub struct Puzzle {
    pub id: u32,
    pub title: felt252,
    pub description: felt252,
    pub version: u32,
    pub difficulty_level: u8,
    pub total_points: u32,
    // Time limit in seconds (0 for no limit)
    pub time_limit: u32,
    pub creator: ContractAddress,
    pub creation_timestamp: u64,
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
