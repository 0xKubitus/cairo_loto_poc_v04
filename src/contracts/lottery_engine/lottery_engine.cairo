use starknet::ContractAddress;

#[starknet::interface]
trait IPragmaVRF<TContractState> {
    // Interface of Pragma Oracle Randomness contract
    // see https://github.com/astraly-labs/pragma-oracle/blob/main/src/randomness/randomness.cairo
    fn compute_premium_fee(self: @TContractState, caller_address: ContractAddress) -> u128;

    fn request_random(
        ref self: TContractState,
        seed: u64,
        callback_address: ContractAddress,
        callback_fee_limit: u128,
        publish_delay: u64,
        num_words: u64,
        calldata: Array<felt252>
    ) -> u64;
}




#[starknet::contract]
mod LotteryEngine {
    use super::{IPragmaVRFDispatcher, IPragmaVRFDispatcherTrait};
    use cairo_loto_poc::contracts::lottery_engine::interface::{ILotteryEngine, LotteryResult};
    use cairo_loto_poc::contracts::tickets_handler::interface::{TicketsHandlerABIDispatcher, TicketsHandlerABIDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::{ContractAddress, ClassHash,};
    use starknet::info::{get_caller_address, get_block_number,};


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        tickets_handler_contract: ContractAddress,
        pragma_vrf_contract: ContractAddress,
        next_draw_ID: u256,
        min_block_number_storage: u64,
        last_random_storage: felt252,

        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }


    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress, tickets_handler: ContractAddress, pragma_vrf: ContractAddress,) {
        self.ownable.initializer(admin);
        self.pragma_vrf_contract.write(pragma_vrf);
        self.next_draw_ID.write(1);
    }

    #[abi(embed_v0)]
    impl LotteryEngineImpl of ILotteryEngine<ContractState> {
        fn get_next_lottery_draw_id(self: @ContractState) -> u256 {
            self.next_draw_ID.read()
        }

        fn run_lottery_draw(
            ref self: ContractState, 
            draw_ID: u256,
        ) {
            let tickets_contract = TicketsHandlerABIDispatcher { contract_address: self.tickets_handler_contract.read() };

            // use `fn request_my_randomness()`

        }

        /// CURRENTLY IMPLEMENTED EXACTLY AS IN PRAGMA'S EXAMPLE
        fn receive_random_words(
            ref self: ContractState,
            requestor_address: ContractAddress,
            request_id: u64,
            random_words: Span<felt252>,
            calldata: Array<felt252>
        ) {
            // Have to make sure that the caller is the Pragma Randomness Oracle contract
            let caller_address = get_caller_address();
            assert(
                caller_address == self.pragma_vrf_contract.read(),
                'caller not randomness contract'
            );
            // and that the current block is within publish_delay of the request block
            let current_block_number = get_block_number();
            let min_block_number = self.min_block_number_storage.read();
            assert(min_block_number <= current_block_number, 'block number issue');

            // and that the requestor_address is what we expect it to be (can be self
            // or another contract address), checking for self in this case
            //let contract_address = get_contract_address();
            //assert(requestor_address == contract_address, 'requestor is not self');

            // Optionally: Can also make sure that request_id is what you expect it to be,
            // and that random_words_len==num_words

            // Your code using randomness!
            let random_word = *random_words.at(0);

            //! `last_random_storage` is default storage value from Pragma's example contract
            self.last_random_storage.write(random_word);
            //! this should be modified to give clear results of the lottery draw ->
            //! draw_ID, block_timestamp, winning_ticket_ID, winning_ticket_owner, cashprize_amount...
            //TODO:
            // finalize_lottery_draw()

            return ();
        }
    
    }
    
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn _update_draw_ID(ref self: ContractState) {
            let current = self.next_draw_ID.read();
            self.next_draw_ID.write(current + 1);
            //? SHOULD THIS CHANGE OF STATE TRIGGER AN EVENT?
        }

        fn _request_my_randomness(
            ref self: ContractState,
            seed: u64,
            callback_address: ContractAddress,
            callback_fee_limit: u128,
            publish_delay: u64,
            num_words: u64,
            calldata: Array<felt252>
        ) {
            let vrf_contract_address = self.pragma_vrf_contract.read();
            let __member_module_pragma_vrf_contract_dispatcher = IPragmaVRFDispatcher { contract_address: vrf_contract_address };
            let caller = get_caller_address();
            let compute_fees = __member_module_pragma_vrf_contract_dispatcher.compute_premium_fee(caller);

            // Approve the randomness contract to transfer the callback fee
            // NOTE FOR SELF: This contract always needs to own some ETH to cover Pragma VRF fees required to use VRF
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 // ETH Contract Address
                    .try_into()
                    .unwrap()
            };
            eth_dispatcher
                .approve(
                    vrf_contract_address,
                    (callback_fee_limit + compute_fees + callback_fee_limit / 5).into()
                );

            // Request the randomness
            let request_id = __member_module_pragma_vrf_contract_dispatcher
                .request_random(
                    seed, callback_address, callback_fee_limit, publish_delay, num_words, calldata
                );

            let current_block_number = get_block_number();
            self.min_block_number_storage.write(current_block_number + publish_delay);

            return ();
        }
    }
}