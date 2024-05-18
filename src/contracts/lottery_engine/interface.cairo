
use starknet::ContractAddress;

#[derive(Drop)]
struct LotteryResult {
    ticket_ID: u256,
    ticket_owner: ContractAddress,
    cashprize_amount: u256,
}


#[starknet::interface]
trait ILotteryEngine<TState> {
    fn get_next_lottery_draw_id(self: @TState) -> u256;

    fn receive_random_words(
        ref self: TState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>
    );
    
    fn run_lottery_draw(ref self: TState, draw_ID: u256);
    
    // fn get_lottery_result(self: @TState, draw_id: u256) -> LotteryResult;
}
