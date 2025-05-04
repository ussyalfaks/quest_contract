#[starknet::contract]
mod TournamentContract {
    use starknet::ContractAddress;
    use starknet::storage::StorageAddress;
    use starknet::syscalls::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::testing;
    use core::debug::PrintTrait;
    use core::serde::Serde;
    use core::array::SpanTrait;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use path::to::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait}; 
    use integer::u256;
    use option::OptionTrait;
    use result::ResultTrait;
    
    // Use Felt252Dict instead of LegacyMap for compatibility with newer Cairo versions & potential features
    // If using an older Starknet version, keep LegacyMap
    use starknet::storage::Felt252Dict; 
    
    // Event definitions
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TournamentCreated: TournamentCreated,
        PlayerEntered: PlayerEntered,
        ScoreSubmitted: ScoreSubmitted,
        WinnersSubmitted: WinnersSubmitted,
        TournamentFinalized: TournamentFinalized,
        PrizeDistributed: PrizeDistributed,
        NFTAwarded: NFTAwarded,
    }

    #[derive(Drop, starknet::Event)]
    struct TournamentCreated {
        #[key]
        tournament_id: u64,
        creator: ContractAddress,
        entry_fee: u256,
        start_time: u64,
        end_time: u64,
        nft_collection: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    struct PlayerEntered {
        #[key]
        tournament_id: u64,
        #[key]
        player: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    struct ScoreSubmitted {
        #[key]
        tournament_id: u64,
        #[key]
        puzzle_id: u32,
        #[key]
        player: ContractAddress,
        score: u128,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct WinnersSubmitted {
         #[key]
        tournament_id: u64,
        submitter: ContractAddress, // Should be creator
    }

    #[derive(Drop, starknet::Event)]
    struct TournamentFinalized {
        #[key]
        tournament_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct PrizeDistributed {
        #[key]
        tournament_id: u64,
        #[key]
        winner: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct NFTAwarded {
        #[key]
        tournament_id: u64,
        #[key]
        winner: ContractAddress,
        nft_collection: ContractAddress,
        token_id: u256, // Assuming NFT uses u256 token IDs
    }


    #[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
    struct Puzzle {
        id: u32,
        // Add puzzle-specific data if needed, e.g., max score
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct PlayerScore {
        player: ContractAddress,
        score: u128,
        timestamp: u64, // Timestamp of last submission
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Tournament {
        id: u64,
        creator: ContractAddress,
        entry_fee: u256,
        start_time: u64,
        end_time: u64,
        puzzle_ids: Array<u32>, // Store only IDs if Puzzle struct is simple
        prize_pool: u256,
        nft_collection: ContractAddress, // Address of the NFT contract for awards
        is_active: bool,
        is_finalized: bool,
    }
    
    // Structure to hold submitted winner data for distribution
    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct WinnerPrizeInfo {
        player: ContractAddress,
        strk_share: u256, 
        nft_token_id: u256, // 0 if no NFT prize for this winner
    }

    #[storage]
    struct Storage {
        strk_token_address: ContractAddress,
        // nft_token_address: ContractAddress, // Might be per-tournament or global
        next_tournament_id: u64,
        tournaments: Felt252Dict<u64, Tournament>,
        // Tracks scores per tournament, per puzzle, per player
        scores: Felt252Dict<(u64, u32, ContractAddress), PlayerScore>, 
        // Tracks total score per player per tournament for leaderboard
        leaderboard: Felt252Dict<(u64, ContractAddress), u128>,
        // Tracks players who entered each tournament
        entrants: Felt252Dict<u64, Felt252Dict<ContractAddress, bool>>,
        // Stores puzzle IDs for each tournament for validation
        tournament_puzzles: Felt252Dict<u64, Felt252Dict<u32, bool>>, 
        // Stores the submitted winner prize info before final distribution
        submitted_winners: Felt252Dict<u64, Array<WinnerPrizeInfo>>, 
        // winners: Felt252Dict<u64, Span<ContractAddress>>, // Replaced by submitted_winners
    }

    #[constructor]
    fn constructor(ref self: ContractState, strk_token: ContractAddress) {
        self.strk_token_address.write(strk_token);
        self.next_tournament_id.write(1); // Start IDs from 1
    }

    #[external(v0)]
    impl TournamentImpl of IExternalImpl<ContractState> {
        // --- Tournament Creation ---
        fn create_tournament(
            ref self: ContractState, 
            entry_fee: u256, 
            start_time: u64, 
            end_time: u64, 
            puzzle_ids: Array<u32>, // Accept Array<u32> instead of Span<Puzzle>
            nft_collection: ContractAddress
        ) -> u64 {
            let current_time = get_block_timestamp();
            assert(start_time >= current_time, 'Start time must be in future');
            assert(end_time > start_time, 'End time must be after start');
            assert(puzzle_ids.len() > 0, 'Must have at least one puzzle');
            
            let caller = get_caller_address();
            let tournament_id = self.next_tournament_id.read();
            
            let tournament = Tournament {
                id: tournament_id,
                creator: caller,
                entry_fee: entry_fee,
                start_time: start_time,
                end_time: end_time,
                puzzle_ids: puzzle_ids.clone(), // Clone the array to store
                prize_pool: 0, // Starts empty, fills with entry fees
                nft_collection: nft_collection,
                is_active: false, // Requires explicit activation? Or based on time?
                is_finalized: false,
            };

            self.tournaments.write(tournament_id, tournament);
            self.next_tournament_id.write(tournament_id + 1);
            
            // Store puzzle IDs for validation
            let mut puzzle_map = self.tournament_puzzles.read(tournament_id);
            let mut i = 0;
            loop {
                if i >= puzzle_ids.len() { break; }
                let puzzle_id = *puzzle_ids.at(i);
                // Optional: check for duplicate IDs in input array?
                puzzle_map.write(puzzle_id, true);
                i += 1;
            };
            self.tournament_puzzles.write(tournament_id, puzzle_map); // Write back the map

            self.emit(Event::TournamentCreated(TournamentCreated {
                tournament_id: tournament_id,
                creator: caller,
                entry_fee: entry_fee,
                start_time: start_time,
                end_time: end_time,
                nft_collection: nft_collection,
            }));
            
            tournament_id
        }

        // --- Player Actions ---
        fn enter_tournament(ref self: ContractState, tournament_id: u64) {
            let caller = get_caller_address();
            let mut tournament = self.tournaments.read(tournament_id);
            assert(tournament.id != 0, 'Tournament not found'); // Check if tournament exists
            assert(!tournament.is_finalized, 'Tournament finalized');
            let current_time = get_block_timestamp();
            // Allow entry before start time or during the tournament? Let's allow entry only before end.
            assert(current_time < tournament.end_time, 'Tournament ended'); 
            
            let mut tournament_entrants = self.entrants.read(tournament_id);
            let has_entered = tournament_entrants.read(caller);
            assert(!has_entered, 'Already entered');

            if tournament.entry_fee > 0 {
                let strk = IERC20Dispatcher { contract_address: self.strk_token_address.read() };
                strk.transfer_from(caller, get_contract_address(), tournament.entry_fee);
                tournament.prize_pool += tournament.entry_fee;
                self.tournaments.write(tournament_id, tournament); 
            }
            
            tournament_entrants.write(caller, true);
            self.entrants.write(tournament_id, tournament_entrants); // Write back the map

            self.emit(Event::PlayerEntered(PlayerEntered {
                tournament_id: tournament_id,
                player: caller,
            }));
        }

        fn submit_score(
            ref self: ContractState, tournament_id: u64, puzzle_id: u32, score: u128
        ) {
            let caller = get_caller_address();
            let tournament = self.tournaments.read(tournament_id);
            assert(tournament.id != 0, 'Tournament not found');
            assert(!tournament.is_finalized, 'Tournament finalized');
            let current_time = get_block_timestamp();
            assert(current_time >= tournament.start_time, 'Tournament not started');
            assert(current_time < tournament.end_time, 'Tournament ended');
            
            let tournament_entrants = self.entrants.read(tournament_id);
            let has_entered = tournament_entrants.read(caller);
            assert(has_entered, 'Player not entered');

            // Validate puzzle_id exists for this tournament
            let puzzle_map = self.tournament_puzzles.read(tournament_id);
            assert(puzzle_map.read(puzzle_id), 'Invalid puzzle ID');

            let current_submission_time = current_time; // Use block timestamp
            let score_key = (tournament_id, puzzle_id, caller);
            let mut scores_map = self.scores.read(score_key); // Read map for this key
            let player_puzzle_score = scores_map; // Assuming structure remains PlayerScore

            // Only update if the new score is higher
            if score > player_puzzle_score.score {
                 let old_score = player_puzzle_score.score;
                 let new_player_score = PlayerScore {
                    player: caller,
                    score: score,
                    timestamp: current_submission_time,
                 };
                 self.scores.write(score_key, new_player_score); // Write back the updated score struct

                 // Update the total leaderboard score
                 let leaderboard_key = (tournament_id, caller);
                 let mut leaderboard_map = self.leaderboard.read(leaderboard_key); // Read map for this key
                 let current_total_score = leaderboard_map; // Assuming structure remains u128
                 // Handle potential underflow if old_score was the default 0 and current is also 0
                 let new_total_score = if current_total_score >= old_score {
                     current_total_score - old_score + score
                 } else { // Should not happen if scores are always >= 0
                     score 
                 };
                 self.leaderboard.write(leaderboard_key, new_total_score); // Write back the updated total score

                 self.emit(Event::ScoreSubmitted(ScoreSubmitted {
                    tournament_id: tournament_id,
                    puzzle_id: puzzle_id,
                    player: caller,
                    score: score,
                    timestamp: current_submission_time,
                 }));
            }
        }
        
        // --- Winner Submission (by Creator/Admin) ---
        fn submit_winners(
            ref self: ContractState, 
            tournament_id: u64, 
            winners_info: Array<WinnerPrizeInfo>
        ) {
            let tournament = self.tournaments.read(tournament_id);
            assert(tournament.id != 0, 'Tournament not found');
            assert(!tournament.is_finalized, 'Already finalized');
            let current_time = get_block_timestamp();
            assert(current_time >= tournament.end_time, 'Tournament not ended');
             
            let caller = get_caller_address();
            assert(caller == tournament.creator, 'Unauthorized: Only creator'); 

            // Basic validation: ensure submitted shares don't exceed prize pool
            let mut total_submitted_share: u256 = 0;
            let mut i = 0;
            loop {
                if i >= winners_info.len() { break; }
                let info = *winners_info.at(i);
                total_submitted_share += info.strk_share;
                i += 1;
            };
            assert(total_submitted_share <= tournament.prize_pool, 'Shares exceed prize pool');
            
            // Store winner info for finalization
            self.submitted_winners.write(tournament_id, winners_info);

            self.emit(Event::WinnersSubmitted(WinnersSubmitted {
                tournament_id: tournament_id,
                submitter: caller,
            }));
        }

        // --- Tournament Finalization & Prizes ---
        fn finalize_tournament(ref self: ContractState, tournament_id: u64) {
             let mut tournament = self.tournaments.read(tournament_id);
             assert(tournament.id != 0, 'Tournament not found');
             assert(!tournament.is_finalized, 'Already finalized');
             let current_time = get_block_timestamp();
             assert(current_time >= tournament.end_time, 'Tournament not ended');
             
             // Ensure winners have been submitted before finalizing
             let winners_info = self.submitted_winners.read(tournament_id);
             assert(winners_info.len() > 0, 'Winners not submitted yet');

             // Optional: Only allow creator or admin to finalize? Or anyone after end + winner submission?
             // let caller = get_caller_address();
             // assert(caller == tournament.creator, 'Unauthorized'); 

             let strk_dispatcher = IERC20Dispatcher { contract_address: self.strk_token_address.read() };
             // let nft_dispatcher = IERC721Dispatcher { contract_address: tournament.nft_collection }; // Placeholder

             let mut distributed_pool: u256 = 0;
             let mut i = 0;
             loop {
                 if i >= winners_info.len() { break; }
                 let info = *winners_info.at(i);

                 // Distribute STRK share
                 if info.strk_share > 0 {
                     // Ensure contract has enough balance (should be covered by prize_pool check, but good practice)
                     // let contract_balance = strk_dispatcher.balance_of(get_contract_address()); 
                     // assert(contract_balance >= info.strk_share, 'Contract STRK insufficient'); // Potentially expensive check
                     
                     strk_dispatcher.transfer(info.player, info.strk_share);
                     distributed_pool += info.strk_share;
                     self.emit(Event::PrizeDistributed(PrizeDistributed{
                        tournament_id: tournament_id,
                        winner: info.player,
                        amount: info.strk_share,
                     }));
                 }

                 // Award NFT
                 if info.nft_token_id > 0 { // Assuming 0 means no NFT prize
                     // Placeholder: Call the NFT contract's mint function
                     // Assumes a mint function like: mint(to: ContractAddress, token_id: u256)
                     // nft_dispatcher.mint(info.player, info.nft_token_id); 
                     
                      self.emit(Event::NFTAwarded(NFTAwarded{
                        tournament_id: tournament_id,
                        winner: info.player,
                        nft_collection: tournament.nft_collection,
                        token_id: info.nft_token_id, // Use the submitted token ID
                     }));
                 }
                 i += 1;
             };
             
             // Update the tournament state
             // We could reduce the prize_pool by distributed_pool, or set it to 0 if all is distributed
             tournament.prize_pool -= distributed_pool; // Reflect distributed amount
             tournament.is_finalized = true;
             self.tournaments.write(tournament_id, tournament);

             self.emit(Event::TournamentFinalized(TournamentFinalized {
                tournament_id: tournament_id,
             }));
        }
        
        // --- Read Functions (Views) ---
        
        fn get_tournament(self: @ContractState, tournament_id: u64) -> Tournament {
            self.tournaments.read(tournament_id)
        }

        fn get_player_score(
            self: @ContractState, tournament_id: u64, puzzle_id: u32, player: ContractAddress
        ) -> PlayerScore {
            self.scores.read((tournament_id, puzzle_id, player))
        }
        
        fn get_player_total_score(
            self: @ContractState, tournament_id: u64, player: ContractAddress
        ) -> u128 {
            self.leaderboard.read((tournament_id, player))
        }

        fn get_tournament_puzzle_ids(self: @ContractState, tournament_id: u64) -> Array<u32> {
            // Note: This reads the whole stored array. May be inefficient for large arrays.
            self.tournaments.read(tournament_id).puzzle_ids 
        }

        fn has_entered(
            self: @ContractState, tournament_id: u64, player: ContractAddress
        ) -> bool {
             self.entrants.read(tournament_id).read(player)
        }

        // TODO: Add function to get leaderboard (potentially paginated or top N)
        // This remains complex on-chain. Could return top N unsorted player scores
        // or require off-chain indexing. For now, let's omit a complex getter.

        // TODO: Add function to allow winners to claim prizes if not distributed automatically
        // Not implemented with current auto-distribution model in finalize_tournament.
    }

    // Internal helper functions removed as winner determination is now off-chain
} 