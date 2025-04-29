#[starknet::contract]
pub mod LogicQuestPuzzle {
    // Imports
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::base::types::{Puzzle, Question, QuestionType, options};
    use crate::interfaces::iquest::ILogicQuestPuzzle;

    // Events
    #[event]
    #[derive(Drop, starknet::Event, starknet::Event)]
    enum Event {
        PuzzleCreated: PuzzleCreated,
        QuestionAdded: QuestionAdded,
        OptionAdded: OptionAdded,
        CreatorAuthorized: CreatorAuthorized,
        CreatorRevoked: CreatorRevoked,
        ContractVersionUpdated: ContractVersionUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleCreated {
        #[key]
        puzzle_id: u32,
        creator: ContractAddress,
        title: felt252,
        version: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct QuestionAdded {
        #[key]
        puzzle_id: u32,
        #[key]
        question_id: u32,
        question_type: QuestionType,
    }

    #[derive(Drop, starknet::Event)]
    struct OptionAdded {
        #[key]
        puzzle_id: u32,
        #[key]
        question_id: u32,
        #[key]
        option_id: u32,
        is_correct: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorAuthorized {
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorRevoked {
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ContractVersionUpdated {
        old_version: u32,
        new_version: u32,
    }

    // Contract storage
    #[storage]
    struct Storage {
        // Admin management
        admin: ContractAddress,
        authorized_creators: Map<ContractAddress, bool>,
        // Puzzles storage
        puzzles_count: u32,
        puzzles: Map<u32, Puzzle>,
        // Questions storage - maps puzzle_id to question_id to Question
        questions_count: Map<u32, u32>,
        questions: Map<(u32, u32), Question>,
        // Options storage - maps puzzle_id, question_id to options array
        options_count: Map<(u32, u32), u32>,
        options: Map<(u32, u32, u32), options>,
        // Version control
        current_contract_version: u32,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress) {
        self.admin.write(admin_address);
        self.puzzles_count.write(0);
        self.current_contract_version.write(1);

        // Authorize admin as a creator
        self.authorized_creators.write(admin_address, true);
        //self.emit(Event::CreatorAuthorized(CreatorAuthorized { creator: admin_address }));
    }


    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_authorized(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                self.authorized_creators.read(caller) || caller == self.admin.read(),
                'Not authorized',
            );
        }
    }


    // Implementation
    #[abi(embed_v0)]
    impl LogicQuestPuzzleImpl of ILogicQuestPuzzle<ContractState> {
        // Add your function implementations here

        // Admin functions
        fn authorize_creator(ref self: ContractState, creator_address: ContractAddress) {
            self.only_admin();
            self.authorized_creators.write(creator_address, true);
            //self.emit(CreatorAuthorized { creator: creator_address });
        }

        fn revoke_creator(ref self: ContractState, creator_address: ContractAddress) {
            self.only_admin();
            self.authorized_creators.write(creator_address, false);
            //self.emit(CreatorRevoked { creator: creator_address });
        }

        fn update_contract_version(ref self: ContractState, new_version: u32) {
            self.only_admin();
            let old_version = self.current_contract_version.read();
            assert(new_version > old_version, 'Version must increase');
            self.current_contract_version.write(new_version);
            //self.emit(ContractVersionUpdated { old_version, new_version });
        }


        // Creator functions
        fn create_puzzle(
            ref self: ContractState,
            title: felt252,
            description: felt252,
            difficulty_level: u8,
            time_limit: u32,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(difficulty_level <= 10, 'Difficulty must be 1-10');

            let caller = get_caller_address();
            let puzzle_id = self.puzzles_count.read() + 1;
            let current_timestamp = starknet::get_block_timestamp();

            // Create new puzzle
            let new_puzzle = Puzzle {
                id: puzzle_id,
                title: title,
                description: description,
                version: self.current_contract_version.read(),
                difficulty_level: difficulty_level,
                total_points: 0, // Will be updated as questions are added
                time_limit: time_limit,
                creator: caller,
                creation_timestamp: current_timestamp,
            };

            // Store the puzzle
            self.puzzles.write(puzzle_id, new_puzzle);
            self.puzzles_count.write(puzzle_id);
            self.questions_count.write(puzzle_id, 0);

            // Emit event
            // self.emit(
            //     PuzzleCreated {
            //         puzzle_id,
            //         creator: caller,
            //         title,
            //         version: self.current_contract_version.read()
            //     }
            // );

            puzzle_id
        }


        fn add_question(
            ref self: ContractState,
            puzzle_id: u32,
            content: felt252,
            question_type: QuestionType,
            difficulty: u8,
            points: u32,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(difficulty <= 10, 'Difficulty must be 1-10');

            // Get puzzle and validate caller is creator
            let puzzle = self.puzzles.read(puzzle_id);
            let caller = get_caller_address();
            assert(puzzle.creator == caller || self.admin.read() == caller, 'Not puzzle creator');

            // Create new question
            let question_id = self.questions_count.read(puzzle_id) + 1;
            let new_question = Question {
                id: question_id, content, question_type, difficulty, points,
            };

            // Store the question
            self.questions.write((puzzle_id, question_id), new_question);
            self.questions_count.write(puzzle_id, question_id);
            self.options_count.write((puzzle_id, question_id), 0);

            // Update puzzle total points
            let mut puzzle = self.puzzles.read(puzzle_id);
            puzzle.total_points += points;
            self.puzzles.write(puzzle_id, puzzle);

            // Emit event
            // self.emit(
            //     QuestionAdded {
            //         puzzle_id,
            //         question_id,
            //         question_type,
            //     }
            // );

            question_id
        }

        fn add_option(
            ref self: ContractState,
            puzzle_id: u32,
            question_id: u32,
            content: felt252,
            is_correct: bool,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');

            // Get puzzle and validate caller is creator
            let puzzle = self.puzzles.read(puzzle_id);
            let caller = get_caller_address();
            assert(puzzle.creator == caller || self.admin.read() == caller, 'Not puzzle creator');

            // Create new option
            let option_id = self.options_count.read((puzzle_id, question_id)) + 1;
            let new_option = options { id: option_id, content, is_correct };

            // Store the option
            self.options.write((puzzle_id, question_id, option_id), new_option);
            self.options_count.write((puzzle_id, question_id), option_id);

            // // Emit event
            // self.emit(
            //     OptionAdded {
            //         puzzle_id,
            //         question_id,
            //         option_id,
            //         is_correct,
            //     }
            //);

            option_id
        }


        // Query functions
        fn get_puzzle(self: @ContractState, puzzle_id: u32) -> Puzzle {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            self.puzzles.read(puzzle_id)
        }

        fn get_question(self: @ContractState, puzzle_id: u32, question_id: u32) -> Question {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            self.questions.read((puzzle_id, question_id))
        }

        fn get_option(
            self: @ContractState, puzzle_id: u32, question_id: u32, option_id: u32,
        ) -> options {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            assert(
                option_id <= self.options_count.read((puzzle_id, question_id)), 'Invalid option ID',
            );
            self.options.read((puzzle_id, question_id, option_id))
        }


        fn get_puzzle_questions_count(self: @ContractState, puzzle_id: u32) -> u32 {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            self.questions_count.read(puzzle_id)
        }

        fn get_question_options_count(
            self: @ContractState, puzzle_id: u32, question_id: u32,
        ) -> u32 {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            self.options_count.read((puzzle_id, question_id))
        }

        fn get_total_puzzles(self: @ContractState) -> u32 {
            self.puzzles_count.read()
        }

        fn get_contract_version(self: @ContractState) -> u32 {
            self.current_contract_version.read()
        }

        fn is_authorized_creator(self: @ContractState, address: ContractAddress) -> bool {
            self.authorized_creators.read(address)
        }
    }
}

