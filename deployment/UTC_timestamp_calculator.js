// Change the date and time as you see fit, but always use UTC time.
const time_of_first_draw_in_ms = Date.parse("2 June 2024 13:55:00 UTC");

// Converting date from milliseconds to seconds because starknet::get_block_timestamp() returns a value in seconds
const time_of_first_draw = time_of_first_draw_in_ms / 1000;

console.log(`time_of_first_draw_in_seconds = ${time_of_first_draw} seconds`);
