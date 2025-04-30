#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::traits::Into;
    use core::num::traits::Zero;
    use quest_contract::base::types::{PlayerProfile, PuzzleStats, LevelUnlock};
    use quest_contract::interfaces::iplayerprofile::{IPlayerProfile, IPlayerProfileDispatcher, IPlayerProfileDispatcherTrait};
    use quest_contract::playerprofile::LogicQuestPlayerProfile;
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
        start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_block_timestamp,
    };
    use starknet::{ContractAddress, contract_address_const};

    // Common setup function for all tests
    fn setup() -> (IPlayerProfileDispatcher, ContractAddress) {
        let playerprofile_class = declare("LogicQuestPlayerProfile").unwrap().contract_class();
        let admin = contract_address_const::<'admin'>();
        let token_contract = contract_address_const::<'token'>();

        let (contract_address, _) = playerprofile_class
            .deploy(@array![admin.into(), token_contract.into()])
            .unwrap();
        let dispatcher = IPlayerProfileDispatcher { contract_address };
        (dispatcher, contract_address)
    }

    // Profile Management Tests
    mod profile_management_tests {
        use super::*;

        #[test]
        fn test_create_profile() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player
            start_cheat_caller_address(contract_address, player);
            
            // Create a profile
            let player_id = dispatcher.create_profile('TestPlayer');
            
            // Verify profile was created with correct data
            let profile = dispatcher.get_profile(player);
            assert(profile.player_id == player_id, 'Player ID mismatch');
            assert(profile.address == player, 'Player address mismatch');
            assert(profile.username == 'TestPlayer', 'Username mismatch');
            assert(profile.level == 1, 'Starting level should be 1');
            assert(profile.total_score == 0, 'Starting score should be 0');
            assert(profile.puzzles_solved == 0, 'No puzzles solved yet');
            assert(profile.streak_days == 0, 'No streak yet');
        }

        #[test]
        #[should_panic(expected: 'Profile already exists')]
        fn test_create_profile_duplicate() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player
            start_cheat_caller_address(contract_address, player);
            
            // Create a profile
            dispatcher.create_profile('TestPlayer');
            
            // Try to create another profile with the same address
            dispatcher.create_profile('AnotherName');
        }

        #[test]
        fn test_update_profile() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player
            start_cheat_caller_address(contract_address, player);
            
            // Create a profile
            dispatcher.create_profile('TestPlayer');
            
            // Update the profile
            dispatcher.update_profile('UpdatedName');
            
            // Verify profile was updated
            let profile = dispatcher.get_profile(player);
            assert(profile.username == 'UpdatedName', 'Username not updated');
        }

        #[test]
        #[should_panic(expected: 'Profile does not exist')]
        fn test_update_nonexistent_profile() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player
            start_cheat_caller_address(contract_address, player);
            
            // Try to update a profile that doesn't exist
            dispatcher.update_profile('UpdatedName');
        }

        #[test]
        #[should_panic(expected: 'Profile does not exist')]
        fn test_get_nonexistent_profile() {
            let (dispatcher, _) = setup();
            let nonexistent_player = contract_address_const::<'nonexistent'>();
            
            // Try to get a profile that doesn't exist
            dispatcher.get_profile(nonexistent_player);
        }
    }

    // Progression Tracking Tests
    mod progression_tests {
        use super::*;

        #[test]
        fn test_record_puzzle_completion() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();
            let puzzle_id = 1_u32;
            let score = 100_u32;
            let time_taken = 60_u64;

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Record puzzle completion
            dispatcher.record_puzzle_completion(puzzle_id, score, time_taken);
            
            // Verify profile was updated
            let profile = dispatcher.get_profile(player);
            assert(profile.total_score == score, 'Score not updated');
            assert(profile.puzzles_solved == 1, 'Puzzles solved not updated');
            assert(profile.total_time_spent == time_taken, 'Time spent not updated');
            
            // Verify puzzle stats were created
            let puzzle_stats = dispatcher.get_puzzle_stats(puzzle_id);
            assert(puzzle_stats.puzzle_id == puzzle_id, 'Puzzle ID mismatch');
            assert(puzzle_stats.player == player, 'Player address mismatch');
            assert(puzzle_stats.attempts == 1, 'Should have 1 attempt');
            assert(puzzle_stats.best_score == score, 'Best score mismatch');
            assert(puzzle_stats.best_time == time_taken, 'Best time mismatch');
        }

        #[test]
        fn test_multiple_puzzle_completions() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();
            let puzzle_id = 1_u32;

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Record first completion
            dispatcher.record_puzzle_completion(puzzle_id, 80, 100);
            
            // Record second completion with better score but worse time
            dispatcher.record_puzzle_completion(puzzle_id, 90, 120);
            
            // Record third completion with worse score but better time
            dispatcher.record_puzzle_completion(puzzle_id, 70, 80);
            
            // Verify profile was updated correctly
            let profile = dispatcher.get_profile(player);
            assert(profile.total_score == 80 + 90 + 70, 'Total score incorrect');
            assert(profile.puzzles_solved == 3, 'Should have 3 puzzles solved');
            assert(profile.total_time_spent == 100 + 120 + 80, 'Total time incorrect');
            
            // Verify puzzle stats track best score and time
            let puzzle_stats = dispatcher.get_puzzle_stats(puzzle_id);
            assert(puzzle_stats.attempts == 3, 'Should have 3 attempts');
            assert(puzzle_stats.best_score == 90, 'Best score should be 90');
            assert(puzzle_stats.best_time == 80, 'Best time should be 80');
        }

        #[test]
        fn test_get_puzzle_stats() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();
            let puzzle_id = 1_u32;

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Record puzzle completion
            dispatcher.record_puzzle_completion(puzzle_id, 100, 60);
            
            // Verify puzzle stats
            let puzzle_stats = dispatcher.get_puzzle_stats(puzzle_id);
            assert(puzzle_stats.puzzle_id == puzzle_id, 'Puzzle ID mismatch');
            assert(puzzle_stats.player == player, 'Player address mismatch');
            assert(puzzle_stats.attempts == 1, 'Should have 1 attempt');
            assert(puzzle_stats.best_score == 100, 'Best score mismatch');
            assert(puzzle_stats.best_time == 60, 'Best time mismatch');
        }

        #[test]
        fn test_get_player_level() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify initial level
            let level = dispatcher.get_player_level(player);
            assert(level == 1, 'Starting level should be 1');
            
            // Complete 5 puzzles to reach level 2
            let mut i = 0;
            while i < 5 {
                dispatcher.record_puzzle_completion(i, 100, 60);
                i += 1;
            }
            
            // Verify level increased
            let level = dispatcher.get_player_level(player);
            assert(level == 2, 'Level  be 2 after 5 puzzles');
        }

        #[test]
        fn test_automatic_level_progression() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Complete puzzles to reach different levels
            
            // Level 1: 0-4 puzzles
            assert(dispatcher.get_player_level(player) == 1, 'Should start at level 1');
            
            // Level 2: 5-14 puzzles
            let mut i = 0;
            while i < 5 {
                dispatcher.record_puzzle_completion(i, 100, 60);
                i += 1;
            }
            assert(dispatcher.get_player_level(player) == 2, 'Should be level 2');
            
            // Level 3: 15-29 puzzles
            while i < 15 {
                dispatcher.record_puzzle_completion(i, 100, 60);
                i += 1;
            }
            assert(dispatcher.get_player_level(player) == 3, 'Should be level 3');
            
            // Level 4: 30-49 puzzles
            while i < 30 {
                dispatcher.record_puzzle_completion(i, 100, 60);
                i += 1;
            }
            assert(dispatcher.get_player_level(player) == 4, 'Should be level 4');
            
            // Level 5: 50+ puzzles
            while i < 50 {
                dispatcher.record_puzzle_completion(i, 100, 60);
                i += 1;
            }
            assert(dispatcher.get_player_level(player) == 5, 'Should be level 5');
        }
    }

    // Level Unlocking Tests
    mod level_unlocking_tests {
        use super::*;

        #[test]
        fn test_default_level_unlocked() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify level 1 is unlocked by default
            let is_unlocked = dispatcher.is_level_unlocked(player, 1);
            assert(is_unlocked, 'Level 1  be unlocked by default');
            
            // Verify other levels are not unlocked
            let is_unlocked = dispatcher.is_level_unlocked(player, 2);
            assert(!is_unlocked, 'Level 2  not be unlocked yet');
        }

        #[test]
        fn test_unlock_level_with_achievement() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Unlock level 2 with achievement
            dispatcher.unlock_level_with_achievement(2, 1);
            
            // Verify level 2 is now unlocked
            let is_unlocked = dispatcher.is_level_unlocked(player, 2);
            assert(is_unlocked, 'Level 2 should be unlocked');
            
            // Verify unlocked levels list includes level 2
            let unlocked_levels = dispatcher.get_unlocked_levels(player);
            assert(unlocked_levels.len() == 2, 'Should have 2 unlocked levels');
            
            // Check each level in the list
            let mut found_level_1 = false;
            let mut found_level_2 = false;
            let mut i = 0;
            while i < unlocked_levels.len() {
                let level_id = *unlocked_levels.at(i);
                if level_id == 1 {
                    found_level_1 = true;
                } else if level_id == 2 {
                    found_level_2 = true;
                }
                i += 1;
            }
            
            assert(found_level_1, 'Level 1 be in unlocked list');
            assert(found_level_2, 'Level 2  be in unlocked list');
        }

        #[test]
        fn test_unlock_level_with_tokens() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Unlock level 2 with tokens
            dispatcher.unlock_level_with_tokens(2, 100);
            
            // Verify level 2 is now unlocked
            let is_unlocked = dispatcher.is_level_unlocked(player, 2);
            assert(is_unlocked, 'Level 2 should be unlocked');
        }

        #[test]
        #[should_panic(expected: 'Level already unlocked')]
        fn test_unlock_already_unlocked_level() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Unlock level 2 with achievement
            dispatcher.unlock_level_with_achievement(2, 1);
            
            // Try to unlock it again
            dispatcher.unlock_level_with_achievement(2, 1);
        }

        #[test]
        #[should_panic(expected: 'Prerequisite level not unlocked')]
        fn test_unlock_level_without_prerequisite() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Try to unlock level 3 without unlocking level 2 first
            dispatcher.unlock_level_with_achievement(3, 2);
        }

        #[test]
        #[should_panic(expected: 'Insufficient tokens')]
        fn test_unlock_level_with_insufficient_tokens() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Try to unlock level 2 with insufficient tokens
            dispatcher.unlock_level_with_tokens(2, 50);
        }

        #[test]
        fn test_get_unlocked_levels() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify only level 1 is unlocked initially
            let unlocked_levels = dispatcher.get_unlocked_levels(player);
            assert(unlocked_levels.len() == 1, 'Should have 1 unlocked level');
            assert(*unlocked_levels.at(0) == 1, 'Level 1 should be unlocked');
            
            // Unlock level 2
            dispatcher.unlock_level_with_achievement(2, 1);
            
            // Verify levels 1 and 2 are unlocked
            let unlocked_levels = dispatcher.get_unlocked_levels(player);
            assert(unlocked_levels.len() == 2, 'Should have 2 unlocked levels');
        }
    }

    // Statistics Tests
    mod statistics_tests {
        use super::*;

        #[test]
        fn test_get_total_puzzles_solved() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify initial count is 0
            let puzzles_solved = dispatcher.get_total_puzzles_solved(player);
            assert(puzzles_solved == 0, ' 0 puzzles solved initially');
            
            // Complete 3 puzzles
            dispatcher.record_puzzle_completion(1, 100, 60);
            dispatcher.record_puzzle_completion(2, 90, 70);
            dispatcher.record_puzzle_completion(3, 80, 80);
            
            // Verify count is updated
            let puzzles_solved = dispatcher.get_total_puzzles_solved(player);
            assert(puzzles_solved == 3, 'Should have 3 puzzles solved');
        }

        #[test]
        fn test_get_average_completion_time() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify initial average is 0
            let avg_time = dispatcher.get_average_completion_time(player);
            assert(avg_time == 0, ' average time should be 0');
            
            // Complete 3 puzzles with different times
            dispatcher.record_puzzle_completion(1, 100, 60);
            dispatcher.record_puzzle_completion(2, 90, 90);
            dispatcher.record_puzzle_completion(3, 80, 120);
            
            // Verify average is calculated correctly: (60 + 90 + 120) / 3 = 90
            let avg_time = dispatcher.get_average_completion_time(player);
            assert(avg_time == 90, 'Average time should be 90');
        }

        #[test]
        fn test_get_current_streak() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Verify initial streak is 0
            let streak = dispatcher.get_current_streak(player);
            assert(streak == 0, 'Initial streak should be 0');
            
            // Complete a puzzle to start streak
            let day1 = 1000;
            start_cheat_block_timestamp(contract_address, day1);
            dispatcher.record_puzzle_completion(1, 100, 60);
            
            // Verify streak is 1 after first activity
            let streak = dispatcher.get_current_streak(player);
            assert(streak == 1, 'Streak  1 after first activity');
            
            // Complete another puzzle on the next day
            let day2 = day1 + 86400; // Add one day (86400 seconds)
            start_cheat_block_timestamp(contract_address, day2);
            dispatcher.record_puzzle_completion(2, 90, 70);
            
            // Verify streak is 2 after consecutive day
            let streak = dispatcher.get_current_streak(player);
            assert(streak == 2, 'Streak  after consecutive day');
            
            // Skip a day and complete another puzzle
            let day4 = day2 + (2 * 86400); // Skip to day 4
            start_cheat_block_timestamp(contract_address, day4);
            dispatcher.record_puzzle_completion(3, 80, 80);
            
            // Verify streak is reset to 1 after missing a day
            let streak = dispatcher.get_current_streak(player);
            assert(streak == 1, 'Streak reset to 1 after gap');
        }

        #[test]
        fn test_get_player_statistics() {
            let (dispatcher, contract_address) = setup();
            let player = contract_address_const::<'player'>();

            // Set caller address to player and create profile
            start_cheat_caller_address(contract_address, player);
            dispatcher.create_profile('TestPlayer');
            
            // Complete 3 puzzles
            dispatcher.record_puzzle_completion(1, 100, 60);
            dispatcher.record_puzzle_completion(2, 90, 90);
            dispatcher.record_puzzle_completion(3, 80, 120);
            
            // Get all statistics at once
            let (puzzles_solved, avg_time, streak, total_score) = dispatcher.get_player_statistics(player);
            
            // Verify all stats are correct
            assert(puzzles_solved == 3, 'Should have 3 puzzles solved');
            assert(avg_time == 90, 'Average time should be 90');
            assert(streak == 1, 'Streak should be 1');
            assert(total_score == 270, 'Total score should be 270');
        }
    }
}
