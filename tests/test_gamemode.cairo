use core::array::ArrayTrait;
use core::num::traits::Zero;
use core::option::OptionTrait;
use quest_contract::base::types::{
    GameMode, GameModeAchievement, GameModeType, UserGameModeProgress,
};
use quest_contract::interfaces::igamemode::{IGameModeDispatcher, IGameModeDispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::ContractAddress;
use starknet::testing::{set_block_timestamp, set_contract_address};

fn setup() -> (ContractAddress, ContractAddress) {
    let admin: ContractAddress = 'Admin'.try_into().unwrap();
    let contract = declare("LogicQuestGameMode").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![admin.into()]).unwrap();
    (contract_address, admin)
}

#[test]
fn test_default_game_modes_exist() {
    let (contract_address, _) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Check total modes
    let total_modes = contract.get_total_game_modes();
    assert(total_modes == 3, 'Should have 3 default modes');

    // Check each mode exists and has correct data
    let practice_mode = contract.get_game_mode(1);
    assert(practice_mode.name == 'Practice', 'Practice mode name mismatch');
    assert(practice_mode.reward_multiplier == 100, 'Practice reward multiplier wrong');
    assert(practice_mode.time_modifier == 150, 'Practice time modifier wrong');

    let challenge_mode = contract.get_game_mode(2);
    assert(challenge_mode.name == 'Challenge', 'Challenge mode name mismatch');
    assert(challenge_mode.reward_multiplier == 150, 'Challenge reward multiplier wrong');
    assert(challenge_mode.time_modifier == 100, 'Challenge time modifier wrong');

    let time_attack_mode = contract.get_game_mode(3);
    assert(time_attack_mode.name == 'Time Attack', 'Time Attack mode name mismatch');
    assert(time_attack_mode.reward_multiplier == 125, 'Time Attack reward multiplier wrong');
    assert(time_attack_mode.time_modifier == 75, 'Time Attack time modifier wrong');
}

#[test]
fn test_create_custom_game_mode() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Create a new custom game mode
    let mode_id = contract
        .create_game_mode(
            'Custom Mode',
            GameModeType::Challenge,
            200, // 2x rewards
            80, // 20% less time
            150 // Points threshold
        );

    // Check it was created as the 4th mode
    assert(mode_id == 4, 'Custom mode should be ID 4');

    // Verify the mode's properties
    let custom_mode = contract.get_game_mode(mode_id);
    assert(custom_mode.name == 'Custom Mode', 'Custom mode name mismatch');
    assert(custom_mode.reward_multiplier == 200, 'Custom reward multiplier wrong');
    assert(custom_mode.time_modifier == 80, 'Custom time modifier wrong');
    assert(custom_mode.points_threshold == 150, 'Custom points threshold wrong');
    assert(custom_mode.enabled == true, 'Custom mode should be enabled');
}

#[test]
fn test_update_game_mode() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Update an existing mode (practice mode)
    contract
        .update_game_mode(
            1, // Practice mode
            'Updated Practice',
            120, // 1.2x rewards
            140, // 40% more time
            50 // New threshold
        );

    // Verify the changes
    let updated_mode = contract.get_game_mode(1);
    assert(updated_mode.name == 'Updated Practice', 'Name not updated');
    assert(updated_mode.reward_multiplier == 120, 'Reward multiplier not updated');
    assert(updated_mode.time_modifier == 140, 'Time modifier not updated');
    assert(updated_mode.points_threshold == 50, 'Points threshold not updated');
}

#[test]
fn test_enable_disable_game_mode() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Disable the challenge mode (ID 2)
    contract.disable_game_mode(2);

    // Verify it's disabled
    let mode = contract.get_game_mode(2);
    assert(mode.enabled == false, 'Mode should be disabled');

    // Check enabled modes list doesn't include the disabled mode
    let enabled_modes = contract.get_enabled_game_modes();

    // Check each mode in the list
    let mut found_mode_2 = false;
    let mut i = 0;
    loop {
        if i >= enabled_modes.len() {
            break;
        }

        if *enabled_modes.at(i) == 2 {
            found_mode_2 = true;
            break;
        }

        i += 1;
    }

    assert(found_mode_2 == false, 'Disabled mode should not be in list');

    // Re-enable the mode
    contract.enable_game_mode(2);

    // Verify it's enabled
    let mode = contract.get_game_mode(2);
    assert(mode.enabled == true, 'Mode should be enabled');

    // Check it appears in the enabled list
    let enabled_modes = contract.get_enabled_game_modes();
    let mut found_mode_2 = false;

    let mut i = 0;
    loop {
        if i >= enabled_modes.len() {
            break;
        }

        if *enabled_modes.at(i) == 2 {
            found_mode_2 = true;
            break;
        }

        i += 1;
    }

    assert(found_mode_2 == true, 'Mode should be in enabled list');
}

#[test]
fn test_create_achievement() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Create a new achievement for practice mode
    let achievement_id = contract
        .create_achievement(
            1, // Practice mode ID
            'Test Achievement',
            'Description of test achievement',
            1, // Puzzles completed type
            10, // Complete 10 puzzles
            100 // 100 reward points
        );

    // Get achievement count from the mode
    let mode_achievements = contract.get_mode_achievements(1);

    // The default practice mode already has 1 achievement, so we should now have 2
    assert(mode_achievements.len() == 2, 'Should have 2 achievements');

    // Verify the achievement properties
    let achievement = contract.get_achievement(achievement_id);
    assert(achievement.name == 'Test Achievement', 'Achievement name mismatch');
    assert(achievement.mode_id == 1, 'Achievement mode ID mismatch');
    assert(achievement.condition_type == 1, 'Achievement condition type mismatch');
    assert(achievement.condition_value == 10, 'Achievement condition value mismatch');
    assert(achievement.reward_points == 100, 'Achievement reward points mismatch');
}

#[test]
fn test_start_puzzle_in_mode() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Create a test user
    let user: ContractAddress = 'TestUser'.try_into().unwrap();

    // Set current timestamp for testing
    set_block_timestamp(1000);

    // Start a puzzle in practice mode
    let (time_limit, reward_multiplier) = contract
        .start_puzzle_in_mode(user, 1, // Puzzle ID
        1 // Practice Mode ID
        );

    // Verify the returned values
    // Practice mode: 50% more time, normal rewards
    assert(time_limit == 300, 'Incorrect time limit'); // Default 300 seconds + 50% modifier
    assert(reward_multiplier == 100, 'Incorrect reward multiplier'); // 1x rewards
}

#[test]
fn test_complete_puzzle_and_progress() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Create a test user
    let user: ContractAddress = 'TestUser'.try_into().unwrap();

    // Set initial timestamp
    set_block_timestamp(1000);

    // Start puzzle in practice mode
    contract.start_puzzle_in_mode(user, 1, 1);

    // Advance time by 100 seconds
    set_block_timestamp(1100);

    // Complete the puzzle
    let (adjusted_rewards, achievements) = contract
        .complete_puzzle_in_mode(
            user,
            1, // Puzzle ID
            1, // Practice Mode ID (standard rewards)
            100, // Points earned
            5 // Difficulty
        );

    // Verify rewards (practice mode: 1x multiplier)
    assert(adjusted_rewards == 100, 'Incorrect adjusted rewards');

    // Verify user progress
    let progress = contract.get_user_progress(user, 1);
    assert(progress.completed_puzzles == 1, 'Should have 1 completed puzzle');
    assert(progress.total_points == 100, 'Should have 100 points');
    assert(progress.highest_difficulty_completed == 5, 'Should have difficulty 5');
    assert(progress.last_played_timestamp == 1100, 'Last played timestamp wrong');
}

#[test]
fn test_challenge_mode_reward_modifiers() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Create a test user
    let user: ContractAddress = 'TestUser'.try_into().unwrap();

    // Test completion in challenge mode with threshold exceeded
    // Challenge mode: 50% more rewards + 20% bonus for exceeding threshold
    set_block_timestamp(1000);
    contract.start_puzzle_in_mode(user, 1, 2); // Mode 2 = Challenge

    set_block_timestamp(1100);
    let (adjusted_rewards, _) = contract
        .complete_puzzle_in_mode(
            user, 1, // Puzzle ID
            2, // Challenge Mode
            150, // Points > threshold (which is 100)
            5,
        );

    // 150 base points * 1.5 (mode multiplier) * 1.2 (threshold bonus) = 270
    assert(adjusted_rewards == 270, 'Challenge mode rewards incorrect');
}

#[test]
fn test_time_attack_mode_reward_modifiers() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Create a test user
    let user: ContractAddress = 'TestUser'.try_into().unwrap();

    // Test fast completion in time attack mode
    // Time attack: 25% more rewards + 50% bonus for very fast completion (< 60s)
    set_block_timestamp(1000);
    contract.start_puzzle_in_mode(user, 1, 3); // Mode 3 = Time Attack

    set_block_timestamp(1050); // 50 seconds later (fast completion)
    let (adjusted_rewards_fast, _) = contract
        .complete_puzzle_in_mode(user, 1, // Puzzle ID
        3, // Time Attack Mode
        100, // Points
        5);

    // 100 base points * 1.25 (mode multiplier) * 1.5 (fast completion bonus) = 187.5 ≈ 187
    assert(adjusted_rewards_fast == 187, 'Time Attack fast rewards incorrect');

    // Test moderate completion in time attack mode
    // Time attack: 25% more rewards + 25% bonus for moderate completion (< 180s)
    set_block_timestamp(2000);
    contract.start_puzzle_in_mode(user, 2, 3); // Different puzzle in Time Attack

    set_block_timestamp(2150); // 150 seconds later (moderate completion)
    let (adjusted_rewards_moderate, _) = contract
        .complete_puzzle_in_mode(user, 2, // Puzzle ID
        3, // Time Attack Mode
        100, // Points
        5);

    // 100 base points * 1.25 (mode multiplier) * 1.25 (moderate completion bonus) = 156.25 ≈ 156
    assert(adjusted_rewards_moderate == 156, 'Time Attack moderate rewards incorrect');
}

#[test]
fn test_earning_achievements() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Create a test user
    let user: ContractAddress = 'TestUser'.try_into().unwrap();

    // Complete 5 puzzles in practice mode to earn the "Practice Makes Perfect" achievement
    for i in 0..5 {
        set_block_timestamp(1000 + i * 100);
        contract.start_puzzle_in_mode(user, i + 1, 1); // Practice mode

        set_block_timestamp(1050 + i * 100);
        contract.complete_puzzle_in_mode(user, i + 1, 1, 100, 5);
    }

    // Check that user earned the achievement
    let user_achievements = contract.get_user_achievements(user);
    assert(user_achievements.len() == 1, 'Should have 1 achievement');

    // Check the specific achievement
    let achievement = contract.get_achievement(*user_achievements.at(0));
    assert(achievement.name == 'Practice Makes Perfect', 'Wrong achievement earned');
}

#[should_panic(expected: ('Only admin can call this',))]
#[test]
fn test_non_admin_cannot_create_game_mode() {
    let (contract_address, _) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Set caller to non-admin user
    let non_admin: ContractAddress = 'NonAdmin'.try_into().unwrap();
    start_cheat_caller_address(contract_address, non_admin);

    // Attempt to create a game mode (should fail)
    contract.create_game_mode('New Mode', GameModeType::Practice, 100, 100, 0);
}

#[should_panic(expected: ('Game mode is disabled',))]
#[test]
fn test_cannot_use_disabled_mode() {
    let (contract_address, admin) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Disable challenge mode
    start_cheat_caller_address(contract_address, admin);
    contract.disable_game_mode(2);

    // Try to start puzzle in disabled mode
    let user: ContractAddress = 'TestUser'.try_into().unwrap();
    contract.start_puzzle_in_mode(user, 1, 2); // Mode 2 = Challenge (now disabled)
}

#[should_panic(expected: ('Invalid mode ID',))]
#[test]
fn test_invalid_mode_id() {
    let (contract_address, _) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Try to get a non-existent mode
    contract.get_game_mode(999);
}

#[should_panic(expected: ('No active session found',))]
#[test]
fn test_complete_without_start() {
    let (contract_address, _) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Try to complete a puzzle without starting it
    let user: ContractAddress = 'TestUser'.try_into().unwrap();
    contract.complete_puzzle_in_mode(user, 1, 1, 100, 5);
}

#[test]
fn test_all_reward_combinations() {
    let (contract_address, _) = setup();
    let contract = IGameModeDispatcher { contract_address };

    // Test all modes with different point values and completion times

    // Practice mode - standard reward
    let practice_normal = contract.calculate_reward_modifier(1, 100, 120);
    assert(practice_normal == 100, 'Practice normal reward wrong');

    // Challenge mode - below threshold
    let challenge_below = contract.calculate_reward_modifier(2, 90, 120);
    assert(challenge_below == 135, 'Challenge below threshold wrong'); // 90 * 1.5 = 135

    // Challenge mode - above threshold
    let challenge_above = contract.calculate_reward_modifier(2, 150, 120);
    assert(challenge_above == 270, 'Challenge above threshold wrong'); // 150 * 1.5 * 1.2 = 270

    // Time Attack - very fast
    let time_attack_fast = contract.calculate_reward_modifier(3, 100, 50);
    assert(time_attack_fast == 187, 'Time Attack fast wrong'); // 100 * 1.25 * 1.5 = 187.5 ≈ 187

    // Time Attack - moderately fast
    let time_attack_moderate = contract.calculate_reward_modifier(3, 100, 120);
    assert(
        time_attack_moderate == 156, 'Time Attack moderate wrong',
    ); // 100 * 1.25 * 1.25 = 156.25 ≈ 156

    // Time Attack - slow
    let time_attack_slow = contract.calculate_reward_modifier(3, 100, 200);
    assert(time_attack_slow == 125, 'Time Attack slow wrong'); // 100 * 1.25 = 125
}


#[test]
fn test_create_game_mode() {
    // Setup
    let admin_address = starknet::contract_address_const::<0x123>();
    let mut state = LogicQuestGameMode::contract_state_for_testing();

    // Deploy contract with admin
    LogicQuestGameMode::constructor(ref state, admin_address);

    // Set caller as admin
    set_contract_address(admin_address);

    // Test creating a new game mode
    let mode_id = IGameMode::create_game_mode(
        ref state,
        'Custom Mode',
        GameModeType::Challenge,
        200, // 2x rewards
        80, // 20% less time
        150 // Points threshold
    );

    // Check mode was created
    let mode = IGameMode::get_game_mode(@state, mode_id);
    assert(mode.name == 'Custom Mode', 'Incorrect mode name');
    assert(mode.reward_multiplier == 200, 'Incorrect reward multiplier');
    assert(mode.time_modifier == 80, 'Incorrect time modifier');
    assert(mode.points_threshold == 150, 'Incorrect points threshold');
    assert(mode.enabled == true, 'Mode should be enabled');
}

#[test]
fn test_default_game_modes() {
    // Setup
    let admin_address = starknet::contract_address_const::<0x123>();
    let mut state = LogicQuestGameMode::contract_state_for_testing();

    // Deploy contract
    LogicQuestGameMode::constructor(ref state, admin_address);

    // Check total number of modes
    let total_modes = IGameMode::get_total_game_modes(@state);
    assert(total_modes == 3, 'Should have 3 default modes');

    // Check Practice mode
    let practice_mode = IGameMode::get_game_mode(@state, 1);
    assert(practice_mode.name == 'Practice', 'Incorrect mode name');

    // Check Challenge mode
    let challenge_mode = IGameMode::get_game_mode(@state, 2);
    assert(challenge_mode.name == 'Challenge', 'Incorrect mode name');

    // Check Time Attack mode
    let time_attack_mode = IGameMode::get_game_mode(@state, 3);
    assert(time_attack_mode.name == 'Time Attack', 'Incorrect mode name');
}

#[test]
fn test_enable_disable_game_mode() {
    // Setup
    let admin_address = starknet::contract_address_const::<0x123>();
    let mut state = LogicQuestGameMode::contract_state_for_testing();

    // Deploy contract
    LogicQuestGameMode::constructor(ref state, admin_address);

    // Set caller as admin
    set_contract_address(admin_address);

    // Disable a mode
    IGameMode::disable_game_mode(ref state, 2); // Disable Challenge mode

    // Check mode is disabled
    let mode = IGameMode::get_game_mode(@state, 2);
    assert(mode.enabled == false, 'Mode should be disabled');

    // Check enabled modes list
    let enabled_modes = IGameMode::get_enabled_game_modes(@state);

    // Should only include modes 1 and 3 (not 2)
    let mut found_1 = false;
    let mut found_2 = false;
    let mut found_3 = false;

    let mut i = 0;
    loop {
        if i >= enabled_modes.len() {
            break;
        }
        let mode_id = *enabled_modes.at(i);
        if mode_id == 1 {
            found_1 = true;
        } else if mode_id == 2 {
            found_2 = true;
        } else if mode_id == 3 {
            found_3 = true;
        }
        i += 1;
    }

    assert(found_1 == true, 'Mode 1 should be enabled');
    assert(found_2 == false, 'Mode 2 should be disabled');
    assert(found_3 == true, 'Mode 3 should be enabled');

    // Re-enable the mode
    IGameMode::enable_game_mode(ref state, 2);

    // Check mode is enabled
    let mode = IGameMode::get_game_mode(@state, 2);
    assert(mode.enabled == true, 'Mode should be enabled');
}

#[test]
fn test_user_progress_and_achievements() {
    // Setup
    let admin_address = starknet::contract_address_const::<0x123>();
    let user_address = starknet::contract_address_const::<0x456>();
    let mut state = LogicQuestGameMode::contract_state_for_testing();

    // Deploy contract
    LogicQuestGameMode::constructor(ref state, admin_address);

    // Set current time
    set_block_timestamp(1000);

    // Start a puzzle in practice mode
    let (time_limit, reward_mult) = IGameMode::start_puzzle_in_mode(
        ref state, user_address, 1, // Puzzle ID
        1 // Practice Mode ID
    );

    // Check time limit adjustment
    assert(time_limit == 300, 'Incorrect adjusted time limit'); // Default with modifier

    // Set later timestamp for completion
    set_block_timestamp(1100); // 100 seconds later

    // Complete the puzzle
    let (adjusted_rewards, achievements) = IGameMode::complete_puzzle_in_mode(
        ref state,
        user_address,
        1, // Puzzle ID
        1, // Practice Mode ID
        100, // Points earned
        5 // Difficulty
    );

    // Check rewards calculation
    assert(
        adjusted_rewards == 100, 'Incorrect adjusted rewards',
    ); // Practice mode has 1x multiplier

    // Check progress
    let progress = IGameMode::get_user_progress(@state, user_address, 1);
    assert(progress.completed_puzzles == 1, 'Should have 1 completed puzzle');
    assert(progress.total_points == 100, 'Should have 100 points');
    assert(progress.highest_difficulty_completed == 5, 'Highest difficulty should be 5');

    // Complete more puzzles to earn an achievement
    for i in 0..4 {
        // Start puzzle
        set_block_timestamp(1200 + i * 100);
        IGameMode::start_puzzle_in_mode(ref state, user_address, 2 + i, 1);

        // Complete puzzle
        set_block_timestamp(1250 + i * 100);
        IGameMode::complete_puzzle_in_mode(ref state, user_address, 2 + i, 1, 100, 5);
    }

    // Check user achievements
    let user_achievements = IGameMode::get_user_achievements(@state, user_address);
    assert(user_achievements.len() == 1, 'Should have earned 1 achievement');
}

#[test]
fn test_reward_modifiers() {
    // Setup
    let admin_address = starknet::contract_address_const::<0x123>();
    let mut state = LogicQuestGameMode::contract_state_for_testing();

    // Deploy contract
    LogicQuestGameMode::constructor(ref state, admin_address);

    // Test Practice mode (normal rewards)
    let practice_rewards = IGameMode::calculate_reward_modifier(@state, 1, 100, 120);
    assert(practice_rewards == 100, 'Practice should give normal rewards');

    // Test Challenge mode (with threshold exceeded)
    let challenge_rewards = IGameMode::calculate_reward_modifier(@state, 2, 150, 120);
    assert(challenge_rewards == 270, 'Challenge rewards incorrect'); // 150 * 1.5 * 1.2 = 270

    // Test Time Attack mode (fast completion)
    let time_attack_rewards_fast = IGameMode::calculate_reward_modifier(@state, 3, 100, 50);
    assert(
        time_attack_rewards_fast == 187, 'Time Attack fast rewards incorrect',
    ); // 100 * 1.25 * 1.5 = 187

    // Test Time Attack mode (moderate completion)
    let time_attack_rewards_moderate = IGameMode::calculate_reward_modifier(@state, 3, 100, 120);
    assert(
        time_attack_rewards_moderate == 156, 'Time Attack moderate rewards incorrect',
    ); // 100 * 1.25 * 1.25 = 156
}
