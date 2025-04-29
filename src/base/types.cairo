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
