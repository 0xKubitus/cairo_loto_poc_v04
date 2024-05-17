# CAIRO LOTO backend protocol (proof-of-concept)

To-Do List:

PART I - TICKETS HANDLER CONTRACT

1. Deploy contract and make end-to-end tests.
   -> deploy mocks on testnet first,
   => then if successful make a test on mainnet!

2. Refacto tests using more generic setups -> split 'SetupData' into separate Structs for each contract  
   and make fewer setup functions that are reusable for all tests.

3. Create private fn `_withdraw_from_zklend` or is it not necessary?

4. Add/Complete tests using Events where relevant -> will imply to update setups again.

5. Add storage value for "tickets_limit_per_account" + getter and setter instead of hardcoded value of 10 (not urgent)

6. Issue with using OZ ERC721 component v0.12.0: the use of ByteArrays for "name", "symbol" and "base_uri" =>
   It's annoying because I don't know how to deploy constructors params in ByteArrays (might not even be possible yet with a simple starkli command?)
   It's also annoying because neither blockexplorers nor wallet applications are currently able to read ByteArray values...

---

PART II - LOTTERY ENGINE CONTRACT

1. Get familiar again with Pragma's VRF using my implementation from beginning of this year.

2. Rewrite Lottery Engine contract using current latest cairo version.

3. Implement a shit-ton of tests again, because safety is key!

---

MISC:

1. Update all the codebase using latest cairo prelude/edition = "2023_11" in Scarb.toml (one of major change is the introduction of "pub", but there's more...)
   /!\ THIS MIGHT CAUSE ISSUES BECAUSE OPENZEPPELIN DEPENDENCY IS CURRENTLY USING AN OLD CAIRO PRELUDE/EDITION /!\

2. Refacto/Optimize codebase for gas efficiency + learn as much as possible about all kinds of testing to reinforce protection.
