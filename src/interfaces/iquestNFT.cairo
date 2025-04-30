use quest_contract::questNFT::LogiQuestAchievement::{AchievementTier, AchievementType};
use starknet::ContractAddress;
// Interface trait
#[starknet::interface]
pub trait ILogiQuestAchievement<TContractState> {
    // Admin functions
    fn authorize_minter(ref self: TContractState, minter_address: ContractAddress);
    fn revoke_minter(ref self: TContractState, minter_address: ContractAddress);
    fn update_puzzle_contract(ref self: TContractState, new_puzzle_contract: ContractAddress);
    fn set_token_uri(ref self: TContractState, token_id: u256, uri: felt252);

    // Achievement minting function
    fn mint_achievement(
        ref self: TContractState,
        recipient: ContractAddress,
        puzzle_id: u32,
        score: u32,
        max_score: u32,
        time_taken: u32,
        max_time: u32,
        difficulty: u8,
        achievement_type: AchievementType,
    ) -> u256;

    // Achievement query functions
    fn get_achievement_details(
        self: @TContractState, token_id: u256,
    ) -> (AchievementTier, AchievementType, u32, u32, u8, u64);
    fn get_achievement_tier(self: @TContractState, token_id: u256) -> AchievementTier;
    fn get_achievement_type(self: @TContractState, token_id: u256) -> AchievementType;
    //fn token_uri(self: @TContractState, token_id: u256) -> felt252;
    fn is_authorized_minter(self: @TContractState, address: ContractAddress) -> bool;
    fn get_puzzle_contract(self: @TContractState) -> ContractAddress;
    fn total_supply(self: @TContractState) -> u256;
}
