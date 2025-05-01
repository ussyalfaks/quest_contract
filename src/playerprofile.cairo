#[starknet::contract]
pub mod LogicQuestPlayerProfile {
    // Imports
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};
    use iplayerprofile::IPlayerProfile;
    use quest_contract::base::types::{LevelUnlock, PlayerProfile, PuzzleStats};
    use quest_contract::interfaces::iplayerprofile;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};


    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ProfileCreated: ProfileCreated,
        ProfileUpdated: ProfileUpdated,
        PuzzleCompleted: PuzzleCompleted,
        LevelUnlocked: LevelUnlocked,
        StreakUpdated: StreakUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct ProfileCreated {
        #[key]
        player: ContractAddress,
        player_id: u32,
        username: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ProfileUpdated {
        #[key]
        player: ContractAddress,
        username: felt252,
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct PuzzleCompleted {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        score: u32,
        time_taken: u64,
        total_puzzles_solved: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct LevelUnlocked {
        #[key]
        player: ContractAddress,
        #[key]
        level_id: u32,
        unlock_method: felt252 // "achievement" or "token"
    }

    #[derive(Drop, starknet::Event)]
    struct StreakUpdated {
        #[key]
        player: ContractAddress,
        streak_days: u32,
    }

    // Contract storage
    #[storage]
    struct Storage {
        // Admin management
        admin: ContractAddress,
        // Player profiles
        players_count: u32,
        player_profiles: Map<ContractAddress, PlayerProfile>,
        player_ids: Map<u32, ContractAddress>,
        // Puzzle statistics
        player_puzzle_stats: Map<
            (ContractAddress, u32), PuzzleStats,
        >, // Maps (player, puzzle_id) to stats
        // Level unlocking
        levels_count: u32,
        level_unlocks: Map<u32, LevelUnlock>, // Maps level_id to unlock requirements
        player_unlocked_levels: Map<
            (ContractAddress, u32), bool,
        >, // Maps (player, level_id) to unlock status
        player_level_count: Map<ContractAddress, u32>, // Maps player to number of unlocked levels
        player_levels: Map<(ContractAddress, u32), u32>, // Maps (player, index) to level_id
        // Token interface
        token_contract: ContractAddress,
        // Streak tracking
        last_day_timestamp: Map<
            ContractAddress, u64,
        > // Maps player to last day timestamp (for streak)
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState, admin_address: ContractAddress, token_contract: ContractAddress,
    ) {
        self.admin.write(admin_address);
        self.token_contract.write(token_contract);
        self.players_count.write(0);
        self.levels_count.write(0);

        // Create default levels
        self._create_default_levels();
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_player_or_admin(self: @ContractState, player: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == player || caller == self.admin.read(), 'Not authorized');
        }

        fn profile_exists(self: @ContractState, player: ContractAddress) -> PlayerProfile {
            let profile = self.player_profiles.read(player);
            assert(!profile.address.is_zero(), 'Profile does not exist');
            profile
        }
    }

    // Implementation
    #[abi(embed_v0)]
    impl PlayerProfileImpl of IPlayerProfile<ContractState> {
        // Player profile management
        fn create_profile(ref self: ContractState, username: felt252) -> u32 {
            let caller = get_caller_address();
            let existing_profile = self.player_profiles.read(caller);

            // Check if profile already exists
            assert(existing_profile.address.is_zero(), 'Profile already exists');

            // Create new profile
            let player_id = self.players_count.read() + 1;
            let current_timestamp = get_block_timestamp();

            let new_profile = PlayerProfile {
                player_id: player_id,
                address: caller,
                username: username,
                level: 1, // Start at level 1
                total_score: 0,
                puzzles_solved: 0,
                total_time_spent: 0,
                streak_days: 0,
                last_active_timestamp: current_timestamp,
                creation_timestamp: current_timestamp,
            };

            // Store the profile
            self.player_profiles.write(caller, new_profile);
            self.player_ids.write(player_id, caller);
            self.players_count.write(player_id);

            // Unlock the first level by default
            self.player_unlocked_levels.write((caller, 1), true);
            self.player_level_count.write(caller, 1);
            self.player_levels.write((caller, 0), 1); // Index 0 -> Level 1

            // Emit event
            self
                .emit(
                    Event::ProfileCreated(
                        ProfileCreated {
                            player: caller, player_id, username, timestamp: current_timestamp,
                        },
                    ),
                );

            player_id
        }

        fn update_profile(ref self: ContractState, username: felt252) {
            let caller = get_caller_address();
            let profile = self.profile_exists(caller);

            // Create updated profile
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: username,
                level: profile.level,
                total_score: profile.total_score,
                puzzles_solved: profile.puzzles_solved,
                total_time_spent: profile.total_time_spent,
                streak_days: profile.streak_days,
                last_active_timestamp: get_block_timestamp(),
                creation_timestamp: profile.creation_timestamp,
            };

            // Store updated profile
            self.player_profiles.write(caller, updated_profile);

            // Emit event
            self.emit(Event::ProfileUpdated(ProfileUpdated { player: caller, username }));
        }

        fn get_profile(self: @ContractState, player: ContractAddress) -> PlayerProfile {
            self.profile_exists(player)
        }

        // Progression tracking
        fn record_puzzle_completion(
            ref self: ContractState, puzzle_id: u32, score: u32, time_taken: u64,
        ) {
            let caller = get_caller_address();
            let profile = self.profile_exists(caller);
            let current_timestamp = get_block_timestamp();

            // Create a mutable copy of the profile
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: profile.username,
                level: profile.level,
                total_score: profile.total_score + score,
                puzzles_solved: profile.puzzles_solved + 1,
                total_time_spent: profile.total_time_spent + time_taken,
                streak_days: profile.streak_days,
                last_active_timestamp: current_timestamp,
                creation_timestamp: profile.creation_timestamp,
            };

            // Update puzzle stats
            let mut puzzle_stats = self.player_puzzle_stats.read((caller, puzzle_id));

            if puzzle_stats.player.is_zero() {
                // First attempt for this puzzle
                puzzle_stats =
                    PuzzleStats {
                        puzzle_id: puzzle_id,
                        player: caller,
                        attempts: 1,
                        best_score: score,
                        best_time: time_taken,
                        last_completion_timestamp: current_timestamp,
                    };
            } else {
                // Update existing stats
                puzzle_stats.attempts += 1;
                puzzle_stats.last_completion_timestamp = current_timestamp;

                // Update best score if current score is better
                if score > puzzle_stats.best_score {
                    puzzle_stats.best_score = score;
                }

                // Update best time if current time is better
                if time_taken < puzzle_stats.best_time {
                    puzzle_stats.best_time = time_taken;
                }
            }

            // Check and update streak
            self._update_streak(caller, current_timestamp);

            // Update level based on puzzles solved
            self._update_level(caller, updated_profile.puzzles_solved);

            // Store updated profile and stats
            self.player_profiles.write(caller, updated_profile);
            self.player_puzzle_stats.write((caller, puzzle_id), puzzle_stats);

            // Emit event
            self
                .emit(
                    Event::PuzzleCompleted(
                        PuzzleCompleted {
                            player: caller,
                            puzzle_id,
                            score,
                            time_taken,
                            total_puzzles_solved: updated_profile.puzzles_solved,
                        },
                    ),
                );
        }

        fn get_puzzle_stats(self: @ContractState, puzzle_id: u32) -> PuzzleStats {
            let caller = get_caller_address();
            self.player_puzzle_stats.read((caller, puzzle_id))
        }

        fn get_player_level(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.level
        }

        // Level unlocking
        fn unlock_level_with_achievement(
            ref self: ContractState, level_id: u32, achievement_id: u32,
        ) {
            let caller = get_caller_address();
            let _profile = self.profile_exists(caller);

            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');
            let level = self.level_unlocks.read(level_id);

            // Check if already unlocked
            let is_unlocked = self.player_unlocked_levels.read((caller, level_id));
            assert(!is_unlocked, 'Level already unlocked');

            // Verify achievement requirement
            assert(level.achievement_requirement > 0, 'No achievement requirement');
            assert(achievement_id == level.achievement_requirement, 'Wrong achievement');

            // Check prerequisite level
            if level.prerequisite_level > 0 {
                let prereq_unlocked = self
                    .player_unlocked_levels
                    .read((caller, level.prerequisite_level));
                assert(prereq_unlocked, 'Prerequisite level not unlocked');
            }

            // Unlock the level
            self._unlock_level(caller, level_id, 'ach'); // Short string literal
        }

        fn unlock_level_with_tokens(ref self: ContractState, level_id: u32, token_amount: u256) {
            let caller = get_caller_address();
            let _profile = self.profile_exists(caller);

            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');
            let level = self.level_unlocks.read(level_id);

            // Check if already unlocked
            let is_unlocked = self.player_unlocked_levels.read((caller, level_id));
            assert(!is_unlocked, 'Level already unlocked');

            // Verify token requirement
            assert(level.token_requirement > 0, 'No token requirement');
            assert(token_amount >= level.token_requirement, 'Insufficient tokens');

            // Check prerequisite level
            if level.prerequisite_level > 0 {
                let prereq_unlocked = self
                    .player_unlocked_levels
                    .read((caller, level.prerequisite_level));
                assert(prereq_unlocked, 'Prerequisite level not unlocked');
            }

            // TODO: Transfer tokens from caller to contract
            // This would require integration with the token contract
            // For now, we'll just unlock the level

            // Unlock the level
            self._unlock_level(caller, level_id, 'tok'); // Short string literal
        }

        fn is_level_unlocked(self: @ContractState, player: ContractAddress, level_id: u32) -> bool {
            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');

            self.player_unlocked_levels.read((player, level_id))
        }

        fn get_unlocked_levels(self: @ContractState, player: ContractAddress) -> Array<u32> {
            let _profile = self.profile_exists(player);
            let level_count = self.player_level_count.read(player);

            let mut unlocked_levels = ArrayTrait::new();
            let mut i: u32 = 0;

            // Collect all unlocked levels
            while i != level_count {
                let level_id = self.player_levels.read((player, i));
                unlocked_levels.append(level_id);

                i += 1;
            }

            unlocked_levels
        }

        // Statistics
        fn get_total_puzzles_solved(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.puzzles_solved
        }

        fn get_average_completion_time(self: @ContractState, player: ContractAddress) -> u64 {
            let profile = self.profile_exists(player);

            if profile.puzzles_solved == 0 {
                return 0;
            }

            profile.total_time_spent / profile.puzzles_solved.into()
        }

        fn get_current_streak(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.streak_days
        }

        fn get_player_statistics(
            self: @ContractState, player: ContractAddress,
        ) -> (u32, u64, u32, u32) {
            let profile = self.profile_exists(player);
            let avg_time = if profile.puzzles_solved == 0 {
                0
            } else {
                profile.total_time_spent / profile.puzzles_solved.into()
            };

            (profile.puzzles_solved, avg_time, profile.streak_days, profile.total_score)
        }
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _create_default_levels(ref self: ContractState) {
            // Level 1 (Starting level)
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Beg', // Shortened string literal
                description: 'Start', // Shortened string literal
                achievement_requirement: 0, // No achievement required
                token_requirement: 0, // No tokens required
                prerequisite_level: 0, // No prerequisite
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 2
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Int', // Shortened string literal
                description: 'Lvl2', // Shortened string literal
                achievement_requirement: 1, // Achievement ID 1
                token_requirement: 100, // 100 tokens
                prerequisite_level: 1, // Requires Level 1
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 3
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Adv', // Shortened string literal
                description: 'Lvl3', // Shortened string literal
                achievement_requirement: 2, // Achievement ID 2
                token_requirement: 250, // 250 tokens
                prerequisite_level: 2, // Requires Level 2
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 4
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Exp', // Shortened string literal
                description: 'Lvl4', // Shortened string literal
                achievement_requirement: 3, // Achievement ID 3
                token_requirement: 500, // 500 tokens
                prerequisite_level: 3, // Requires Level 3
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 5
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Mas', // Shortened string literal
                description: 'Lvl5', // Shortened string literal
                achievement_requirement: 4, // Achievement ID 4
                token_requirement: 1000, // 1000 tokens
                prerequisite_level: 4, // Requires Level 4
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);
        }

        fn _unlock_level(
            ref self: ContractState, player: ContractAddress, level_id: u32, unlock_method: felt252,
        ) {
            // Mark level as unlocked
            self.player_unlocked_levels.write((player, level_id), true);

            // Add to player's unlocked levels
            let level_count = self.player_level_count.read(player);
            self.player_levels.write((player, level_count), level_id);
            self.player_level_count.write(player, level_count + 1);

            // Emit event
            self.emit(Event::LevelUnlocked(LevelUnlocked { player, level_id, unlock_method }));
        }

        fn _update_streak(
            ref self: ContractState, player: ContractAddress, current_timestamp: u64,
        ) {
            let last_day = self.last_day_timestamp.read(player);
            let profile = self.player_profiles.read(player);

            // Calculate day difference (86400 seconds in a day)
            let day_diff = if last_day == 0 {
                0 // First activity
            } else {
                (current_timestamp - last_day) / 86400
            };

            let new_streak = if last_day == 0 || day_diff == 0 {
                // First activity or same day, no streak change
                profile.streak_days
            } else if day_diff == 1 {
                // Next consecutive day, increase streak
                profile.streak_days + 1
            } else {
                // Streak broken
                1 // Reset to 1 (today)
            };

            // Only emit event if streak changed
            if new_streak != profile.streak_days {
                self.emit(Event::StreakUpdated(StreakUpdated { player, streak_days: new_streak }));
            }

            // Update last day timestamp (normalize to start of day)
            let day_start = current_timestamp - (current_timestamp % 86400);
            self.last_day_timestamp.write(player, day_start);

            // Update profile with new streak
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: profile.username,
                level: profile.level,
                total_score: profile.total_score,
                puzzles_solved: profile.puzzles_solved,
                total_time_spent: profile.total_time_spent,
                streak_days: new_streak,
                last_active_timestamp: profile.last_active_timestamp,
                creation_timestamp: profile.creation_timestamp,
            };
            self.player_profiles.write(player, updated_profile);
        }

        fn _update_level(ref self: ContractState, player: ContractAddress, puzzles_solved: u32) {
            let profile = self.player_profiles.read(player);

            // Simple level progression based on puzzles solved
            let new_level = if puzzles_solved < 5 {
                1 // Beginner
            } else if puzzles_solved < 15 {
                2 // Intermediate
            } else if puzzles_solved < 30 {
                3 // Advanced
            } else if puzzles_solved < 50 {
                4 // Expert
            } else {
                5 // Master
            };

            // Update level if increased
            if new_level > profile.level {
                let updated_profile = PlayerProfile {
                    player_id: profile.player_id,
                    address: profile.address,
                    username: profile.username,
                    level: new_level,
                    total_score: profile.total_score,
                    puzzles_solved: profile.puzzles_solved,
                    total_time_spent: profile.total_time_spent,
                    streak_days: profile.streak_days,
                    last_active_timestamp: profile.last_active_timestamp,
                    creation_timestamp: profile.creation_timestamp,
                };
                self.player_profiles.write(player, updated_profile);
            }
        }
    }
}
