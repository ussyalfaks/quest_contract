use quest_contract::base::types::{GameMode, GameModeType, UserGameModeProgress, GameModeAchievement};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IGameMode<TContractState> {
    // Admin functions
    fn create_game_mode(
        ref self: TContractState,
        name: felt252,
        mode_type: GameModeType,
        reward_multiplier: u32,
        time_modifier: u32,
        points_threshold: u32,
    ) -> u32;
    
    fn update_game_mode(
        ref self: TContractState,
        mode_id: u32,
        name: felt252,
        reward_multiplier: u32,
        time_modifier: u32,
        points_threshold: u32,
    );
    
    fn enable_game_mode(ref self: TContractState, mode_id: u32);
    fn disable_game_mode(ref self: TContractState, mode_id: u32);
    
    // Achievement management
    fn create_achievement(
        ref self: TContractState,
        mode_id: u32,
        name: felt252,
        description: felt252,
        condition_type: u8,
        condition_value: u32,
        reward_points: u32,
    ) -> u32;
    
    // User gameplay functions
    fn start_puzzle_in_mode(
        ref self: TContractState,
        user: ContractAddress,
        puzzle_id: u32,
        mode_id: u32,
    ) -> (u32, u32); // Returns (adjusted time limit, reward multiplier)
    
    fn complete_puzzle_in_mode(
        ref self: TContractState,
        user: ContractAddress,
        puzzle_id: u32,
        mode_id: u32,
        points_earned: u32,
        difficulty: u8,
    ) -> (u32, Array<u32>); // Returns (adjusted rewards, achievement IDs earned)
    
    // Query functions
    fn get_game_mode(self: @TContractState, mode_id: u32) -> GameMode;
    fn get_total_game_modes(self: @TContractState) -> u32;
    fn get_enabled_game_modes(self: @TContractState) -> Array<u32>;
    fn get_user_progress(self: @TContractState, user: ContractAddress, mode_id: u32) -> UserGameModeProgress;
    fn get_achievement(self: @TContractState, achievement_id: u32) -> GameModeAchievement;
    fn get_mode_achievements(self: @TContractState, mode_id: u32) -> Array<u32>;
    fn get_user_achievements(self: @TContractState, user: ContractAddress) -> Array<u32>;
    fn calculate_reward_modifier(self: @TContractState, mode_id: u32, points: u32, time_taken: u32) -> u32;
} 