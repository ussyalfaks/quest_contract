use quest_contract::base::types::{Puzzle, Question, QuestionType, options};
use starknet::ContractAddress;
// Interface trait

#[starknet::interface]
pub trait ILogicQuestPuzzle<TContractState> {
    // Admin functions
    fn authorize_creator(ref self: TContractState, creator_address: ContractAddress);
    fn revoke_creator(ref self: TContractState, creator_address: ContractAddress);
    fn update_contract_version(ref self: TContractState, new_version: u32);

    // Creator functions
    fn create_puzzle(
        ref self: TContractState,
        title: felt252,
        description: felt252,
        difficulty_level: u8,
        time_limit: u32,
    ) -> u32;

    fn add_question(
        ref self: TContractState,
        puzzle_id: u32,
        content: felt252,
        question_type: QuestionType,
        difficulty: u8,
        points: u32,
    ) -> u32;

    fn add_option(
        ref self: TContractState,
        puzzle_id: u32,
        question_id: u32,
        content: felt252,
        is_correct: bool,
    ) -> u32;

    // // Query functions
    fn get_puzzle(self: @TContractState, puzzle_id: u32) -> Puzzle;
    fn get_question(self: @TContractState, puzzle_id: u32, question_id: u32) -> Question;
    fn get_option(
        self: @TContractState, puzzle_id: u32, question_id: u32, option_id: u32,
    ) -> options;
    fn get_puzzle_questions_count(self: @TContractState, puzzle_id: u32) -> u32;
    fn get_question_options_count(self: @TContractState, puzzle_id: u32, question_id: u32) -> u32;
    fn get_total_puzzles(self: @TContractState) -> u32;
    fn get_contract_version(self: @TContractState) -> u32;
    fn is_authorized_creator(self: @TContractState, address: ContractAddress) -> bool;
}
