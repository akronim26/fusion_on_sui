// filename: sources/fusion_order.move

/// This module implements a permissionless order execution system inspired by 1inch Fusion on Sui.
/// It enables users to create orders that can be fulfilled by any resolver (executor) who meets
/// the specified trading conditions. Key features:
///
/// * Permissionless execution - Any resolver can fill orders by providing the required output
/// * Security deposits - Orders are secured by deposits that incentivize honest execution
/// * Shared objects - Orders are implemented as shared objects for public discoverability
/// * Event tracking - Full order lifecycle events (creation, filling, cancellation)
///
/// # Technical Implementation
/// * Uses shared objects as an idiomatic Sui replacement for EVM's CREATE2 pattern
/// * Implements a resolver reward mechanism through security deposits
/// * Provides atomic execution guarantees through Sui's object model
///
/// # Usage Flow
/// 1. Maker creates order with security deposit and trade parameters
/// 2. Order becomes publicly discoverable as a shared object
/// 3. Resolver executes trade and claims security deposit as reward
/// 4. Maker can cancel and reclaim deposit after expiry
///
/// # Note
/// This differs from a basic two-party escrow by enabling permissionless resolution
/// and using security deposits to ensure honest execution.

module escrow_contracts::fusion_order {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    
    use escrow_contracts::order_types::{Self, Order};

    // === Error Codes ===
    /// Unauthorized attempt to resolve an order by non-designated resolver
    const E_INVALID_RESOLVER: u64 = 1;
    /// Security deposit amount is below required minimum
    const E_INSUFFICIENT_DEPOSIT: u64 = 2;
    /// Output amount from swap is below specified minimum
    const E_INSUFFICIENT_OUTPUT: u64 = 3;
    /// Operation attempted on an expired order
    const E_ORDER_EXPIRED: u64 = 4;

    // === Events ===
    
    /// Event emitted when a new order is created
    public struct OrderCreated has copy, drop {
        order_id: address,
        maker: address,
        resolver: address,
        deposit_amount: u64,
        min_output: u64,
        expiry: u64
    }

    /// Event emitted when an order is filled by resolver
    public struct OrderFilled has copy, drop {
        order_id: address,
        maker: address,
        resolver: address,
        output_amount: u64,
        timestamp: u64
    }

    /// Event emitted when an order is cancelled
    public struct OrderCancelled has copy, drop {
        order_id: address,
        maker: address,
        timestamp: u64
    }
    
    /// Specifies the trade execution parameters for a Fusion order
    /// This structure contains all the information needed by resolvers to execute the trade
    public struct TradeParams has copy, drop, store {
        /// The type of coin that the maker wants to receive (encoded as bytes)
        target_coin_type: vector<u8>,
        /// Minimum amount of target coins that must be received for the trade to succeed
        min_output: u64, 
        /// Additional routing data that resolvers should use for trade execution
        /// Format depends on the specific DEX or AMM being used
        route_data: vector<u8> 
    }

    /// Core Fusion order object that extends the basic Order type with resolver-specific features
    /// This is implemented as a shared object to enable permissionless discovery and execution
    public struct FusionOrder has key {
        /// Unique identifier for the order object
        id: UID,
        /// Core order data including deposit and maker information
        core: Order<SUI>,
        /// Address of the designated resolver who can execute this order
        resolver: address,
        /// Execution parameters for the trade
        trade_params: TradeParams,
        /// Version number for potential future upgrades
        /// Current version: 1
        version: u64
    }
    
    // === Public Entry Functions ===

    /// Creates a new Fusion order with the specified parameters and security deposit
    /// The order becomes publicly discoverable as a shared object that resolvers can execute
    ///
    /// # Arguments
    /// * `security_deposit` - SUI coins to be used as security deposit
    /// * `resolver` - Address of the designated resolver who can execute this order
    /// * `target_coin_type` - Type of coin the maker wants to receive
    /// * `min_output` - Minimum amount of target coins that must be received
    /// * `route_data` - Additional data needed by resolver for trade execution
    /// * `expiry_ms` - Timestamp in milliseconds when order expires
    /// * `ctx` - Transaction context
    ///
    /// # Events
    /// Emits an `OrderCreated` event upon successful creation
    ///
    /// # Aborts
    /// * If security deposit is below minimum required amount
    public entry fun create_order(
        security_deposit: Coin<SUI>,
        resolver: address,
        target_coin_type: vector<u8>,
        min_output: u64,
        route_data: vector<u8>,
        expiry_ms: u64,
        ctx: &mut TxContext
    ) {
        // Verify sufficient deposit
        assert!(
            coin::value(&security_deposit) >= order_types::min_deposit(),
            E_INSUFFICIENT_DEPOSIT
        );

        let maker = tx_context::sender(ctx);
        
        // Create core escrow order
        let core = order_types::new_order(
            coin::value(&security_deposit),
            expiry_ms,
            maker,
            coin::into_balance(security_deposit)
        );

        // Create trade params
        let trade_params = TradeParams {
            target_coin_type,
            min_output,
            route_data
        };

        // Create fusion order
        let fusion_order = FusionOrder {
            id: object::new(ctx),
            core,
            resolver,
            trade_params,
            version: 1
        };

        // Get the order ID for event emission
        let order_id = object::uid_to_address(&fusion_order.id);

        // Share the order object making it publicly discoverable
        transfer::share_object(fusion_order);

        // Emit order creation event
        event::emit(OrderCreated {
            order_id,
            maker,
            resolver,
            deposit_amount: coin::value(&security_deposit),
            min_output,
            expiry: expiry_ms
        });
    }

    /// Allows the designated resolver to fill an order by providing the swapped coins
    /// Upon successful execution, the resolver receives the security deposit as a reward
    ///
    /// # Arguments
    /// * `order` - The Fusion order to execute (consumed on successful execution)
    /// * `swapped_coins` - The coins obtained from executing the trade, must meet min_output
    /// * `ctx` - Transaction context
    ///
    /// # Flow
    /// 1. Verifies resolver authorization and order expiry
    /// 2. Validates that swapped amount meets minimum requirements
    /// 3. Transfers swapped coins to maker
    /// 4. Transfers security deposit to resolver as reward
    /// 5. Cleans up the order object
    ///
    /// # Events
    /// Emits an `OrderFilled` event upon successful execution
    ///
    /// # Aborts
    /// * If caller is not the designated resolver
    /// * If order has expired
    /// * If swapped amount is below minimum required output
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

        // Check order expiry
        assert!(
            tx_context::epoch_timestamp_ms(ctx) < order_types::get_order_expiry(&core),
            E_ORDER_EXPIRED
        );

        // Verify resolver is authorized
        assert!(
            tx_context::sender(ctx) == resolver,
            E_INVALID_RESOLVER
        );

        // Verify the swapped amount meets minimum requirements
        assert!(
            coin::value(&swapped_coins) >= trade_params.min_output,
            E_INSUFFICIENT_OUTPUT
        );
        
        // Get the maker's address
        let maker = order_types::get_order_maker(&core);

        // Transfer swapped coins to the maker
        transfer::public_transfer(copy swapped_coins, maker);

        // Transfer security deposit to resolver as reward
        let deposit_coin = coin::from_balance(
            order_types::extract_deposit(&mut core),
            ctx
        );
        let resolver_addr = tx_context::sender(ctx);
        transfer::public_transfer(deposit_coin, resolver_addr);

        // Emit order filled event
        event::emit(OrderFilled {
            order_id: object::uid_to_address(&id),
            maker,
            resolver: resolver_addr,
            output_amount: coin::value(&swapped_coins),
            timestamp: tx_context::epoch_timestamp_ms(ctx)
        });

        // Cleanup order object
        object::delete(id)
    }

    /// Allows the order maker to cancel an expired order and reclaim the security deposit
    ///
    /// # Arguments
    /// * `order` - The Fusion order to cancel (consumed on successful cancellation)
    /// * `ctx` - Transaction context
    ///
    /// # Flow
    /// 1. Verifies caller is the order maker
    /// 2. Verifies order has expired
    /// 3. Returns security deposit to maker
    /// 4. Cleans up the order object
    ///
    /// # Events
    /// Emits an `OrderCancelled` event upon successful cancellation
    ///
    /// # Aborts
    /// * If caller is not the order maker
    /// * If order has not yet expired
    public entry fun cancel(
        order: FusionOrder,
        ctx: &mut TxContext
    ) {
        let FusionOrder {
            id,
            core,
            resolver: _,
            trade_params: _,
            version: _
        } = order;

        let maker = order_types::get_order_maker(&core);

        // Verify caller is maker and order is expired
        assert!(
            tx_context::sender(ctx) == maker,
            E_INVALID_RESOLVER
        );

        assert!(
            tx_context::epoch_timestamp_ms(ctx) >= order_types::get_order_expiry(&core),
            E_ORDER_EXPIRED
        );

        // Create coin from balance and send to maker
        let deposit_coin = coin::from_balance(
            order_types::extract_deposit(&mut core),
            ctx
        );
        transfer::public_transfer(deposit_coin, maker);

        // Emit order cancelled event
        event::emit(OrderCancelled {
            order_id: object::uid_to_address(&id),
            maker,
            timestamp: tx_context::epoch_timestamp_ms(ctx)
        });

        // Cleanup order object 
        object::delete(id)
    }

    // === Public View Functions ===

    /// Returns the type of coin that the maker wants to receive
    /// @param order - The Fusion order to query
    /// @return The target coin type as a byte vector
    public fun get_target_coin_type(order: &FusionOrder): vector<u8> {
        order.trade_params.target_coin_type
    }

    /// Returns the minimum amount of target coins that must be received
    /// @param order - The Fusion order to query
    /// @return The minimum output amount
    public fun get_min_output(order: &FusionOrder): u64 {
        order.trade_params.min_output
    }

    /// Returns the address of the designated resolver for this order
    /// @param order - The Fusion order to query
    /// @return The resolver's address
    public fun get_resolver(order: &FusionOrder): address {
        order.resolver
    }

    /// Returns the address of the maker who created this order
    /// @param order - The Fusion order to query
    /// @return The maker's address
    public fun get_maker(order: &FusionOrder): address {
        order_types::get_order_maker(&order.core)
    }

    /// Returns the amount of SUI coins deposited as security
    /// @param order - The Fusion order to query
    /// @return The deposit amount in SUI
    public fun get_deposit_value(order: &FusionOrder): u64 {
        order_types::get_order_value(&order.core)
    }

    /// Returns the timestamp when this order expires
    /// @param order - The Fusion order to query
    /// @return The expiry timestamp in milliseconds
    public fun get_expiry(order: &FusionOrder): u64 {
        order_types::get_order_expiry(&order.core)
    }
}
