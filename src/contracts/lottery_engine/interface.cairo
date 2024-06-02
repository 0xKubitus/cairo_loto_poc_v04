use starknet::ContractAddress;


#[starknet::interface]
trait ILotteryEngine<TState> {
    // Getters
    fn get_last_lottery_draw_ID(self: @TState) -> u64;
    fn get_lottery_result(self: @TState, draw_ID: u64) -> (u256, ContractAddress, u256);
    fn get_lottery_engine_status(self: @TState) -> felt252;
    fn get_next_lottery_min_draw_time(self: @TState) -> u64;
    //! to be deleted
    fn get_last_random(self: @TState) -> felt252;

    // Setters
    fn receive_random_words(
        ref self: TState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>
    );
    fn run_lottery_draw(ref self: TState, draw_ID: u64);

    // fn get_lottery_result(self: @TState, draw_id: u256) -> LotteryResult;

    //! TO BE DELETED - ONLY USEFUL DURING DEVELOPMENT IN ORDER TO GET BACK THE 
    //! TESTNET ETHs I SEND TO EACH DEPLOYED CONTRACT FOR TESTING
    fn withdraw_funds(ref self: TState, receiver: ContractAddress);
}
