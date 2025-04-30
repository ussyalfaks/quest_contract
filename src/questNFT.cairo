#[starknet::contract]
pub mod LogiQuestAchievement {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use quest_contract::interfaces::iquestNFT::ILogiQuestAchievement;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721Impl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        owners: Map<u256, ContractAddress>,
        balances: Map<ContractAddress, u256>,
        // Achievement specific storage
        token_counter: u256,
        authorized_minters: Map<ContractAddress, bool>,
        admin: ContractAddress,
        puzzle_contract: ContractAddress,
        // Achievement metadata
        achievement_tier: Map<u256, AchievementTier>,
        achievement_type: Map<u256, AchievementType>,
        achievement_puzzle_id: Map<u256, u32>,
        achievement_score: Map<u256, u32>,
        achievement_timestamp: Map<u256, u64>,
        achievement_difficulty: Map<u256, u8>,
        achievement_uri: Map<u256, felt252>,
    }

    // Achievement tier enum
    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub enum AchievementTier {
        #[default]
        Bronze: (),
        Silver: (),
        Gold: (),
        Platinum: () // For special achievements
    }

    // Achievement type enum
    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub enum AchievementType {
        #[default]
        PuzzleCompletion: (),
        SpeedRun: (),
        PerfectScore: (),
        SeriesCompletion: (),
        Special: (),
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        AchievementMinted: AchievementMinted,
        MinterAuthorized: MinterAuthorized,
        MinterRevoked: MinterRevoked,
        PuzzleContractUpdated: PuzzleContractUpdated,
    }

    // Custom events
    #[derive(Drop, starknet::Event)]
    struct AchievementMinted {
        #[key]
        token_id: u256,
        #[key]
        recipient: ContractAddress,
        achievement_tier: AchievementTier,
        achievement_type: AchievementType,
        puzzle_id: u32,
        score: u32,
        difficulty: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterAuthorized {
        minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRevoked {
        minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleContractUpdated {
        old_address: ContractAddress,
        new_address: ContractAddress,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin_address: ContractAddress,
        puzzle_contract_address: ContractAddress,
    ) {
        let name = "CytickNft";
        let symbol = "NFT";
        let base_uri = "https://api.example.com/v1/";

        self.erc721.initializer(name, symbol, base_uri);
        self.token_counter.write(0);
        self.admin.write(admin_address);
        self.puzzle_contract.write(puzzle_contract_address);
        self.token_counter.write(0);

        // Authorize admin as a minter
        self.authorized_minters.write(admin_address, true);
        self.emit(MinterAuthorized { minter: admin_address });
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_authorized_minter(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                self.authorized_minters.read(caller) || caller == self.admin.read(),
                'Not authorized to mint',
            );
        }


        fn only_token_owner(self: @ContractState, token_id: u256) {
            let caller = get_caller_address();
            assert(self.owners.read(token_id) == caller, 'Not token owner');
        }

        fn token_exists(self: @ContractState, token_id: u256) {
            assert(self.owners.read(token_id).is_non_zero(), 'Token does not exist');
        }

        fn valid_token(self: @ContractState, token_id: u256) {
            assert(token_id < self.token_counter.read(), 'Invalid token ID');
        }
    }

    #[abi(embed_v0)]
    impl LogiQuestAchievementImpl of ILogiQuestAchievement<ContractState> {
        // Admin functions
        fn authorize_minter(ref self: ContractState, minter_address: ContractAddress) {
            self.only_admin();
            self.authorized_minters.write(minter_address, true);
            self.emit(MinterAuthorized { minter: minter_address });
        }


        fn revoke_minter(ref self: ContractState, minter_address: ContractAddress) {
            self.only_admin();
            self.authorized_minters.write(minter_address, false);
            self.emit(MinterRevoked { minter: minter_address });
        }

        fn update_puzzle_contract(ref self: ContractState, new_puzzle_contract: ContractAddress) {
            self.only_admin();
            let old_address = self.puzzle_contract.read();
            self.puzzle_contract.write(new_puzzle_contract);
            self.emit(PuzzleContractUpdated { old_address, new_address: new_puzzle_contract });
        }


        fn set_token_uri(ref self: ContractState, token_id: u256, uri: felt252) {
            self.only_admin();
            // Use OZ's token_exists check
            assert(self.erc721.exists(token_id), 'Token does not exist');
            self.achievement_uri.write(token_id, uri);
        }


        // Achievement minting function
        fn mint_achievement(
            ref self: ContractState,
            recipient: ContractAddress,
            puzzle_id: u32,
            score: u32,
            max_score: u32,
            time_taken: u32,
            max_time: u32,
            difficulty: u8,
            achievement_type: AchievementType,
        ) -> u256 {
            self.only_authorized_minter();
            assert(recipient.is_non_zero(), 'Cannot mint to zero address');

            // Determine achievement tier based on performance
            let tier = self.calculate_tier(score, max_score, time_taken, max_time);

            // Get next token ID
            let token_id = self.token_counter.read();
            self.token_counter.write(token_id + 1);

            // Mint NFT using ERC721 component
            self.erc721.mint(recipient, token_id);

            // Store achievement metadata
            self.achievement_tier.write(token_id, tier);
            self.achievement_type.write(token_id, achievement_type);
            self.achievement_puzzle_id.write(token_id, puzzle_id);
            self.achievement_score.write(token_id, score);
            self.achievement_difficulty.write(token_id, difficulty);
            self.achievement_timestamp.write(token_id, get_block_timestamp());

            // Emit achievement event
            self
                .emit(
                    AchievementMinted {
                        token_id,
                        recipient,
                        achievement_tier: tier,
                        achievement_type,
                        puzzle_id,
                        score,
                        difficulty,
                    },
                );

            token_id
        }


        // Achievement query functions
        fn get_achievement_details(
            self: @ContractState, token_id: u256,
        ) -> (AchievementTier, AchievementType, u32, u32, u8, u64) {
            assert(self.erc721.exists(token_id), 'Token does not exist');

            (
                self.achievement_tier.read(token_id),
                self.achievement_type.read(token_id),
                self.achievement_puzzle_id.read(token_id),
                self.achievement_score.read(token_id),
                self.achievement_difficulty.read(token_id),
                self.achievement_timestamp.read(token_id),
            )
        }

        fn get_achievement_tier(self: @ContractState, token_id: u256) -> AchievementTier {
            assert(self.erc721.exists(token_id), 'Token does not exist');
            self.achievement_tier.read(token_id)
        }

        fn get_achievement_type(self: @ContractState, token_id: u256) -> AchievementType {
            assert(self.erc721.exists(token_id), 'Token does not exist');
            self.achievement_type.read(token_id)
        }

        fn is_authorized_minter(self: @ContractState, address: ContractAddress) -> bool {
            self.authorized_minters.read(address)
        }

        fn get_puzzle_contract(self: @ContractState) -> ContractAddress {
            self.puzzle_contract.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.token_counter.read()
        }
    }

    // Internal functions
    #[generate_trait]
    impl Private of PrivateTrait {
        fn calculate_tier(
            ref self: ContractState, score: u32, max_score: u32, time_taken: u32, max_time: u32,
        ) -> AchievementTier {
            // Calculate percentage of max score achieved
            let score_percentage = (score * 100) / max_score;

            // Time factor (100% if time_taken == 0, decreasing as time increases)
            let time_factor = if max_time == 0 {
                100 // No time limit, full factor
            } else if time_taken >= max_time {
                50 // Used all time or exceeded, minimum factor
            } else {
                // Scale between 100 and 50 based on time used
                100 - ((time_taken * 50) / max_time)
            };

            // Combined performance score (weighted 70% score, 30% time)
            let performance = (score_percentage * 70 + time_factor * 30) / 100;

            // Determine tier based on performance
            if performance >= 95 {
                AchievementTier::Platinum(())
            } else if performance >= 80 {
                AchievementTier::Gold(())
            } else if performance >= 60 {
                AchievementTier::Silver(())
            } else {
                AchievementTier::Bronze(())
            }
        }
    }
}

