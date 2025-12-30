# swift-cashu-mint

A production-ready Cashu mint server implementation in Swift.

## Features

- Full NUT compliance (NUT-00 through NUT-09)
- Hummingbird 2.x HTTP framework
- PostgreSQL database via Fluent
- Pluggable Lightning backend (LND or Mock)
- Actor-based services for thread safety

## Requirements

- Swift 6.0+
- PostgreSQL 14+
- LND (for production) or use Mock backend for testing

## Quick Start

### 1. Start PostgreSQL

```bash
docker run -d --name mint-postgres \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=cashu_mint \
  -p 5432:5432 postgres:16
```

### 2. Run the Mint

```bash
DATABASE_URL="postgres://postgres:test@localhost:5432/cashu_mint" \
LIGHTNING_BACKEND=mock \
swift run swift-cashu-mint
```

The mint will start on `http://localhost:3338`.

### 3. Verify It's Running

```bash
curl http://localhost:3338/v1/info | jq
```

## Configuration

All configuration is done via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | **Required** |
| `LIGHTNING_BACKEND` | Lightning backend: `lnd` or `mock` | `mock` |
| `MINT_HOST` | Host address to bind | `0.0.0.0` |
| `MINT_PORT` | Port to listen on | `3338` |
| `MINT_NAME` | Mint name (NUT-06) | `Swift Cashu Mint` |
| `MINT_DESCRIPTION` | Short description | - |
| `MINT_UNIT` | Currency unit | `sat` |
| `MINT_INPUT_FEE_PPK` | Input fee in parts per thousand | `0` |
| `MINT_MIN_AMOUNT` | Minimum mint amount | `1` |
| `MINT_MAX_AMOUNT` | Maximum mint amount | `1000000` |
| `MELT_MIN_AMOUNT` | Minimum melt amount | `1` |
| `MELT_MAX_AMOUNT` | Maximum melt amount | `1000000` |

### LND Configuration (when `LIGHTNING_BACKEND=lnd`)

| Variable | Description |
|----------|-------------|
| `LND_HOST` | LND REST API host (e.g., `localhost:8080`) |
| `LND_MACAROON_PATH` | Path to admin.macaroon file |
| `LND_CERT_PATH` | Path to tls.cert file (optional) |

## CLI Commands

```bash
# Start the server
swift run swift-cashu-mint serve

# Start with custom host/port
swift run swift-cashu-mint serve --host 127.0.0.1 --port 8080

# Enable verbose logging
swift run swift-cashu-mint serve --verbose

# Run database migrations
swift run swift-cashu-mint migrate

# Revert all migrations
swift run swift-cashu-mint migrate --revert
```

## API Endpoints

| Method | Endpoint | NUT | Description |
|--------|----------|-----|-------------|
| GET | `/v1/info` | NUT-06 | Mint information |
| GET | `/v1/keys` | NUT-01 | Active keysets with public keys |
| GET | `/v1/keys/{keyset_id}` | NUT-02 | Specific keyset |
| GET | `/v1/keysets` | NUT-02 | All keysets |
| POST | `/v1/swap` | NUT-03 | Swap tokens |
| POST | `/v1/mint/quote/bolt11` | NUT-04 | Create mint quote |
| GET | `/v1/mint/quote/bolt11/{quote_id}` | NUT-04 | Check mint quote |
| POST | `/v1/mint/bolt11` | NUT-04 | Mint tokens |
| POST | `/v1/melt/quote/bolt11` | NUT-05 | Create melt quote |
| GET | `/v1/melt/quote/bolt11/{quote_id}` | NUT-05 | Check melt quote |
| POST | `/v1/melt/bolt11` | NUT-05 | Melt tokens |
| POST | `/v1/checkstate` | NUT-07 | Check proof states |
| POST | `/v1/restore` | NUT-09 | Restore signatures |

## Development

### Build

```bash
swift build
```

### Run Tests

```bash
DATABASE_URL="postgres://postgres:test@localhost:5432/cashu_mint_test" swift test
```

### Project Structure

```
Sources/swift-cashu-mint/
├── App/
│   ├── Application.swift      # Hummingbird app setup
│   └── Configuration.swift    # Environment config
├── Routes/
│   ├── KeyRoutes.swift        # NUT-01, NUT-02
│   ├── SwapRoutes.swift       # NUT-03
│   ├── MintRoutes.swift       # NUT-04
│   ├── MeltRoutes.swift       # NUT-05, NUT-08
│   ├── CheckRoutes.swift      # NUT-07
│   └── RestoreRoutes.swift    # NUT-09
├── Services/
│   ├── KeysetManager.swift    # Keyset generation/rotation
│   ├── SigningService.swift   # BDHKE blind signing
│   ├── ProofValidator.swift   # Proof verification
│   ├── SpentProofStore.swift  # Double-spend prevention
│   ├── QuoteManager.swift     # Quote lifecycle
│   └── FeeCalculator.swift    # Fee computation
├── Lightning/
│   ├── LightningBackend.swift # Protocol
│   ├── LNDBackend.swift       # LND REST client
│   └── MockLightningBackend.swift
├── Models/
│   ├── Database/              # Fluent models
│   └── API/                   # Request/response types
├── Migrations/
│   └── CreateTables.swift     # Database schema
├── Middleware/
│   └── ErrorMiddleware.swift  # Cashu error formatting
└── SwiftCashuMint.swift       # CLI entry point
```

## Security

- Never run with real funds on mainnet until fully tested
- Always test on testnet/signet first
- Database backups are critical - spent proofs cannot be recreated
- The `spent_proofs` table has a unique constraint on `Y` to prevent double-spending

## License

MIT
