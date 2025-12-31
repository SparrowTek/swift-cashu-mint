import Fluent
import Foundation

/// Initial migration to create all mint database tables
struct CreateMintTables: AsyncMigration {
    
    func prepare(on database: Database) async throws {
        // Create mint_keysets table
        try await database.schema(MintKeyset.schema)
            .id()
            .field("keyset_id", .string, .required)
            .field("unit", .string, .required)
            .field("active", .bool, .required)
            .field("input_fee_ppk", .int, .required)
            .field("created_at", .datetime)
            .field("deactivated_at", .datetime)
            .field("private_keys", .data, .required)
            .unique(on: "keyset_id")
            .create()
        
        // Create spent_proofs table - CRITICAL for double-spend prevention
        try await database.schema(SpentProof.schema)
            .id()
            .field("y", .string, .required)
            .field("keyset_id", .string, .required)
            .field("amount", .int, .required)
            .field("spent_at", .datetime)
            .field("witness", .string)
            .unique(on: "y") // CRITICAL: prevents double-spending
            .create()
        
        // Create mint_quotes table
        try await database.schema(MintQuote.schema)
            .id()
            .field("quote_id", .string, .required)
            .field("method", .string, .required)
            .field("unit", .string, .required)
            .field("amount", .int, .required)
            .field("request", .string, .required)
            .field("payment_hash", .string, .required)
            .field("state", .string, .required)
            .field("expiry", .datetime, .required)
            .field("created_at", .datetime)
            .field("issued_at", .datetime)
            .field("description", .string)
            .unique(on: "quote_id")
            .create()
        
        // Create melt_quotes table
        try await database.schema(MeltQuote.schema)
            .id()
            .field("quote_id", .string, .required)
            .field("method", .string, .required)
            .field("unit", .string, .required)
            .field("request", .string, .required)
            .field("amount", .int, .required)
            .field("fee_reserve", .int, .required)
            .field("state", .string, .required)
            .field("payment_preimage", .string)
            .field("fee_paid", .int)
            .field("expiry", .datetime, .required)
            .field("created_at", .datetime)
            .field("paid_at", .datetime)
            .unique(on: "quote_id")
            .create()
        
        // Create blind_signatures table (NUT-09 restore)
        try await database.schema(BlindSignatureRecord.schema)
            .id()
            .field("b_", .string, .required)
            .field("keyset_id", .string, .required)
            .field("amount", .int, .required)
            .field("c_", .string, .required)
            .field("created_at", .datetime)
            .field("dleq_e", .string)
            .field("dleq_s", .string)
            .create()
        
        // Create pending_proofs table (NUT-07)
        try await database.schema(PendingProof.schema)
            .id()
            .field("y", .string, .required)
            .field("keyset_id", .string, .required)
            .field("amount", .int, .required)
            .field("quote_id", .string)
            .field("created_at", .datetime)
            .field("expires_at", .datetime, .required)
            .unique(on: "y") // A proof can only be pending in one operation
            .create()
    }
    
    func revert(on database: Database) async throws {
        // Drop tables in reverse order of dependencies
        try await database.schema(PendingProof.schema).delete()
        try await database.schema(BlindSignatureRecord.schema).delete()
        try await database.schema(MeltQuote.schema).delete()
        try await database.schema(MintQuote.schema).delete()
        try await database.schema(SpentProof.schema).delete()
        try await database.schema(MintKeyset.schema).delete()
    }
}

/// Migration to add NUT-15 MPP support to melt_quotes
struct AddMPPSupport: AsyncMigration {

    func prepare(on database: Database) async throws {
        // Add mpp_amount column to melt_quotes table
        try await database.schema(MeltQuote.schema)
            .field("mpp_amount", .int)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MeltQuote.schema)
            .deleteField("mpp_amount")
            .update()
    }
}

/// Migration to create indexes for performance
/// Separated from table creation for clarity
struct CreateIndexes: AsyncMigration {
    
    func prepare(on database: Database) async throws {
        // Note: Fluent automatically creates indexes for unique constraints
        // and primary keys. Additional indexes can be added using raw SQL
        // if needed for specific query patterns.
        
        // For PostgreSQL, we could add additional indexes via raw SQL:
        // try await database.execute(sql: "CREATE INDEX idx_spent_proofs_keyset ON spent_proofs(keyset_id)")
        // But for now, the unique constraints provide sufficient indexing
    }
    
    func revert(on database: Database) async throws {
        // Indexes will be dropped with tables
    }
}

// MARK: - Migration List

/// All migrations in order
var allMigrations: [any AsyncMigration] {
    [
        CreateMintTables(),
        AddMPPSupport(),
        CreateIndexes()
    ]
}
