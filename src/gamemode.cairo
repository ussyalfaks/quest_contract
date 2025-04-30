#[starknet::contract]
pub mod LogicQuestGameMode {
    // Imports
    use core::array::ArrayTrait;
    use core::clone::Clone;
    use core::dict::Dict;
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};
    use quest_contract::base::types::{
        GameMode, GameModeAchievement, GameModeType, UserGameModeProgress,
    };
    use quest_contract::interfaces::igamemode::IGameMode;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameModeCreated: GameModeCreated,
        GameModeUpdated: GameModeUpdated,
        GameModeStatusChanged: GameModeStatusChanged,
        AchievementCreated: AchievementCreated,
        PuzzleStarted: PuzzleStarted,
        PuzzleCompleted: PuzzleCompleted,
        AchievementEarned: AchievementEarned,
    }

    #[derive(Drop, starknet::Event)]
    struct GameModeCreated {
        #[key]
        mode_id: u32,
        name: felt252,
        mode_type: GameModeType,
    }

    #[derive(Drop, starknet::Event)]
    struct GameModeUpdated {
        #[key]
        mode_id: u32,
        name: felt252,
        reward_multiplier: u32,
        time_modifier: u32,
        points_threshold: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct GameModeStatusChanged {
        #[key]
        mode_id: u32,
        enabled: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct AchievementCreated {
        #[key]
        achievement_id: u32,
        #[key]
        mode_id: u32,
        name: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleStarted {
        #[key]
        user: ContractAddress,
        #[key]
        puzzle_id: u32,
        #[key]
        mode_id: u32,
        adjusted_time_limit: u32,
        reward_multiplier: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleCompleted {
        #[key]
        user: ContractAddress,
        #[key]
        puzzle_id: u32,
        #[key]
        mode_id: u32,
        base_points: u32,
        adjusted_rewards: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct AchievementEarned {
        #[key]
        user: ContractAddress,
        #[key]
        achievement_id: u32,
        #[key]
        mode_id: u32,
        reward_points: u32,
    }

    // Contract storage
    #[storage]
    struct Storage {
        // Admin management
        admin: ContractAddress,
        // Game modes storage
        game_modes_count: u32,
        game_modes: Map<u32, GameMode>,
        enabled_game_modes: Map<u32, bool>, // Maps mode_id to enabled status
        // Achievements storage
        achievements_count: u32,
        achievements: Map<u32, GameModeAchievement>,
        mode_achievement_count: Map<u32, u32>, // Maps mode_id to achievement count
        mode_achievements: Map<(u32, u32), u32>, // Maps (mode_id, index) to achievement_id
        // User progress
        user_progress: Map<
            (ContractAddress, u32), UserGameModeProgress,
        >, // Maps (user, mode_id) to progress
        user_achievement_count: Map<ContractAddress, u32>, // Maps user to achievement count
        user_achievements: Map<(ContractAddress, u32), u32>, // Maps (user, index) to achievement_id
        // Active sessions
        active_sessions: Map<
            (ContractAddress, u32, u32), u64,
        > // Maps (user, puzzle_id, mode_id) to start_timestamp
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress) {
        self.admin.write(admin_address);
        self.game_modes_count.write(0);
        self.achievements_count.write(0);

        // Create default game modes
        self._create_default_game_modes(ref self);
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }
    }

    // Implementation
    #[abi(embed_v0)]
    impl GameModeImpl of IGameMode<ContractState> {
        // Admin functions
        fn create_game_mode(
            ref self: ContractState,
            name: felt252,
            mode_type: GameModeType,
            reward_multiplier: u32,
            time_modifier: u32,
            points_threshold: u32,
        ) -> u32 {
            self.only_admin();

            // Validate inputs
            assert(reward_multiplier > 0, 'Reward multiplier must be positive');
            assert(time_modifier > 0, 'Time modifier must be positive');

            let mode_id = self.game_modes_count.read() + 1;
            let current_timestamp = starknet::get_block_timestamp();

            // Create new game mode
            let new_mode = GameMode {
                id: mode_id,
                name: name,
                mode_type: mode_type,
                reward_multiplier: reward_multiplier,
                time_modifier: time_modifier,
                points_threshold: points_threshold,
                enabled: true,
                creation_timestamp: current_timestamp,
            };

            // Store the game mode
            self.game_modes.write(mode_id, new_mode);
            self.game_modes_count.write(mode_id);

            // Add to enabled modes
            self.enabled_game_modes.write(mode_id, true);

            // Emit event
            self.emit(Event::GameModeCreated(GameModeCreated { mode_id, name, mode_type }));

            mode_id
        }

        fn update_game_mode(
            ref self: ContractState,
            mode_id: u32,
            name: felt252,
            reward_multiplier: u32,
            time_modifier: u32,
            points_threshold: u32,
        ) {
            self.only_admin();

            // Validate inputs
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            assert(reward_multiplier > 0, 'Reward multiplier must be positive');
            assert(time_modifier > 0, 'Time modifier must be positive');

            // Get and update game mode
            let mut mode = self.game_modes.read(mode_id);
            mode.name = name;
            mode.reward_multiplier = reward_multiplier;
            mode.time_modifier = time_modifier;
            mode.points_threshold = points_threshold;

            // Store the updated game mode
            self.game_modes.write(mode_id, mode);

            // Emit event
            self
                .emit(
                    Event::GameModeUpdated(
                        GameModeUpdated {
                            mode_id, name, reward_multiplier, time_modifier, points_threshold,
                        },
                    ),
                );
        }

        fn enable_game_mode(ref self: ContractState, mode_id: u32) {
            self.only_admin();
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');

            let mut mode = self.game_modes.read(mode_id);
            mode.enabled = true;
            self.game_modes.write(mode_id, mode);

            // Update enabled status
            self.enabled_game_modes.write(mode_id, true);

            // Emit event
            self
                .emit(
                    Event::GameModeStatusChanged(GameModeStatusChanged { mode_id, enabled: true }),
                );
        }

        fn disable_game_mode(ref self: ContractState, mode_id: u32) {
            self.only_admin();
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');

            let mut mode = self.game_modes.read(mode_id);
            mode.enabled = false;
            self.game_modes.write(mode_id, mode);

            // Update enabled status
            self.enabled_game_modes.write(mode_id, false);

            // Emit event
            self
                .emit(
                    Event::GameModeStatusChanged(GameModeStatusChanged { mode_id, enabled: false }),
                );
        }

        // Achievement management
        fn create_achievement(
            ref self: ContractState,
            mode_id: u32,
            name: felt252,
            description: felt252,
            condition_type: u8,
            condition_value: u32,
            reward_points: u32,
        ) -> u32 {
            self.only_admin();

            // Validate inputs
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            assert(condition_type >= 1 && condition_type <= 3, 'Invalid condition type');
            assert(reward_points > 0, 'Reward points must be positive');

            let achievement_id = self.achievements_count.read() + 1;

            // Create new achievement
            let new_achievement = GameModeAchievement {
                id: achievement_id,
                mode_id: mode_id,
                name: name,
                description: description,
                condition_type: condition_type,
                condition_value: condition_value,
                reward_points: reward_points,
            };

            // Store the achievement
            self.achievements.write(achievement_id, new_achievement);
            self.achievements_count.write(achievement_id);

            // Add to mode achievements
            let achievement_count = self.mode_achievement_count.read(mode_id);
            let new_count = achievement_count + 1;
            self.mode_achievements.write((mode_id, achievement_count), achievement_id);
            self.mode_achievement_count.write(mode_id, new_count);

            // Emit event
            self
                .emit(
                    Event::AchievementCreated(AchievementCreated { achievement_id, mode_id, name }),
                );

            achievement_id
        }

        // User gameplay functions
        fn start_puzzle_in_mode(
            ref self: ContractState, user: ContractAddress, puzzle_id: u32, mode_id: u32,
        ) -> (u32, u32) {
            // Validate inputs
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            let mode = self.game_modes.read(mode_id);
            assert(mode.enabled, 'Game mode is disabled');

            let current_timestamp = starknet::get_block_timestamp();

            // Store start time for the session
            self.active_sessions.write((user, puzzle_id, mode_id), current_timestamp);

            // Calculate adjusted time limit based on mode
            let adjusted_time_limit = self
                ._calculate_adjusted_time(mode_id, 0); // Time will be passed from quest contract

            // Emit event
            self
                .emit(
                    Event::PuzzleStarted(
                        PuzzleStarted {
                            user,
                            puzzle_id,
                            mode_id,
                            adjusted_time_limit,
                            reward_multiplier: mode.reward_multiplier,
                        },
                    ),
                );

            (adjusted_time_limit, mode.reward_multiplier)
        }

        fn complete_puzzle_in_mode(
            ref self: ContractState,
            user: ContractAddress,
            puzzle_id: u32,
            mode_id: u32,
            points_earned: u32,
            difficulty: u8,
        ) -> (u32, Array<u32>) {
            // Validate inputs
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            let mode = self.game_modes.read(mode_id);
            assert(mode.enabled, 'Game mode is disabled');

            // Get session start time
            let start_timestamp = self.active_sessions.read((user, puzzle_id, mode_id));
            assert(start_timestamp > 0, 'No active session found');

            let current_timestamp = starknet::get_block_timestamp();
            let time_taken = current_timestamp - start_timestamp;

            // Calculate adjusted rewards
            let base_rewards = points_earned;
            let adjusted_rewards = self
                .calculate_reward_modifier(mode_id, points_earned, time_taken);

            // Update user progress
            let mut progress = self._get_or_create_progress(ref self, user, mode_id);
            progress.completed_puzzles += 1;
            progress.total_points += adjusted_rewards;
            if difficulty > progress.highest_difficulty_completed {
                progress.highest_difficulty_completed = difficulty;
            }
            progress.last_played_timestamp = current_timestamp;
            self.user_progress.write((user, mode_id), progress);

            // Clear session
            self.active_sessions.write((user, puzzle_id, mode_id), 0);

            // Check for earned achievements
            let earned_achievements = self._check_achievements(ref self, user, mode_id);

            // Emit event
            self
                .emit(
                    Event::PuzzleCompleted(
                        PuzzleCompleted {
                            user, puzzle_id, mode_id, base_points: base_rewards, adjusted_rewards,
                        },
                    ),
                );

            (adjusted_rewards, earned_achievements)
        }

        // Query functions
        fn get_game_mode(self: @ContractState, mode_id: u32) -> GameMode {
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            self.game_modes.read(mode_id)
        }

        fn get_total_game_modes(self: @ContractState) -> u32 {
            self.game_modes_count.read()
        }

        fn get_enabled_game_modes(self: @ContractState) -> Array<u32> {
            let total_modes = self.game_modes_count.read();
            let mut enabled_modes = ArrayTrait::new();

            let mut i: u32 = 1;
            loop {
                if i > total_modes {
                    break;
                }

                if self.enabled_game_modes.read(i) {
                    enabled_modes.append(i);
                }

                i += 1;
            }

            enabled_modes
        }

        fn get_user_progress(
            self: @ContractState, user: ContractAddress, mode_id: u32,
        ) -> UserGameModeProgress {
            self.user_progress.read((user, mode_id))
        }

        fn get_achievement(self: @ContractState, achievement_id: u32) -> GameModeAchievement {
            assert(achievement_id <= self.achievements_count.read(), 'Invalid achievement ID');
            self.achievements.read(achievement_id)
        }

        fn get_mode_achievements(self: @ContractState, mode_id: u32) -> Array<u32> {
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');

            let achievement_count = self.mode_achievement_count.read(mode_id);
            let mut achievements = ArrayTrait::new();

            let mut i: u32 = 0;
            loop {
                if i >= achievement_count {
                    break;
                }

                let achievement_id = self.mode_achievements.read((mode_id, i));
                achievements.append(achievement_id);

                i += 1;
            }

            achievements
        }

        fn get_user_achievements(self: @ContractState, user: ContractAddress) -> Array<u32> {
            let achievement_count = self.user_achievement_count.read(user);
            let mut achievements = ArrayTrait::new();

            let mut i: u32 = 0;
            loop {
                if i >= achievement_count {
                    break;
                }

                let achievement_id = self.user_achievements.read((user, i));
                achievements.append(achievement_id);

                i += 1;
            }

            achievements
        }

        fn calculate_reward_modifier(
            self: @ContractState, mode_id: u32, points: u32, time_taken: u32,
        ) -> u32 {
            assert(mode_id <= self.game_modes_count.read(), 'Invalid mode ID');
            let mode = self.game_modes.read(mode_id);

            // Apply base multiplier
            let mut modified_points = (points * mode.reward_multiplier) / 100;

            // Apply mode-specific modifiers
            match mode.mode_type {
                GameModeType::Practice => {
                    // Practice mode has normal rewards
                    modified_points
                },
                GameModeType::Challenge => {
                    // Challenge mode offers bonus for exceeding threshold
                    if points > mode.points_threshold {
                        // Add 20% bonus for exceeding threshold
                        modified_points = (modified_points * 120) / 100;
                    }
                    modified_points
                },
                GameModeType::TimeAttack => {
                    // Time attack offers bonus for fast completion
                    // The faster the completion, the higher the bonus
                    // Using a simple formula where time < 60s gives max bonus
                    if time_taken < 60 {
                        // 50% bonus for very fast completion
                        modified_points = (modified_points * 150) / 100;
                    } else if time_taken < 180 {
                        // 25% bonus for moderately fast completion
                        modified_points = (modified_points * 125) / 100;
                    }
                    modified_points
                },
            }
        }
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _create_default_game_modes(ref self: ContractState) {
            // Create Practice mode
            let practice_id = self.game_modes_count.read() + 1;
            let practice_mode = GameMode {
                id: practice_id,
                name: 'Practice',
                mode_type: GameModeType::Practice,
                reward_multiplier: 100, // Normal rewards (1x)
                time_modifier: 150, // 50% more time
                points_threshold: 0, // No threshold
                enabled: true,
                creation_timestamp: starknet::get_block_timestamp(),
            };
            self.game_modes.write(practice_id, practice_mode);
            self.enabled_game_modes.write(practice_id, true);

            // Create Challenge mode
            let challenge_id = practice_id + 1;
            let challenge_mode = GameMode {
                id: challenge_id,
                name: 'Challenge',
                mode_type: GameModeType::Challenge,
                reward_multiplier: 150, // 50% more rewards
                time_modifier: 100, // Normal time
                points_threshold: 100, // Threshold for bonus
                enabled: true,
                creation_timestamp: starknet::get_block_timestamp(),
            };
            self.game_modes.write(challenge_id, challenge_mode);
            self.enabled_game_modes.write(challenge_id, true);

            // Create Time Attack mode
            let time_attack_id = challenge_id + 1;
            let time_attack_mode = GameMode {
                id: time_attack_id,
                name: 'Time Attack',
                mode_type: GameModeType::TimeAttack,
                reward_multiplier: 125, // 25% more rewards
                time_modifier: 75, // 25% less time
                points_threshold: 50, // Lower threshold for completion
                enabled: true,
                creation_timestamp: starknet::get_block_timestamp(),
            };
            self.game_modes.write(time_attack_id, time_attack_mode);
            self.enabled_game_modes.write(time_attack_id, true);

            // Set game modes count
            self.game_modes_count.write(time_attack_id);

            // Create default achievements for each mode
            self._create_default_achievements(ref self, practice_id, challenge_id, time_attack_id);
        }

        fn _create_default_achievements(
            ref self: ContractState, practice_id: u32, challenge_id: u32, time_attack_id: u32,
        ) {
            // Practice mode achievements
            let achievement_id = self.achievements_count.read() + 1;
            let practice_complete_5 = GameModeAchievement {
                id: achievement_id,
                mode_id: practice_id,
                name: 'Practice Makes Perfect',
                description: 'Complete 5 puzzles in Practice mode',
                condition_type: 1, // Puzzles completed
                condition_value: 5,
                reward_points: 50,
            };
            self.achievements.write(achievement_id, practice_complete_5);

            // Add to practice mode achievements
            let practice_ach_count = self.mode_achievement_count.read(practice_id);
            self.mode_achievements.write((practice_id, practice_ach_count), achievement_id);
            self.mode_achievement_count.write(practice_id, practice_ach_count + 1);

            // Challenge mode achievements
            let challenge_achievement_id = achievement_id + 1;
            let challenge_complete_3 = GameModeAchievement {
                id: challenge_achievement_id,
                mode_id: challenge_id,
                name: 'Challenge Accepted',
                description: 'Complete 3 puzzles in Challenge mode',
                condition_type: 1, // Puzzles completed
                condition_value: 3,
                reward_points: 100,
            };
            self.achievements.write(challenge_achievement_id, challenge_complete_3);

            let challenge_achievement_id2 = challenge_achievement_id + 1;
            let challenge_points_500 = GameModeAchievement {
                id: challenge_achievement_id2,
                mode_id: challenge_id,
                name: 'Elite Challenger',
                description: 'Earn 500 points in Challenge mode',
                condition_type: 2, // Points earned
                condition_value: 500,
                reward_points: 200,
            };
            self.achievements.write(challenge_achievement_id2, challenge_points_500);

            // Add to challenge mode achievements
            let challenge_ach_count = self.mode_achievement_count.read(challenge_id);
            self
                .mode_achievements
                .write((challenge_id, challenge_ach_count), challenge_achievement_id);
            self.mode_achievement_count.write(challenge_id, challenge_ach_count + 1);
            self
                .mode_achievements
                .write((challenge_id, challenge_ach_count + 1), challenge_achievement_id2);
            self.mode_achievement_count.write(challenge_id, challenge_ach_count + 2);

            // Time Attack mode achievements
            let time_attack_achievement_id = challenge_achievement_id2 + 1;
            let time_attack_complete_3 = GameModeAchievement {
                id: time_attack_achievement_id,
                mode_id: time_attack_id,
                name: 'Speed Demon',
                description: 'Complete 3 puzzles in Time Attack mode',
                condition_type: 1, // Puzzles completed
                condition_value: 3,
                reward_points: 150,
            };
            self.achievements.write(time_attack_achievement_id, time_attack_complete_3);

            let time_attack_achievement_id2 = time_attack_achievement_id + 1;
            let time_attack_difficulty_7 = GameModeAchievement {
                id: time_attack_achievement_id2,
                mode_id: time_attack_id,
                name: 'Race Against Time',
                description: 'Complete a difficulty 7+ puzzle in Time Attack mode',
                condition_type: 3, // Difficulty reached
                condition_value: 7,
                reward_points: 250,
            };
            self.achievements.write(time_attack_achievement_id2, time_attack_difficulty_7);

            // Add to time attack mode achievements
            let time_attack_ach_count = self.mode_achievement_count.read(time_attack_id);
            self
                .mode_achievements
                .write((time_attack_id, time_attack_ach_count), time_attack_achievement_id);
            self.mode_achievement_count.write(time_attack_id, time_attack_ach_count + 1);
            self
                .mode_achievements
                .write((time_attack_id, time_attack_ach_count + 1), time_attack_achievement_id2);
            self.mode_achievement_count.write(time_attack_id, time_attack_ach_count + 2);

            // Update achievement count
            self.achievements_count.write(time_attack_achievement_id2);
        }

        fn _get_or_create_progress(
            ref self: ContractState, user: ContractAddress, mode_id: u32,
        ) -> UserGameModeProgress {
            let progress = self.user_progress.read((user, mode_id));

            // If this is a new user for this mode, create progress
            if progress.user.is_zero() {
                return UserGameModeProgress {
                    user: user,
                    mode_id: mode_id,
                    completed_puzzles: 0,
                    total_points: 0,
                    highest_difficulty_completed: 0,
                    last_played_timestamp: 0,
                };
            }

            progress
        }

        fn _check_achievements(
            ref self: ContractState, user: ContractAddress, mode_id: u32,
        ) -> Array<u32> {
            let progress = self.user_progress.read((user, mode_id));
            let achievement_count = self.mode_achievement_count.read(mode_id);
            let mut earned_achievements = ArrayTrait::new();
            let user_ach_count = self.user_achievement_count.read(user);

            // Check each achievement for the mode
            let mut i: u32 = 0;
            loop {
                if i >= achievement_count {
                    break;
                }

                let achievement_id = self.mode_achievements.read((mode_id, i));
                let achievement = self.achievements.read(achievement_id);

                // Check if user already has this achievement
                let mut already_earned = false;
                let mut j: u32 = 0;
                loop {
                    if j >= user_ach_count {
                        break;
                    }

                    if self.user_achievements.read((user, j)) == achievement_id {
                        already_earned = true;
                        break;
                    }

                    j += 1;
                }

                if !already_earned {
                    // Check if criteria met based on condition type
                    let mut criteria_met = false;

                    if achievement.condition_type == 1
                        && progress.completed_puzzles >= achievement.condition_value {
                        // Puzzles completed condition
                        criteria_met = true;
                    } else if achievement.condition_type == 2
                        && progress.total_points >= achievement.condition_value {
                        // Points earned condition
                        criteria_met = true;
                    } else if achievement.condition_type == 3
                        && progress
                            .highest_difficulty_completed >= achievement
                            .condition_value
                            .try_into()
                            .unwrap() {
                        // Difficulty reached condition
                        criteria_met = true;
                    }

                    if criteria_met {
                        // Award the achievement
                        let new_user_ach_count = user_ach_count + 1;
                        self.user_achievements.write((user, user_ach_count), achievement_id);
                        self.user_achievement_count.write(user, new_user_ach_count);
                        earned_achievements.append(achievement_id);

                        // Emit event
                        self
                            .emit(
                                Event::AchievementEarned(
                                    AchievementEarned {
                                        user,
                                        achievement_id,
                                        mode_id,
                                        reward_points: achievement.reward_points,
                                    },
                                ),
                            );
                    }
                }

                i += 1;
            }

            earned_achievements
        }

        fn _calculate_adjusted_time(self: @ContractState, mode_id: u32, original_time: u32) -> u32 {
            let mode = self.game_modes.read(mode_id);

            if original_time == 0 {
                // Default time if not specified
                return 300; // 5 minutes
            }

            // Apply time modifier from game mode
            (original_time * mode.time_modifier) / 100
        }
    }
}
