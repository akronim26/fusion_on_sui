module escrow_contracts::order_types {
    use sui::hash;
    use sui::bcs;
    use sui::balance::{Self, Balance};
    
    const MIN_SECURITY_DEPOSIT: u64 = 2_000_000_000;
    
    /// Core order interface for the escrow system
    public struct Order<phantom T> has store {
        value: u64,
        expiry: u64,
        maker: address,
        deposit: Balance<T>
    }

    /// Extracts deposit balance from the order
    /// This should only be called when an order is being resolved or cancelled
    public fun extract_deposit<T>(order: &mut Order<T>): Balance<T> {
        balance::withdraw_all(&mut order.deposit)
    }

    /// Parameters used to derive deterministic escrow IDs
    /// Similar to CREATE2 salt + init code pattern
    public struct OrderCreationData has copy, drop {
        maker: address,
        resolver: address,
        value: u64,
        expiry: u64,
        salt: vector<u8>,
        creation_nonce: u64 // Unique nonce from tx sender
    }

    /// Hashes order data to create a unique identifier
    /// Similar to CREATE2 but adapted for Sui's object model
    /// @param data - The order creation parameters
    /// @return vector<u8> - The hash that will be used for ID generation
    public fun hash_order_data(data: &OrderCreationData): vector<u8> {
        // Combine all data including the creation nonce to ensure uniqueness
        bcs::to_bytes(data)
    }

    /// Generates a deterministic ID for an escrow
    /// Similar to CREATE2 address generation but for Sui objects
    /// @param data - The order creation parameters
    /// @return ID - The deterministic object ID for the escrow
    public fun derive_escrow_id(data: &OrderCreationData): address {
        // Hash all order data including creator's address
        let hash = hash_order_data(data);
        
        // Generate deterministic ID from hash
        // This pattern ensures the ID will be the same if all parameters match
        let mut input = hash::keccak256(&hash);
        let nonce_bytes = bcs::to_bytes(&data.creation_nonce);
        vector::append(&mut input, nonce_bytes);
        let final_hash = hash::keccak256(&input); 
        object::id_to_address(&object::id_from_bytes(final_hash)) // generate address

    }

    /// Create new order creation data with a unique nonce
    public fun new_order_creation_data(
        maker: address,
        resolver: address,
        value: u64,
        expiry: u64,
        salt: vector<u8>,
        nonce: u64
    ): OrderCreationData {
        OrderCreationData {
            maker,
            resolver,
            value,
            expiry,
            salt,
            creation_nonce: nonce
        }
    }
    
    /// Getters for OrderCreationData fields
    public fun get_data_maker(data: &OrderCreationData): address {
        data.maker
    }

    public fun get_data_resolver(data: &OrderCreationData): address {
        data.resolver
    }

    public fun get_data_value(data: &OrderCreationData): u64 {
        data.value
    }

    public fun get_data_expiry(data: &OrderCreationData): u64 {
        data.expiry
    }

    /// Get the salt bytes from the order data
    public fun get_data_salt(data: &OrderCreationData): vector<u8> {
        data.salt
    }

    public fun min_deposit(): u64 {
        MIN_SECURITY_DEPOSIT
    }

    public fun get_order_value<T>(order: &Order<T>): u64 {
        order.value
    }

    public fun get_order_expiry<T>(order: &Order<T>): u64 {
        order.expiry
    }

    public fun get_order_maker<T>(order: &Order<T>): address {
        order.maker
    }

    public fun take_order_deposit<T>(order: Order<T>): Balance<T> {
        let Order { value: _, expiry: _, maker: _, deposit } = order;
        deposit
    }

    // === Public Creator Functions ===

    /// Create a new order core struct
    public fun new_order<T>(
        value: u64,
        expiry: u64,
        maker: address,
        deposit: Balance<T>
    ): Order<T> {
        Order<T> {
            value,
            expiry,
            maker,
            deposit
        }
    }
}
