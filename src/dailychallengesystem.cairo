use starknet::ContractAddress;
use openzeppelin::access::ownable::OwnableComponent; // Import OwnableComponent

#[starknet::interface]
pub trait IDailyChallengeSystem<TContractState> {
    fn submit_challenge_completion(ref self: TContractState);
    fn get_user_data(self: @TContractState, user: ContractAddress) -> UserData;
    fn get_current_system_day(self: @TContractState) -> u64;
    fn update_reward_parameters( ref self: TContractState, new_base_reward: u256, new_streak_bonus: u256);
    fn update_system_start_timestamp(ref self: TContractState, new_start_timestamp: u64);
    // Add Ownable interface functions if using the component
    fn owner(self: @TContractState) -> ContractAddress; // Example from Ownable
}

// --- Constants for Achievements ---
const SEVEN_DAY_ACHIEVEMENT_ID: u32 = 0;
const THIRTY_DAY_ACHIEVEMENT_ID: u32 = 1;
const NINETY_DAY_ACHIEVEMENT_ID: u32 = 2;

const SEVEN_DAY_STREAK_MILESTONE: u32 = 7;
const THIRTY_DAY_STREAK_MILESTONE: u32 = 30;
const NINETY_DAY_STREAK_MILESTONE: u32 = 90;

const SEVEN_DAY_ACHIEVEMENT_BONUS: u256 = 50;
const THIRTY_DAY_ACHIEVEMENT_BONUS: u256 = 250;
const NINETY_DAY_ACHIEVEMENT_BONUS: u256 = 1000;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct UserData {
    last_completed_system_day: u64,
    current_streak: u32,
}

#[starknet::contract]
mod DailyChallengeSystem { 
    use starknet::{get_caller_address, ContractAddress, get_block_timestamp};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::*; // Wildcard import for storage
    use openzeppelin::access::ownable::OwnableComponent; // Use component
    use super::{IDailyChallengeSystem, UserData};
    use core::num::traits::Zero;


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[storage]
    pub struct Storage {
        initialized: bool,
        system_start_timestamp: u64,
        seconds_per_day: u64,
        reward_token_address: ContractAddress,
        base_reward_amount: u256,
        streak_bonus_per_day: u256,
        user_challenge_data: Map::<ContractAddress, UserData>,
        user_claimed_achievements: Map::<(ContractAddress, u32), bool>,
        #[substorage(v0)] // Add substorage for OwnableComponent
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    pub enum Event {
        ChallengeSubmitted: ChallengeSubmitted,
        AchievementUnlocked: AchievementUnlocked,
        #[flat] // Flatten the OwnableEvent to avoid name conflicts
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct ChallengeSubmitted {
        user: starknet::ContractAddress,
        system_day: u64,
        streak: u32,
        total_reward_for_day: u256,
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct AchievementUnlocked {
        user: starknet::ContractAddress,
        achievement_id: u32,
        streak_milestone_achieved: u32,
        achievement_bonus_reward: u256,
    }

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        start_timestamp: u64,
        daily_duration_seconds: u64,
        reward_token_address: ContractAddress,
        base_reward: u256,
        streak_bonus: u256
        ) {
        assert(!self.initialized.read(), 'Contract already initialized');

        self.ownable.initializer(owner); // Initialize Ownable component

        self.system_start_timestamp.write(start_timestamp);

        assert(daily_duration_seconds > 0, 'Daily duration must be positive');
        self.seconds_per_day.write(daily_duration_seconds);

        assert(!reward_token_address.is_zero(), 'Reward token address cannot be zero');
        self.reward_token_address.write(reward_token_address);

        self.base_reward_amount.write(base_reward);
        self.streak_bonus_per_day.write(streak_bonus);

        self.initialized.write(true);
    }


    #[abi(embed_v0)]
    pub impl DailyChallengeSystemImpl of super::IDailyChallengeSystem<ContractState> {
        fn submit_challenge_completion(ref self: ContractState) {

            assert(self.initialized.read(), 'ERR_NOT_INITIALIZED');

            let caller = get_caller_address();
            let current_system_day = self._get_current_system_day(); // Use internal function

            let mut user_data = self.user_challenge_data.read(caller);

            let is_first_submission_ever = user_data.last_completed_system_day == 0
                                        && user_data.current_streak == 0;

            if !is_first_submission_ever {
                 // Check if already submitted today
                assert(user_data.last_completed_system_day < current_system_day, 'ERR_DAY_ALREADY_COMPLETED');
            }


            // Streak logic
            if user_data.last_completed_system_day == (current_system_day - 1_u64) {
                user_data.current_streak += 1_u32;
            } else {
                // Reset streak if day was missed or first submission on a later day
                user_data.current_streak = 1_u32;
            }

            user_data.last_completed_system_day = current_system_day;

            // Include base reward in total
            let mut total_reward_for_today = self.base_reward_amount.read();

            let streak_bonus_per_day = self.streak_bonus_per_day.read();

            if user_data.current_streak > 0_u32 {
                 total_reward_for_today += streak_bonus_per_day;
            }


            // --- Achievement Logic & Bonus Rewards (Using new map-based functions) ---
            // Check and grant 7-day streak achievement
            if user_data.current_streak >= SEVEN_DAY_STREAK_MILESTONE {
                if !self._is_achievement_claimed(caller, SEVEN_DAY_ACHIEVEMENT_ID) {
                    total_reward_for_today +=  SEVEN_DAY_ACHIEVEMENT_BONUS.into(); // Cast u256 constant to u256
                    self._mark_achievement_as_claimed(caller, SEVEN_DAY_ACHIEVEMENT_ID);
                    self.emit(AchievementUnlocked {
                        user: caller,
                        achievement_id: SEVEN_DAY_ACHIEVEMENT_ID,
                        streak_milestone_achieved: SEVEN_DAY_STREAK_MILESTONE,
                        achievement_bonus_reward: SEVEN_DAY_ACHIEVEMENT_BONUS.into() // Cast u256 constant to u256
                    });
                }
            }
            // Check and grant 30-day streak achievement
            if user_data.current_streak >= THIRTY_DAY_STREAK_MILESTONE {
                if !self._is_achievement_claimed(caller, THIRTY_DAY_ACHIEVEMENT_ID) {
                    total_reward_for_today +=  THIRTY_DAY_ACHIEVEMENT_BONUS.into(); 
                    self._mark_achievement_as_claimed(caller, THIRTY_DAY_ACHIEVEMENT_ID);
                    self.emit(AchievementUnlocked {
                        user: caller,
                        achievement_id: THIRTY_DAY_ACHIEVEMENT_ID,
                        streak_milestone_achieved: THIRTY_DAY_STREAK_MILESTONE,
                        achievement_bonus_reward: THIRTY_DAY_ACHIEVEMENT_BONUS.into() 
                    });
                }
            }
            // Check and grant 90-day streak achievement
            if user_data.current_streak >= NINETY_DAY_STREAK_MILESTONE {
                if !self._is_achievement_claimed(caller, NINETY_DAY_ACHIEVEMENT_ID) {
                    total_reward_for_today +=  NINETY_DAY_ACHIEVEMENT_BONUS.into(); 
                    self._mark_achievement_as_claimed(caller, NINETY_DAY_ACHIEVEMENT_ID);
                    self.emit(AchievementUnlocked {
                        user: caller,
                        achievement_id: NINETY_DAY_ACHIEVEMENT_ID,
                        streak_milestone_achieved: NINETY_DAY_STREAK_MILESTONE,
                        achievement_bonus_reward: NINETY_DAY_ACHIEVEMENT_BONUS.into() 
                    });
                }
            }

            self.user_challenge_data.write(caller, user_data);

            let token_address = self.reward_token_address.read();
            assert(!token_address.is_zero(), 'ERR_REWARD_TOKEN_NOT_SET');
            let token = IERC20Dispatcher { contract_address: token_address };

            let transfer = token.transfer(caller, total_reward_for_today);

            assert(transfer, 'Transfer Failed');

            self
                .emit (
                    ChallengeSubmitted {
                        user: caller,
                        system_day: current_system_day,
                        streak: user_data.current_streak,
                        total_reward_for_day,
            } );

        }

        fn get_user_data(self: @ContractState, user: ContractAddress) -> UserData {
            self.user_challenge_data.read(user);
        }

        fn get_current_system_day(self: @ContractState) -> u64 {
            self._get_current_system_day() // Delegate to internal function
        }

        fn update_reward_parameters( ref self: ContractState, new_base_reward: u256, new_streak_bonus: u256) {
            self.ownable.assert_only_owner(); // Use Ownable check

            self.base_reward_amount.write(new_base_reward);
            // Corrected variable name
            self.streak_bonus_per_day.write(new_streak_bonus);
        }

        fn update_system_start_timestamp(ref self: ContractState, new_start_timestamp: u64){
            self.ownable.assert_only_owner(); // Use Ownable check
            self.system_start_timestamp.write(new_start_timestamp);
        }

        // Implement Ownable interface function if using the component
        fn owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }
    }

    #[generate_trait]
    pub impl Internal of InternalTrait {
        fn _get_current_system_day(self: @ContractState) -> u64 {
            let start_ts = self.system_start_timestamp.read();
            let secs_per_day = self.seconds_per_day.read();

            assert(secs_per_day > 0, 'ERR_SECONDS_PER_DAY_NOT_SET');

            let current_ts = get_block_timestamp();

            // checks whether the challenge has started
            assert(current_ts >= start_ts, 'ERR_CHALLENGE_NOT_STARTED_YET');

            (current_ts - start_ts) / secs_per_day
        }

        fn _is_achievement_claimed(self: @ContractState, user: ContractAddress, achievement_id: u32) -> bool {
            self.user_claimed_achievements.read((user, achievement_id))
        }

        fn _mark_achievement_as_claimed(ref self: ContractState, user: ContractAddress, achievement_id: u32) {
            self.user_claimed_achievements.write((user, achievement_id), true);
        }
    }
}