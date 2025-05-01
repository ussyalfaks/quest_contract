use quest_contract::base::types::{PlayerProfile, PuzzleStats};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IPlayerProfile<TContractState> {
    // Player profile management
    fn create_profile(ref self: TContractState, username: felt252) -> u32;
    fn update_profile(ref self: TContractState, username: felt252);
    fn get_profile(self: @TContractState, player: ContractAddress) -> PlayerProfile;

    // Progression tracking
    fn record_puzzle_completion(
        ref self: TContractState, puzzle_id: u32, score: u32, time_taken: u64,
    );
    fn get_puzzle_stats(self: @TContractState, puzzle_id: u32) -> PuzzleStats;
    fn get_player_level(self: @TContractState, player: ContractAddress) -> u32;

    // Level unlocking
    fn unlock_level_with_achievement(ref self: TContractState, level_id: u32, achievement_id: u32);
    fn unlock_level_with_tokens(ref self: TContractState, level_id: u32, token_amount: u256);
    fn is_level_unlocked(self: @TContractState, player: ContractAddress, level_id: u32) -> bool;
    fn get_unlocked_levels(self: @TContractState, player: ContractAddress) -> Array<u32>;

    // Statistics
    fn get_total_puzzles_solved(self: @TContractState, player: ContractAddress) -> u32;
    fn get_average_completion_time(self: @TContractState, player: ContractAddress) -> u64;
    fn get_current_streak(self: @TContractState, player: ContractAddress) -> u32;
    fn get_player_statistics(
        self: @TContractState, player: ContractAddress,
    ) -> (u32, u64, u32, u32); // (puzzles_solved, avg_time, streak, total_score)
}
