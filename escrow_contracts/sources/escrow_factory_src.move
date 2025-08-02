module escrow_contracts::escrow_factory_src {
    use sui::object::new;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::tx_context::sender;
    use sui::clock::Clock;

    use escrow_contracts::escrow_src;

    public struct EscrowFactory has key {
        id: UID,
        owner: address
    }

    public fun new_src(ctx: &mut TxContext): EscrowFactory {
        EscrowFactory {
            id: new(ctx),
            owner: sender(ctx)
        }
    }

    public entry fun create_escrow<T>(
        factory: &EscrowFactory,
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
    ) {
        assert!(sender(ctx) == factory.owner, 0);

        let order_data = escrow_contracts::order_types::new_order_creation_data(
            maker,
            resolver,
            amount,
            timelock,
            hashlock,
            0 // creation_nonce set to 0 for now
        );

        let escrow = escrow_src::create<T>(
            &order_data,
            token_coin,
            sui_coin,
            clock,
            ctx
        );

        // ownership transfer of escrow contract to the resolver
        transfer::public_transfer(escrow, resolver);
    }
}
