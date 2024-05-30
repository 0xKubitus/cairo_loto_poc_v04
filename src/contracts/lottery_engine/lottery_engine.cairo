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
    use cairo_loto_poc::contracts::lottery_engine::interface::ILotteryEngine;
    use cairo_loto_poc::contracts::tickets_handler::interface::{
        TicketsHandlerABIDispatcher, TicketsHandlerABIDispatcherTrait
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::{ContractAddress, ClassHash,};
    use starknet::info::{
        get_block_number, get_block_timestamp, get_caller_address, get_contract_address,
    };


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[derive(Drop, Serde, starknet::Store)]
    struct LotteryDrawDetails {
        ticket_ID: u256,
        ticket_owner: ContractAddress,
        cashprize_amount: u256,
    }


    #[storage]
    struct Storage {
        tickets_handler_contract: ContractAddress,
        pragma_vrf_contract: ContractAddress,
        last_lottery_draw_ID: u64,
        min_UTC_time_for_next_draw: u64,
        lottery_draw_info: LegacyMap::<u256, LotteryDrawDetails>,
        lottery_engine_status: felt252,
        min_block_number_storage: u64, // required by Pragma VRF contract
        last_random_storage: felt252, // value updated by Pragma's VRF contract, not mandatory to save in storage but useful for development/testing
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
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        tickets_handler: ContractAddress,
        pragma_vrf: ContractAddress,
        UTC_timestamp_of_first_draw_in_seconds: u64,
    ) {
        self.ownable.initializer(admin);
        self.pragma_vrf_contract.write(pragma_vrf);

        //================================================================
        //! Setting the minimum date for the first lottery draw => To be updated for production/mainnet deployment
        //? => Use Javascript to print in your console the minimum time for the next lottery draw (run the following code in the javascript environment of your liking, for example -> codepen.io)
        //? ```javascript
        //? const time_of_first_draw_in_ms = Date.parse('01 Feb 2024 22:45:00 UTC'); // Change the date and time as you see fit, but always use UTC time.
        //?
        //? const time_of_first_draw = time_of_first_draw_in_ms / 1000; // (Converting date from milliseconds to seconds because starknet::get_block_timestamp() returns a value in seconds)
        //? console.log('time_of_first_draw_in_seconds = ', time_of_first_draw);
        //? ```
        //? You should see this result in your console:
        //? "time_of_first_draw_in_seconds = 1706827500"

        //! here is the hard-coded way, which might be more practical for development & testing?
        // let UTC_timestamp_of_first_draw_in_seconds: u256 = 1706827500;
        // self.time_of_first_draw_in_seconds.write(UTC_timestamp_of_first_draw_in_seconds);

        //! Below is the generic way, to use for production
        self.min_UTC_time_for_next_draw.write(UTC_timestamp_of_first_draw_in_seconds);
        //================================================================

        self.lottery_engine_status.write('WAITING FOR NEXT DRAW TIME');
    }

    #[abi(embed_v0)]
    impl LotteryEngineImpl of ILotteryEngine<ContractState> {
        //
        // Getters
        //
        fn get_last_lottery_draw_ID(self: @ContractState) -> u64 {
            self.last_lottery_draw_ID.read()
        }

        fn get_lottery_engine_status(self: @ContractState) -> felt252 {
            self.lottery_engine_status.read()
        }

        //! To be deleted/replaced with the results of a specific lottery draw_ID
        fn get_last_random(self: @ContractState) -> felt252 {
            let last_random = self.last_random_storage.read();
            return last_random;
        }

        //
        // Setters
        //
        fn run_lottery_draw(ref self: ContractState, draw_ID: u64,) {
            //! Should we ONLY allow the owner of this contract to interact with this function?
            // (maybe we should not, for example in case we can't trigger the lottery draws
            // with a cron job and want to allow any user to run lottery draws when a timer arrives to zero on the frontend app?)
            //! let's keep it during development phase, though, to avoid anyone spending the testnet ETH I'll be sending to this contract!
            self.ownable.assert_only_owner();

            // Verify that it is indeed time to initialize a new lottery draw
            let current_time = get_block_timestamp();
            assert!(
                current_time >= self.min_UTC_time_for_next_draw.read(),
                "It is not yet time to conduct this Lottery draw"
            );

            // Verify that this Lottery draw hasn't been already initialized
            assert!(
                self.lottery_engine_status.read() == 'WAITING FOR NEXT DRAW TIME',
                "this Lottery draw has already been initialized"
            );

            // Change lottery_engine_status value to 'IN PROGRESS'...
            // to prevent the same lottery_draw_ID to be conducted multiple times
            self.lottery_engine_status.write('LOTTERY DRAW IS IN PROGRESS');

            // Request 'random_words' from PragmaVRF contract using "fn _request_my_randomness()" private method
            let callback_address: ContractAddress = get_contract_address();
            let callback_fee_limit: u128 = 5000000000000000; //! will need to be fine-tuned
            let publish_delay: u64 = 1; //! let's try '1' and '0', but I guess that '0' won't work.
            let num_words: u64 =
                1; // I might request for more than a single word from the VRF so that there would be more probability to have a value matching a ticket_ID?
            let calldata: Array<felt252> =
                array![]; // I HAVE NO CLUE IF THIS CALLDATA PARAMETER ACTUALLY PLAYS ANY ROLE IN THE RANDOMNESS GENERATION? IF ONLY IT COULD BE USED TO SET UP THE RANGE OF THE RANDOMNESS...
            //! SEED NEEDS TO CHANGE EVERY DRAW, BUT DOES IT ALSO NEEDS
            //! TO BE VERY DIFFICULT TO GUESS BY POTENTIAL HACKERS?
            //! IF SO, HOW SHOULD I PROCEED? 
            //! (=> passing the value of seed from frontend app, which would not be open-sourced?)
            // let seed: u64 = ((current_time / get_block_number()) * draw_ID); // no need to make things complex here if I plan to open-source the code of this contract...
            let seed: u64 = current_time;

            self
                ._request_my_randomness(
                    seed, callback_address, callback_fee_limit, publish_delay, num_words, calldata
                );
        }

        /// CANNOT BE RENAMED, NOR HAVE DIFFERENT ATTRIBUTES
        /// (PRAGMA SENDS THE RANDOMNESS TO THE PRESENT CONTRACT USING BELOW FUNCTION)
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
                caller_address == self.pragma_vrf_contract.read(), 'caller not randomness contract'
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

            //! this should be modified to give clear results of the lottery draw ->
            self
                .last_random_storage
                .write(
                    random_word
                ); // `last_random_storage` is default storage value from Pragma's example contract

            // Maybe return: draw_ID, block_timestamp, winning_ticket_ID, winning_ticket_owner, cashprize_amount... instead?

            //TODO: Find the owner of the ticket which ID matches the last random storage + compute cashprize + allow winner to claim cashprize
            // _finalize_lottery_draw();

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
            let current = self.last_lottery_draw_ID.read();
            self.last_lottery_draw_ID.write(current + 1);
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
            let randomness_contract_address = self.pragma_vrf_contract.read();
            let randomness_dispatcher = IPragmaVRFDispatcher {
                contract_address: randomness_contract_address
            };
            let caller = get_caller_address();
            let compute_fees = randomness_dispatcher.compute_premium_fee(caller);

            // Approve the randomness contract to transfer the callback fee
            // NOTE FOR SELF: This contract always needs to own some ETH to cover Pragma VRF fees required to use VRF
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 // ETH Contract Address
                    .try_into()
                    .unwrap()
            };
            eth_dispatcher
                .approve(
                    randomness_contract_address,
                    (callback_fee_limit + compute_fees + callback_fee_limit / 5).into()
                );

            // Request the randomness
            let request_id = randomness_dispatcher
                .request_random(
                    seed, callback_address, callback_fee_limit, publish_delay, num_words, calldata
                );

            let current_block_number = get_block_number();
            self.min_block_number_storage.write(current_block_number + publish_delay);

            return ();
        }
    }
}
