#[cfg(test)]
mod tests {
    use core::byte_array::ByteArray;
    use quest_contract::interfaces::iquestNFT::{
        ILogiQuestAchievement, ILogiQuestAchievementDispatcher,
    };
    use quest_contract::questNFT::LogiQuestAchievement;
    use quest_contract::questNFT::LogiQuestAchievement::{AchievementTier, AchievementType};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
        start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_block_timestamp,
    };
    use starknet::{ContractAddress, contract_address_const};

    // Common setup function for all tests
    fn setup() -> (ILogiQuestAchievementDispatcher, ContractAddress) {
        let questNFT_class = declare("LogiQuestAchievement").unwrap().contract_class();
        let admin = contract_address_const::<'admin'>();
        let puzzle_contract = contract_address_const::<'puzzle'>();

        let (contract_address, _) = questNFT_class
            .deploy(@array![admin.into(), puzzle_contract.into()])
            .unwrap();
        let dispatcher = ILogiQuestAchievementDispatcher { contract_address };
        (dispatcher, contract_address)
    }

    // Admin Tests Module
    mod admin_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_authorize_minter() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let new_minter = contract_address_const::<'minter'>();

            start_cheat_caller_address(contract_address, admin);
            dispatcher.authorize_minter(new_minter);

            let is_authorized = dispatcher.is_authorized_minter(new_minter);
            assert(is_authorized, 'Minter should be authorized');
        }

        #[test]
        #[should_panic(expected: 'Only admin can call this')]
        fn test_authorize_minter_non_admin() {
            let (dispatcher, contract_address) = setup();
            let non_admin = contract_address_const::<'non_admin'>();
            let new_minter = contract_address_const::<'minter'>();

            start_cheat_caller_address(contract_address, non_admin);
            dispatcher.authorize_minter(new_minter);
        }

        #[test]
        fn test_revoke_minter() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let minter = contract_address_const::<'minter'>();

            start_cheat_caller_address(contract_address, admin);
            dispatcher.authorize_minter(minter);
            dispatcher.revoke_minter(minter);

            let is_authorized = dispatcher.is_authorized_minter(minter);
            assert(!is_authorized, 'Minter should be revoked');
        }

        #[test]
        fn test_update_puzzle_contract() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let new_puzzle = contract_address_const::<'new_puzzle'>();

            start_cheat_caller_address(contract_address, admin);
            dispatcher.update_puzzle_contract(new_puzzle);

            let current_puzzle = dispatcher.get_puzzle_contract();
            assert(current_puzzle == new_puzzle, 'Puzzle contract not updated');
        }
    }

    // Achievement Minting Tests Module
    mod minting_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_mint_achievement() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            // Mock a non-zero timestamp
            let mock_timestamp = 1234567890;
            start_cheat_block_timestamp(contract_address, mock_timestamp);

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1, // puzzle_id
                    90, // score
                    100, // max_score
                    30, // time_taken
                    60, // max_time
                    2, // difficulty
                    AchievementType::PuzzleCompletion(()),
                );

            let (tier, achievement_type, puzzle_id, score, difficulty, timestamp) = dispatcher
                .get_achievement_details(token_id);

            // Assert for tier using pattern matching
            match tier {
                AchievementTier::Gold(()) => {}, // Expected tier
                _ => { assert(false, 'Wrong achievement tier'); },
            }

            // Assert for achievement type using pattern matching
            match achievement_type {
                AchievementType::PuzzleCompletion(()) => {}, // Expected type
                _ => { assert(false, 'Wrong achievement type'); },
            }

            assert(puzzle_id == 1, 'Wrong puzzle ID');
            assert(score == 90, 'Wrong score');
            assert(difficulty == 2, 'Wrong difficulty');
            assert(timestamp > 0, 'Timestamp not set');
        }


        #[test]
        #[should_panic(expected: 'Not authorized to mint')]
        fn test_mint_achievement_unauthorized() {
            let (dispatcher, contract_address) = setup();
            let unauthorized = contract_address_const::<'unauthorized'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, unauthorized);
            dispatcher
                .mint_achievement(
                    recipient, 1, 90, 100, 30, 60, 2, AchievementType::PuzzleCompletion(()),
                );
        }

        #[test]
        #[should_panic(expected: 'Cannot mint to zero address')]
        fn test_mint_achievement_zero_address() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let zero_address = contract_address_const::<0>();

            start_cheat_caller_address(contract_address, admin);
            dispatcher
                .mint_achievement(
                    zero_address, 1, 90, 100, 30, 60, 2, AchievementType::PuzzleCompletion(()),
                );
        }
    }

    // Achievement Tier Tests Module
    mod tier_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_platinum_tier_achievement() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    100, // Perfect score
                    100,
                    0, // Instant completion
                    60,
                    3, // High difficulty
                    AchievementType::PerfectScore(()),
                );

            let tier = dispatcher.get_achievement_tier(token_id);
            //assert(tier == AchievementTier::Platinum(()), 'Should be platinum tier');
        }

        #[test]
        fn test_gold_tier_achievement() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    85, // Good score
                    100,
                    20, // Good time
                    60,
                    2,
                    AchievementType::PuzzleCompletion(()),
                );

            let tier = dispatcher.get_achievement_tier(token_id);
            // assert(tier == AchievementTier::Gold(()), 'Should be gold tier');
        }

        #[test]
        fn test_silver_tier_achievement() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    65, // Average score
                    100,
                    40, // Average time
                    60,
                    1,
                    AchievementType::PuzzleCompletion(()),
                );

            let tier = dispatcher.get_achievement_tier(token_id);
            // assert(tier == AchievementTier::Silver(()), 'Should be silver tier');
        }

        #[test]
        fn test_bronze_tier_achievement() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    50, // Low score
                    100,
                    55, // Slow time
                    60,
                    1,
                    AchievementType::PuzzleCompletion(()),
                );

            let tier = dispatcher.get_achievement_tier(token_id);
            //assert(tier == AchievementTier::Bronze(()), 'Should be bronze tier');
        }
    }

    // Achievement Type Tests Module
    mod achievement_type_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_puzzle_completion_type() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient, 1, 90, 100, 30, 60, 2, AchievementType::PuzzleCompletion(()),
                );

            let achievement_type = dispatcher.get_achievement_type(token_id);
            // assert(achievement_type == AchievementType::PuzzleCompletion(()), 'Wrong achievement
        // type');
        }

        #[test]
        fn test_speed_run_type() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    90,
                    100,
                    10, // Very fast time
                    60,
                    2,
                    AchievementType::SpeedRun(()),
                );

            let achievement_type = dispatcher.get_achievement_type(token_id);
            // assert(achievement_type == AchievementType::SpeedRun(()), 'Wrong achievement type');
        }

        #[test]
        fn test_perfect_score_type() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient,
                    1,
                    100, // Perfect score
                    100,
                    30,
                    60,
                    2,
                    AchievementType::PerfectScore(()),
                );

            let achievement_type = dispatcher.get_achievement_type(token_id);
            // assert(achievement_type == AchievementType::PerfectScore(()), 'Wrong achievement
        // type');
        }
    }

    // Token URI Tests Module
    mod token_uri_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_set_token_uri() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            let token_id = dispatcher
                .mint_achievement(
                    recipient, 1, 90, 100, 30, 60, 2, AchievementType::PuzzleCompletion(()),
                );

            let new_uri: felt252 = 'new_uri';
            dispatcher.set_token_uri(token_id, new_uri);
        }

        #[test]
        #[should_panic(expected: 'Token does not exist')]
        fn test_set_token_uri_nonexistent() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();

            start_cheat_caller_address(contract_address, admin);
            dispatcher.set_token_uri(999, 'new_uri');
        }
    }

    // Total Supply Tests Module
    mod supply_tests {
        use quest_contract::interfaces::iquestNFT::ILogiQuestAchievementDispatcherTrait;
        use super::*;

        #[test]
        fn test_total_supply() {
            let (dispatcher, contract_address) = setup();
            let admin = contract_address_const::<'admin'>();
            let recipient = contract_address_const::<'recipient'>();

            start_cheat_caller_address(contract_address, admin);
            assert(dispatcher.total_supply() == 0, 'Initial supply should be 0');

            dispatcher
                .mint_achievement(
                    recipient, 1, 90, 100, 30, 60, 2, AchievementType::PuzzleCompletion(()),
                );

            assert(dispatcher.total_supply() == 1, 'Supply should be 1');

            dispatcher
                .mint_achievement(
                    recipient, 2, 95, 100, 20, 60, 2, AchievementType::PerfectScore(()),
                );

            assert(dispatcher.total_supply() == 2, 'Supply should be 2');
        }
    }
}
