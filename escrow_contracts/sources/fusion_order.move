module escrow_contracts::fusion_order {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    use sui::tx_context;
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::Balance;

    use escrow_contracts::order_types::{Self, Order};

    const E_INVALID_RESOLVER: u64 = 1;
    const E_INSUFFICIENT_DEPOSIT: u64 = 2;
    const E_INSUFFICIENT_OUTPUT: u64 = 3;
    const E_ORDER_EXPIRED: u64 = 4;

    public struct OrderCreated has copy, drop {
        order_id: address,
        maker: address,
        resolver: address,
        deposit_amount: u64,
        min_output: u64,
        expiry: u64
    }

    public struct OrderFilled has copy, drop {
        order_id: address,
        maker: address,
        resolver: address,
        output_amount: u64,
        timestamp: u64
    }

    public struct OrderCancelled has copy, drop {
        order_id: address,
        maker: address,
        timestamp: u64
    }

    public struct TradeParams has copy, drop, store {
        target_coin_type: vector<u8>,
        min_output: u64,
        route_data: vector<u8> 
    }

    public struct FusionOrder has key {
        id: UID,
        core: Order<SUI>,
        resolver: address,
        trade_params: TradeParams,
        version: u64
    }

    public entry fun create_order(
        security_deposit: Coin<SUI>,
        resolver: address,
        target_coin_type: vector<u8>,
        min_output: u64,
        route_data: vector<u8>,
        expiry_ms: u64,
        ctx: &mut TxContext
    ) {
        assert!(
            coin::value(&security_deposit) >= order_types::min_deposit(),
            E_INSUFFICIENT_DEPOSIT
        );

        let maker = tx_context::sender(ctx);

        let deposit_amount_val = coin::value(&security_deposit);

        let core = order_types::new_order(
            deposit_amount_val,
            expiry_ms,
            maker,
            coin::into_balance(security_deposit)
        );

        let trade_params = TradeParams {
            target_coin_type,
            min_output,
            route_data
        };

        let fusion_order = FusionOrder {
            id: object::new(ctx),
            core,
            resolver,
            trade_params,
            version: 1
        };

        let order_id = object::uid_to_address(&fusion_order.id);

        transfer::share_object(fusion_order);

        event::emit(OrderCreated {
            order_id,
            maker,
            resolver,
            deposit_amount: deposit_amount_val,
            min_output,
            expiry: expiry_ms
        });
    }

    public entry fun resolve(
        order: FusionOrder,
        swapped_coins: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let FusionOrder { 
            id,
            mut core,
            resolver,
            trade_params,
            version: _
        } = order;

        assert!(
            tx_context::epoch_timestamp_ms(ctx) < order_types::get_order_expiry(&core),
            E_ORDER_EXPIRED
        );

        assert!(
            tx_context::sender(ctx) == resolver,
            E_INVALID_RESOLVER
        );

        assert!(
            coin::value(&swapped_coins) >= trade_params.min_output,
            E_INSUFFICIENT_OUTPUT
        );

        let maker = order_types::get_order_maker(&core);

        let output_amount = coin::value(&swapped_coins);
        transfer::public_transfer(swapped_coins, maker);

        let deposit_coin = coin::from_balance(
            order_types::extract_deposit(&mut core),
            ctx
        );
        let resolver_addr = tx_context::sender(ctx);
        transfer::public_transfer(deposit_coin, resolver_addr);

        event::emit(OrderFilled {
            order_id: object::uid_to_address(&id),
            maker,
            resolver: resolver_addr,
            output_amount,
            timestamp: tx_context::epoch_timestamp_ms(ctx)
        });

        // Fully consume core before returning
        order_types::destroy_order(core);
        object::delete(id);
    }

    public entry fun cancel(
        order: FusionOrder,
        ctx: &mut TxContext
    ) {
        let FusionOrder {
            id,
            mut core,
            resolver: _,
            trade_params: _,
            version: _
        } = order;

        let maker = order_types::get_order_maker(&core);

        assert!(
            tx_context::sender(ctx) == maker,
            E_INVALID_RESOLVER
        );

        assert!(
            tx_context::epoch_timestamp_ms(ctx) >= order_types::get_order_expiry(&core),
            E_ORDER_EXPIRED
        );

        let deposit_coin = coin::from_balance(
            order_types::extract_deposit(&mut core),
            ctx
        );
        transfer::public_transfer(deposit_coin, maker);

        event::emit(OrderCancelled {
            order_id: object::uid_to_address(&id),
            maker,
            timestamp: tx_context::epoch_timestamp_ms(ctx)
        });

        // Fully consume core before returning
        order_types::destroy_order(core);
        object::delete(id);
    }

    public fun get_target_coin_type(order: &FusionOrder): vector<u8> {
        order.trade_params.target_coin_type
    }

    public fun get_min_output(order: &FusionOrder): u64 {
        order.trade_params.min_output
    }

    public fun get_resolver(order: &FusionOrder): address {
        order.resolver
    }

    public fun get_maker(order: &FusionOrder): address {
        order_types::get_order_maker(&order.core)
    }

    public fun get_deposit_value(order: &FusionOrder): u64 {
        order_types::get_order_value(&order.core)
    }

    public fun get_expiry(order: &FusionOrder): u64 {
        order_types::get_order_expiry(&order.core)
    }
}
