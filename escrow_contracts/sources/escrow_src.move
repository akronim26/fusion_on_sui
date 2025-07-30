module escrow_contracts::escrow_src {
    use sui::object::{delete, new};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::tx_context::sender;
    use sui::hash::keccak256;

    const MIN_SAFETY_DEPOSIT: u64 = 2_000_000_000; // 2 SUI equivalent - for resolvers

    const EInsufficientDeposit: u64 = 0;
    const ENotResolver: u64 = 1;
    const EAlreadyResolved: u64 = 2;
    const EInvalidSecret: u64 = 3;
    const ETimelocked: u64 = 4;
    const EFinalityLockActive: u64 = 5; 
    const ETimelockNotExpired: u64 = 6;
    const EAlreadyClaimed: u64 = 7;

    // key creates an object which gets stored on chain and can be transferred between the users
    // store allows the struct to be used as the field inside another struct
    public struct Escrow<phantom T> has key, store {
        id: UID,
        maker: address,
        resolver: address,
        amount: u64,
        hashlock: vector<u8>,
        timelock: u64,
        finalitylock: u64,
        is_claimed: bool,
        is_refunded: bool,
        token_balance: Balance<T>, // <T> means the token can be of any type which implements store ability
        sui_balance: Balance<SUI> // balance of SUI coins
    }

    public fun create<T>(
        maker: address,
        resolver: address,
        amount: u64,
        hashlock: vector<u8>,
        timelock: u64,
        finalitylock: u64,
        token_coin: Coin<T>,
        sui_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Escrow<T> {
        let sui_balance = coin::into_balance(sui_coin); // destroys the sui coin and stores the balance
        assert!(balance::value(&sui_balance) >= MIN_SAFETY_DEPOSIT, EInsufficientDeposit);

        let current_timestamp = timestamp_ms(clock);

        Escrow<T> {
            id: new(ctx),
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

    public entry fun claim<T>(
        escrow: Escrow<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == escrow.resolver, ENotResolver);
        assert!(!escrow.is_claimed && !escrow.is_refunded, EAlreadyResolved);
        assert!(keccak256(&secret) == escrow.hashlock, EInvalidSecret);
        assert!(timestamp_ms(clock) < escrow.timelock, ETimelocked);
        assert!(timestamp_ms(clock) >= escrow.finalitylock, EFinalityLockActive);

        let Escrow {
            id,
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

        // transfer the security deposit and the tokens to the resolver 
        transfer::public_transfer(coin::from_balance(token_balance, ctx), resolver);
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), resolver);

        delete(id);
    }

    public entry fun slash<T>(
        escrow: Escrow<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(timestamp_ms(clock) >= escrow.timelock, ETimelockNotExpired);
        assert!(!escrow.is_claimed, EAlreadyClaimed);

        let Escrow {
            id,
            maker,
            resolver: _,
            amount: _,
            hashlock: _,
            timelock: _,
            finalitylock: _,
            is_claimed: _,
            is_refunded: _,
            token_balance,
            sui_balance
        } = escrow;

        transfer::public_transfer(coin::from_balance(token_balance, ctx), maker); //transfer to maker because on source chain the resolver is the one staking the funds
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), sender(ctx));
        delete(id);
    }

}
