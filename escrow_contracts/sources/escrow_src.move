module escrow_contracts::escrow_src {
    use sui::object::new;   
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::hash;
    use sui::coin::{Self, Coin};

    use escrow_contracts::order_types::{Self, OrderCreationData};

    const MIN_SAFETY_DEPOSIT: u64 = 2_000_000_000; // 2 SUI minimum security deposit
    const FINALITY_PERIOD: u64 = 3600000; // 1 hour finality period

    const EInsufficientDeposit: u64 = 0;
    const EInvalidSecret: u64 = 1;
    const ETimelocked: u64 = 2;
    const EFinalityLockActive: u64 = 3; 
    const ETimelockNotExpired: u64 = 4;
    const EAlreadyClaimed: u64 = 5;
    const ETimelockExpired: u64 = 6;

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

    /// Claim escrow funds by revealing the secret
    /// Transfers tokens to resolver and security deposit to maker
    public fun claim<T>(
        escrow: &mut Escrow<T>,
        secret: vector<u8>,
        clock: &Clock,
        resolver_ctx: &mut TxContext
    ) {
        // Verify secret and timing conditions
        assert!(hash::keccak256(&secret) == escrow.hashlock, EInvalidSecret);
        assert!(clock::timestamp_ms(clock) < escrow.timelock, ETimelocked);
        assert!(clock::timestamp_ms(clock) >= escrow.finalitylock, EFinalityLockActive);
        assert!(!escrow.is_claimed && !escrow.is_refunded, EAlreadyClaimed);

        escrow.is_claimed = true;
        
        // Transfer escrowed tokens to resolver
        let amount = escrow.amount;
        let token_coin = coin::from_balance(balance::split(&mut escrow.token_balance, amount), resolver_ctx);
        transfer::public_transfer(token_coin, escrow.resolver);

        // Return security deposit to maker
        let sui_amount = balance::value(&escrow.sui_balance);
        let sui_coin = coin::from_balance(balance::split(&mut escrow.sui_balance, sui_amount), resolver_ctx);
        transfer::public_transfer(sui_coin, escrow.resolver);
    }

    public fun refund<T>(
        escrow: &mut Escrow<T>,
        clock: &Clock,
        maker_ctx: &mut TxContext
    ) {
        assert!(clock::timestamp_ms(clock) >= escrow.timelock, ETimelockNotExpired);
        assert!(!escrow.is_claimed && !escrow.is_refunded, EAlreadyClaimed);

        escrow.is_refunded = true;

        // Return all tokens to maker
        let token_amount = balance::value(&escrow.token_balance);
        let token_coin = coin::from_balance(balance::split(&mut escrow.token_balance, token_amount), maker_ctx);
        let sui_amount = balance::value(&escrow.sui_balance);
        let sui_coin = coin::from_balance(balance::split(&mut escrow.sui_balance, sui_amount), maker_ctx);
        
        let maker = escrow.maker;
        transfer::public_transfer(token_coin, maker);
        transfer::public_transfer(sui_coin, escrow.resolver);
    }

}
