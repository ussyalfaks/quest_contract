#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, get_caller_address, class_hash::Felt252TryIntoClassHash, SyscallResultTrait};
    use starknet::testing::{set_contract_address, set_caller_address, set_block_timestamp, pop_log, get_syscall_execution_info_syscall_ptr};
    use core::result::ResultTrait;
    use core::option::OptionTrait;
    use core::array::{ArrayTrait, SpanTrait};
    use core::serde::Serde; 
    use integer::{u256, U256TryIntoContractAddress, u128_try_from_felt252};
    use debug::PrintTrait;

    // Assuming OZ ERC20 and a basic ERC721 implementation are available
    // Adjust paths as necessary based on your project structure and dependencies
    use openzeppelin::token::erc20::erc20::ERC20;
    use openzeppelin::token::erc20::erc20::ERC20::InternalTrait as ERC20InternalTrait; // Alias to avoid conflict
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    // Mock ERC721 - Replace with actual implementation if available
    // Or use a more sophisticated mock framework
    mod MockERC721 {
        use starknet::ContractAddress;
        use integer::u256;

        #[starknet::interface]
        trait IMockERC721<TState> {
            // Mock mint function to track calls
            fn mint(ref self: TState, to: ContractAddress, token_id: u256);
            fn owner_of(self: @TState, token_id: u256) -> ContractAddress;
        }

        #[starknet::contract]
        mod MockERC721Contract {
            use starknet::ContractAddress;
            use integer::u256;
            use super::IMockERC721;

            #[storage]
            struct Storage {
                owners: LegacyMap<u256, ContractAddress>,
                // Track mint calls for testing
                last_mint_to: ContractAddress,
                last_mint_token_id: u256,
            }

            #[external(v0)]
            impl MockERC721Impl of IMockERC721<ContractState> {
                fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
                    // Basic mint logic for testing, no checks
                    self.owners.write(token_id, to);
                    self.last_mint_to.write(to);
                    self.last_mint_token_id.write(token_id);
                }
                fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
                    self.owners.read(token_id)
                }
            }
        }
    }

    // Import the contract to be tested
    use quest_contract::src::tournament::TournamentContract;
    use quest_contract::src::tournament::TournamentContract::{ 
        IExternalImpl, 
        Tournament, PlayerScore, WinnerPrizeInfo, 
        Event, TournamentCreated, PlayerEntered, ScoreSubmitted, WinnersSubmitted, TournamentFinalized, PrizeDistributed, NFTAwarded
    };

    // Helper constants
    fn CREATOR() -> ContractAddress { starknet::contract_address_const::<'CREATOR'>() }
    fn PLAYER1() -> ContractAddress { starknet::contract_address_const::<'PLAYER1'>() }
    fn PLAYER2() -> ContractAddress { starknet::contract_address_const::<'PLAYER2'>() }
    fn STRK_TOKEN_ADDR() -> ContractAddress { starknet::contract_address_const::<'STRK'>() }
    fn NFT_COLLECTION_ADDR() -> ContractAddress { starknet::contract_address_const::<'NFT'>() }
    fn TOURNAMENT_CONTRACT_ADDR() -> ContractAddress { starknet::contract_address_const::<'TOURNEY'>() }

    const ONE_HOUR: u64 = 3600;
    const ENTRY_FEE: u256 = 100; // Example fee
    const PUZZLE_ID_1: u32 = 1;
    const PUZZLE_ID_2: u32 = 2;
    const NFT_TOKEN_ID_1: u256 = 111;
    const NFT_TOKEN_ID_2: u256 = 222;

    // Helper struct for deployment results
    struct DeployOutput {
        tournament_address: ContractAddress,
        strk_address: ContractAddress,
        nft_address: ContractAddress,
    }

    // Helper function to deploy contracts and setup initial state
    fn setup_env() -> DeployOutput {
        // Deploy Mock STRK ERC20
        let strk_admin = CREATOR(); // Use creator as admin for simplicity
        let mut strk_state = ERC20::unsafe_new_contract_state();
        ERC20::InternalTrait::_initializer(ref strk_state, 'MockSTRK'.try_into().unwrap(), 'MSTRK'.try_into().unwrap(), 18, 0, strk_admin, strk_admin);
        set_contract_address(STRK_TOKEN_ADDR()); // Set address for the dispatcher calls
        // Mint some STRK for players
        ERC20::InternalTrait::_mint(ref strk_state, PLAYER1(), 1000.into());
        ERC20::InternalTrait::_mint(ref strk_state, PLAYER2(), 1000.into());

        // Deploy Mock NFT ERC721
        let mut nft_state = MockERC721::MockERC721Contract::unsafe_new_contract_state();
        set_contract_address(NFT_COLLECTION_ADDR());
        // No constructor needed for this simple mock

        // Deploy Tournament Contract
        let mut tournament_state = TournamentContract::unsafe_new_contract_state();
        TournamentContract::constructor(ref tournament_state, STRK_TOKEN_ADDR());
        set_contract_address(TOURNAMENT_CONTRACT_ADDR());

        DeployOutput { 
            tournament_address: TOURNAMENT_CONTRACT_ADDR(),
            strk_address: STRK_TOKEN_ADDR(),
            nft_address: NFT_COLLECTION_ADDR(),
        }
    }
    
    // Helper to get dispatchers
    fn get_tournament_dispatcher(address: ContractAddress) -> TournamentContract::IContractDispatcher {
        TournamentContract::IContractDispatcher { contract_address: address }
    }
    fn get_strk_dispatcher(address: ContractAddress) -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address: address }
    }
    fn get_nft_dispatcher(address: ContractAddress) -> MockERC721::IMockERC721Dispatcher {
        MockERC721::IMockERC721Dispatcher { contract_address: address }
    }

    // Helper function to setup a tournament for testing
    fn setup_tournament_with_players(deploy: DeployOutput) -> u64 {
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Create tournament
        let current_time = get_block_timestamp();
        let start_time = current_time + ONE_HOUR;
        let end_time = start_time + ONE_HOUR * 2;
        let puzzle_ids = array![PUZZLE_ID_1, PUZZLE_ID_2];
        
        set_caller_address(CREATOR());
        let tournament_id = tournament_dispatcher.create_tournament(
            ENTRY_FEE, start_time, end_time, puzzle_ids, deploy.nft_address
        );
        
        // Approve STRK spend for both players
        let strk_dispatcher = get_strk_dispatcher(deploy.strk_address);
        set_caller_address(PLAYER1());
        strk_dispatcher.approve(deploy.tournament_address, ENTRY_FEE);
        set_caller_address(PLAYER2());
        strk_dispatcher.approve(deploy.tournament_address, ENTRY_FEE);
        
        tournament_id
    }
    
    // Helper to advance time to tournament start
    fn advance_to_tournament_start(tournament_dispatcher: TournamentContract::IContractDispatcher, tournament_id: u64) {
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        set_block_timestamp(tournament.start_time);
    }
    
    // Helper to advance time to tournament end
    fn advance_to_tournament_end(tournament_dispatcher: TournamentContract::IContractDispatcher, tournament_id: u64) {
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        set_block_timestamp(tournament.end_time);
    }

    // --- Test Cases Start Here ---

    #[test]
    #[available_gas(2000000)] // Adjust gas limit as needed
    fn test_create_tournament_success() {
        let deploy = setup_env();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);

        let start_time = get_block_timestamp() + ONE_HOUR;
        let end_time = start_time + ONE_HOUR;
        let puzzle_ids = array![PUZZLE_ID_1, PUZZLE_ID_2];

        set_caller_address(CREATOR());
        let tournament_id = tournament_dispatcher.create_tournament(ENTRY_FEE, start_time, end_time, puzzle_ids.clone(), deploy.nft_address);
        assert(tournament_id == 1, 'Incorrect tournament ID');

        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        assert(tournament.id == tournament_id, 'ID mismatch');
        assert(tournament.creator == CREATOR(), 'Creator mismatch');
        assert(tournament.entry_fee == ENTRY_FEE, 'Fee mismatch');
        assert(tournament.start_time == start_time, 'Start time mismatch');
        assert(tournament.end_time == end_time, 'End time mismatch');
        assert(tournament.nft_collection == deploy.nft_address, 'NFT address mismatch');
        assert(tournament.prize_pool == 0, 'Prize pool should be 0');
        assert(!tournament.is_finalized, 'Should not be finalized');
        
        // Check puzzle IDs stored
        let stored_puzzles = tournament_dispatcher.get_tournament_puzzle_ids(tournament_id);
        assert(stored_puzzles.len() == puzzle_ids.len(), 'Puzzle count mismatch');
        assert(*stored_puzzles.at(0) == PUZZLE_ID_1, 'Puzzle ID 1 mismatch');
        assert(*stored_puzzles.at(1) == PUZZLE_ID_2, 'Puzzle ID 2 mismatch');

        // Check Event (using pop_log which isn't ideal, better with testing frameworks)
        // let event = starknet::testing::pop_event().expect('No event emitted'); 
        // match event { 
        //     Event::TournamentCreated(data) => {
        //        assert(data.tournament_id == tournament_id, 'Event ID mismatch');
        //     }, 
        //     _ => panic_with_felt252('Wrong event type') 
        // };
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Start time must be in future',))] 
    fn test_create_tournament_fail_past_start_time(){
        let deploy = setup_env();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        let start_time = get_block_timestamp() - 1; // In the past
        let end_time = start_time + ONE_HOUR;
        let puzzle_ids = array![PUZZLE_ID_1];
        set_caller_address(CREATOR());
        tournament_dispatcher.create_tournament(ENTRY_FEE, start_time, end_time, puzzle_ids, deploy.nft_address);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('End time must be after start',))] 
    fn test_create_tournament_fail_end_before_start(){
        let deploy = setup_env();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        let start_time = get_block_timestamp() + ONE_HOUR;
        let end_time = start_time - 1; // Before start
        let puzzle_ids = array![PUZZLE_ID_1];
        set_caller_address(CREATOR());
        tournament_dispatcher.create_tournament(ENTRY_FEE, start_time, end_time, puzzle_ids, deploy.nft_address);
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Must have at least one puzzle',))] 
    fn test_create_tournament_fail_no_puzzles(){
        let deploy = setup_env();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        let start_time = get_block_timestamp() + ONE_HOUR;
        let end_time = start_time + ONE_HOUR;
        let puzzle_ids = array![]; // Empty array
        set_caller_address(CREATOR());
        tournament_dispatcher.create_tournament(ENTRY_FEE, start_time, end_time, puzzle_ids, deploy.nft_address);
    }

    // --- Tests for enter_tournament ---
    
    #[test]
    #[available_gas(2000000)]
    fn test_enter_tournament_success() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        let strk_dispatcher = get_strk_dispatcher(deploy.strk_address);
        
        // Initial balance check
        let contract_balance_before = strk_dispatcher.balance_of(deploy.tournament_address);
        let player_balance_before = strk_dispatcher.balance_of(PLAYER1());
        
        // Enter tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Check entry state
        assert(tournament_dispatcher.has_entered(tournament_id, PLAYER1()), 'Player should be entered');
        
        // Check fee transfer
        let contract_balance_after = strk_dispatcher.balance_of(deploy.tournament_address);
        let player_balance_after = strk_dispatcher.balance_of(PLAYER1());
        assert(contract_balance_after == contract_balance_before + ENTRY_FEE, 'Contract balance incorrect');
        assert(player_balance_after == player_balance_before - ENTRY_FEE, 'Player balance incorrect');
        
        // Check prize pool updated
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        assert(tournament.prize_pool == ENTRY_FEE, 'Prize pool not updated');
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Already entered',))]
    fn test_enter_tournament_already_entered() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Enter first time
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Try to enter again - should fail
        tournament_dispatcher.enter_tournament(tournament_id);
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Tournament ended',))]
    fn test_enter_tournament_after_end() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Advance time past tournament end
        advance_to_tournament_end(tournament_dispatcher, tournament_id);
        
        // Try to enter after end - should fail
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
    }
    
    // --- Tests for submit_score ---
    
    #[test]
    #[available_gas(2000000)]
    fn test_submit_score_success() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit score
        let score: u128 = 100;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, score);
        
        // Check score is recorded
        let player_score = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_1, PLAYER1());
        assert(player_score.score == score, 'Score not recorded correctly');
        
        // Check total score
        let total_score = tournament_dispatcher.get_player_total_score(tournament_id, PLAYER1());
        assert(total_score == score, 'Total score incorrect');
    }
    
    #[test]
    #[available_gas(2000000)]
    fn test_submit_score_update_higher() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit initial score
        let first_score: u128 = 100;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, first_score);
        
        // Submit higher score
        let second_score: u128 = 150;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, second_score);
        
        // Check score is updated
        let player_score = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_1, PLAYER1());
        assert(player_score.score == second_score, 'Score not updated correctly');
        
        // Check total score reflects update
        let total_score = tournament_dispatcher.get_player_total_score(tournament_id, PLAYER1());
        assert(total_score == second_score, 'Total score incorrect');
    }
    
    #[test]
    #[available_gas(2000000)]
    fn test_submit_score_ignored_lower() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit high score
        let high_score: u128 = 100;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, high_score);
        
        // Submit lower score (should be ignored)
        let low_score: u128 = 50;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, low_score);
        
        // Check score is still the high score
        let player_score = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_1, PLAYER1());
        assert(player_score.score == high_score, 'Score incorrectly updated');
    }
    
    #[test]
    #[available_gas(2000000)]
    fn test_submit_multiple_puzzle_scores() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit scores for multiple puzzles
        let score1: u128 = 100;
        let score2: u128 = 200;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, score1);
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_2, score2);
        
        // Check individual scores
        let player_score1 = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_1, PLAYER1());
        let player_score2 = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_2, PLAYER1());
        assert(player_score1.score == score1, 'Score 1 incorrect');
        assert(player_score2.score == score2, 'Score 2 incorrect');
        
        // Check total score is sum of both
        let total_score = tournament_dispatcher.get_player_total_score(tournament_id, PLAYER1());
        assert(total_score == score1 + score2, 'Total score incorrect');
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Invalid puzzle ID',))]
    fn test_submit_score_invalid_puzzle() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit score for non-existent puzzle
        let invalid_puzzle_id: u32 = 999;
        tournament_dispatcher.submit_score(tournament_id, invalid_puzzle_id, 100);
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Tournament not started',))]
    fn test_submit_score_before_start() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Try to submit score before tournament starts
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, 100);
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Tournament ended',))]
    fn test_submit_score_after_end() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player enters tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance time past tournament end
        advance_to_tournament_end(tournament_dispatcher, tournament_id);
        
        // Try to submit score after tournament ends
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, 100);
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Player not entered',))]
    fn test_submit_score_not_entered() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Try to submit score without entering tournament
        set_caller_address(PLAYER1());
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, 100);
    }
    
    // --- Tests for submit_winners and finalize_tournament ---
    
    fn setup_tournament_with_entries_and_scores() -> (DeployOutput, u64) {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player 1 enters and submits scores
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Player 2 enters and submits scores
        set_caller_address(PLAYER2());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to tournament start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit scores
        set_caller_address(PLAYER1());
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, 100);
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_2, 200);
        
        set_caller_address(PLAYER2());
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, 150);
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_2, 250);
        
        // Advance to tournament end
        advance_to_tournament_end(tournament_dispatcher, tournament_id);
        
        (deploy, tournament_id)
    }
    
    #[test]
    #[available_gas(4000000)]
    fn test_submit_winners_success() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Create winner prize info
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER2(), 
                strk_share: 120, // 60% of prize pool
                nft_token_id: NFT_TOKEN_ID_1, 
            },
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: 80, // 40% of prize pool
                nft_token_id: NFT_TOKEN_ID_2, 
            },
        ];
        
        // Submit winners
        set_caller_address(CREATOR());
        tournament_dispatcher.submit_winners(tournament_id, winners_info);
        
        // Check tournament state (should still be active, not finalized)
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        assert(!tournament.is_finalized, 'Should not be finalized yet');
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Unauthorized: Only creator',))]
    fn test_submit_winners_unauthorized() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Create winner prize info
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: 100, 
                nft_token_id: NFT_TOKEN_ID_1, 
            },
        ];
        
        // Try to submit winners as non-creator
        set_caller_address(PLAYER1());
        tournament_dispatcher.submit_winners(tournament_id, winners_info);
    }
    
    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('Shares exceed prize pool',))]
    fn test_submit_winners_exceeds_prize_pool() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Get prize pool amount
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        
        // Create winner prize info with excessive share
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: tournament.prize_pool + 1, // Exceeds prize pool
                nft_token_id: NFT_TOKEN_ID_1, 
            },
        ];
        
        // Try to submit winners with excessive shares
        set_caller_address(CREATOR());
        tournament_dispatcher.submit_winners(tournament_id, winners_info);
    }
    
    #[test]
    #[available_gas(4000000)]
    fn test_finalize_tournament_success() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        let strk_dispatcher = get_strk_dispatcher(deploy.strk_address);
        
        // Record balances before
        let player1_balance_before = strk_dispatcher.balance_of(PLAYER1());
        let player2_balance_before = strk_dispatcher.balance_of(PLAYER2());
        
        // Create winner prize info
        let p1_share: u256 = 80;
        let p2_share: u256 = 120;
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER2(), 
                strk_share: p2_share,
                nft_token_id: NFT_TOKEN_ID_1, 
            },
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: p1_share,
                nft_token_id: NFT_TOKEN_ID_2, 
            },
        ];
        
        // Submit winners
        set_caller_address(CREATOR());
        tournament_dispatcher.submit_winners(tournament_id, winners_info);
        
        // Finalize tournament
        tournament_dispatcher.finalize_tournament(tournament_id);
        
        // Check tournament state
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        assert(tournament.is_finalized, 'Tournament should be finalized');
        assert(tournament.prize_pool == 0, 'Prize pool should be empty');
        
        // Check token transfers
        let player1_balance_after = strk_dispatcher.balance_of(PLAYER1());
        let player2_balance_after = strk_dispatcher.balance_of(PLAYER2());
        assert(player1_balance_after == player1_balance_before + p1_share, 'Player1 prize incorrect');
        assert(player2_balance_after == player2_balance_before + p2_share, 'Player2 prize incorrect');
        
        // NFT awards would be checked here if we had a real NFT contract
    }
    
    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Winners not submitted yet',))]
    fn test_finalize_tournament_no_winners() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Try to finalize without submitting winners
        set_caller_address(CREATOR());
        tournament_dispatcher.finalize_tournament(tournament_id);
    }
    
    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('Tournament not ended',))]
    fn test_finalize_tournament_before_end() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player 1 and 2 enter
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        set_caller_address(PLAYER2());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to start but not end
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Create winner prize info
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: 100, 
                nft_token_id: NFT_TOKEN_ID_1, 
            },
        ];
        
        // Submit winners
        set_caller_address(CREATOR());
        tournament_dispatcher.submit_winners(tournament_id, winners_info); // This should fail with "Tournament not ended"
    }
    
    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('Already finalized',))]
    fn test_finalize_tournament_already_finalized() {
        let (deploy, tournament_id) = setup_tournament_with_entries_and_scores();
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Create winner prize info
        let winners_info = array![
            WinnerPrizeInfo { 
                player: PLAYER1(), 
                strk_share: 100, 
                nft_token_id: NFT_TOKEN_ID_1, 
            },
            WinnerPrizeInfo { 
                player: PLAYER2(), 
                strk_share: 100, 
                nft_token_id: NFT_TOKEN_ID_2, 
            },
        ];
        
        // Submit winners and finalize
        set_caller_address(CREATOR());
        tournament_dispatcher.submit_winners(tournament_id, winners_info);
        tournament_dispatcher.finalize_tournament(tournament_id);
        
        // Try to finalize again
        tournament_dispatcher.finalize_tournament(tournament_id);
    }
    
    // --- Tests for view functions ---
    
    #[test]
    #[available_gas(2000000)]
    fn test_view_functions() {
        let deploy = setup_env();
        let tournament_id = setup_tournament_with_players(deploy.clone());
        let tournament_dispatcher = get_tournament_dispatcher(deploy.tournament_address);
        
        // Player 1 enters
        set_caller_address(PLAYER1());
        tournament_dispatcher.enter_tournament(tournament_id);
        
        // Advance to start
        advance_to_tournament_start(tournament_dispatcher, tournament_id);
        
        // Submit score
        let score: u128 = 150;
        tournament_dispatcher.submit_score(tournament_id, PUZZLE_ID_1, score);
        
        // Test get_tournament
        let tournament = tournament_dispatcher.get_tournament(tournament_id);
        assert(tournament.id == tournament_id, 'Tournament ID mismatch');
        assert(tournament.entry_fee == ENTRY_FEE, 'Entry fee mismatch');
        
        // Test get_player_score
        let player_score = tournament_dispatcher.get_player_score(tournament_id, PUZZLE_ID_1, PLAYER1());
        assert(player_score.player == PLAYER1(), 'Player mismatch');
        assert(player_score.score == score, 'Score mismatch');
        
        // Test get_player_total_score
        let total_score = tournament_dispatcher.get_player_total_score(tournament_id, PLAYER1());
        assert(total_score == score, 'Total score mismatch');
        
        // Test has_entered
        assert(tournament_dispatcher.has_entered(tournament_id, PLAYER1()), 'Player1 should be entered');
        assert(!tournament_dispatcher.has_entered(tournament_id, PLAYER2()), 'Player2 should not be entered');
        
        // Test get_tournament_puzzle_ids
        let puzzle_ids = tournament_dispatcher.get_tournament_puzzle_ids(tournament_id);
        assert(puzzle_ids.len() == 2, 'Should have 2 puzzles');
        assert(*puzzle_ids.at(0) == PUZZLE_ID_1, 'Puzzle ID 1 mismatch');
        assert(*puzzle_ids.at(1) == PUZZLE_ID_2, 'Puzzle ID 2 mismatch');
    }
} 