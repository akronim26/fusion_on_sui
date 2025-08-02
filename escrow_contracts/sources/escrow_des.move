module escrow_contracts::escrow_des {
    use sui::object::{delete, new};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::tx_context::sender;
    use sui::hash::keccak256;

    use escrow_contracts::order_types::{Self, OrderCreationData};

    // Constants
    const MIN_SAFETY_DEPOSIT: u64 = 2_000_000_000; // 2 SUI minimum deposit
    const FINALITY_PERIOD: u64 = 3600000; // 1 hour finality period

    // Error codes
    const EInsufficientDeposit: u64 = 0;
    const ENotResolver: u64 = 1;
    const EAlreadyResolved: u64 = 2;
    const EInvalidSecret: u64 = 3;
    const ETimelocked: u64 = 4;
    const EFinalityLockActive: u64 = 5; 
    const ETimelockNotExpired: u64 = 6;
    const EAlreadyClaimed: u64 = 7;
    const ETimelockExpired: u64 = 8;

    // key creates an object which gets stored on chain and can be transferred between the users
    // store allows the struct to be used as the field inside another struct
    public struct Escrow<phantom T> has key, store {
        id: UID,
        escrow_address: address,
        maker: address,
        resolver: address,
        amount: u64,
        hashlock: vector<u8>,
        timelock: u64,
        finalitylock: u64,
        is_claimed: bool,
        is_refunded: bool,
        token_balance: Balance<T>, 
        sui_balance: Balance<SUI> // balance of SUI coins
    }

    /// Creates an escrow with a deterministic ID based on order parameters
    /// Similar to CREATE2 deployment pattern in EVM
    public fun create<T>(
        order_data: &OrderCreationData,
        token_coin: Coin<T>,
        sui_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Escrow<T> {
        // Verify security deposit
        let sui_balance = coin::into_balance(sui_coin);
        assert!(balance::value(&sui_balance) >= MIN_SAFETY_DEPOSIT, EInsufficientDeposit);

        // Get current time
        let current_time = clock::timestamp_ms(clock);

        // Verify order not expired
        assert!(current_time < order_types::get_data_expiry(order_data), ETimelockExpired);
        
        // Generate deterministic ID
        let escrow_id = order_types::derive_escrow_id(order_data);

        let maker = order_types::get_data_maker(order_data);
        let resolver = order_types::get_data_resolver(order_data);
        let amount = order_types::get_data_value(order_data);
        let hashlock = order_types::get_data_salt(order_data);
        let timelock = order_types::get_data_expiry(order_data);
        let finalitylock = FINALITY_PERIOD;

        let current_timestamp = clock::timestamp_ms(clock);

        Escrow<T> {
            id: new(ctx),
            escrow_address: escrow_id,
            maker,
            resolver,
            amount,
            hashlock,
            timelock: current_timestamp + timelock,
            finalitylock: current_timestamp + finalitylock,
            is_claimed: false,
            is_refunded: false,
            token_balance: coin::into_balance(token_coin),
            sui_balance
        }
    }

    public entry fun transfer_tokens_to_maker<T>(
        escrow: Escrow<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(sender(ctx) == escrow.resolver, ENotResolver); // ensures that this function is only callable by the resolver
        assert!(!escrow.is_claimed && !escrow.is_refunded, EAlreadyResolved);
        assert!(keccak256(&secret) == escrow.hashlock, EInvalidSecret);
        assert!(clock::timestamp_ms(clock) < escrow.timelock, ETimelocked);
        assert!(clock::timestamp_ms(clock) >= escrow.finalitylock, EFinalityLockActive);

        let Escrow {
            id,
            escrow_address,
            maker,
            resolver,
            amount: _,
            hashlock: _,
            timelock: _,
            finalitylock: _,
            is_claimed: _,
            is_refunded: _,
            token_balance,
            sui_balance
        } = escrow;

        // transfer back the security deposit to resolver and the token to maker (need to see for different address for maker on both chain) on the destination chain
        transfer::public_transfer(coin::from_balance(token_balance, ctx), maker);
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), resolver);

        // deletes the escrow contract
        delete(id);
    }

    public entry fun slash<T>(
        escrow: Escrow<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(clock::timestamp_ms(clock) >= escrow.timelock, ETimelockNotExpired);
        assert!(!escrow.is_claimed, EAlreadyClaimed);

        let Escrow {
            id,
            escrow_address,
            maker: _,
            resolver,
            amount: _,
            hashlock: _,
            timelock: _,
            finalitylock: _,
            is_claimed: _,
            is_refunded: _,
            token_balance,
            sui_balance
        } = escrow;

        // transfer the fund back in case the timelock is expired
        transfer::public_transfer(coin::from_balance(token_balance, ctx), resolver); //transfer to resolver because on destination chain the resolver is the one staking the funds
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), resolver);

        delete(id);
    }
    
}
