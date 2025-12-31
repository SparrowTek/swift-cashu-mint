# Swift Cashu Mint Security Audit Checklist

This checklist covers security considerations for the Swift Cashu Mint. Complete all items before deploying to production.

## 1. Cryptographic Security

### Private Key Management
- [ ] Private keys are generated using CSPRNG (Cryptographically Secure Pseudo-Random Number Generator)
- [ ] Private keys are never logged or exposed in error messages
- [ ] Private keys are stored encrypted at rest in the database
- [ ] Key derivation follows NUT-02 specification exactly
- [ ] Keyset rotation is tested and documented

### Blind Signature Security (BDHKE)
- [ ] Blind signature implementation matches NUT-00 specification
- [ ] Hash-to-curve implementation is constant-time
- [ ] No timing side channels in signature verification
- [ ] DLEQ proofs (NUT-12) implementation verified if enabled

## 2. Double-Spend Prevention

### Database Constraints
- [ ] `spent_proofs.y` has UNIQUE constraint enforced at database level
- [ ] `pending_proofs.y` has UNIQUE constraint enforced at database level
- [ ] Proof marking is atomic (all-or-nothing transaction)
- [ ] Database isolation level is sufficient (SERIALIZABLE for critical operations)

### Concurrent Access
- [ ] Race conditions tested with concurrent swap/melt requests
- [ ] Proof status checks and marking are atomic
- [ ] Pending proof timeout/cleanup is implemented
- [ ] Double-spend attempts are logged and monitored

## 3. Input Validation

### Hex String Validation
- [ ] All hex inputs validated for correct format
- [ ] Even-length hex strings enforced
- [ ] Invalid hex characters rejected

### Public Key Validation
- [ ] Public keys validated as valid curve points
- [ ] Compressed key prefix (02/03) validated
- [ ] Key length bounds enforced (66-130 chars)

### Amount Validation
- [ ] All amounts are positive integers
- [ ] Amounts within configured min/max limits
- [ ] Transaction balance verified: inputs - fees = outputs
- [ ] Overflow protection on amount calculations

### Quote ID Validation
- [ ] Quote IDs validated as alphanumeric
- [ ] Quote ID length bounds enforced
- [ ] No path traversal or injection possible

### Request Size Limits
- [ ] Maximum request body size enforced (default: 1MB)
- [ ] Maximum number of inputs enforced (default: 1000)
- [ ] Maximum number of outputs enforced (default: 1000)

## 4. API Security

### Rate Limiting
- [ ] Rate limiting enabled per IP address
- [ ] Stricter limits on sensitive endpoints (swap, mint, melt)
- [ ] Rate limit exceeded returns proper 429 status
- [ ] Rate limit headers included in responses

### Error Handling
- [ ] Internal errors do not leak sensitive information
- [ ] Stack traces not exposed to clients
- [ ] Error codes match NUT specification
- [ ] All errors are logged with context

### HTTPS/TLS
- [ ] TLS 1.2+ enforced for production
- [ ] Valid SSL certificate configured
- [ ] HSTS headers configured (if applicable)

## 5. Lightning Backend Security

### LND Configuration
- [ ] Macaroon permissions are minimal (invoice, payment only)
- [ ] Macaroon file permissions are restricted (600)
- [ ] TLS certificate verified for LND connection
- [ ] Connection timeout configured

### Payment Handling
- [ ] Maximum payment amount enforced
- [ ] Fee reserve calculation is safe (no underflow)
- [ ] Payment timeout prevents stuck funds
- [ ] Failed payments properly cleaned up

## 6. Database Security

### Connection Security
- [ ] SSL required for non-localhost connections
- [ ] Connection string not logged
- [ ] Password not exposed in error messages
- [ ] Connection pooling limits configured

### Data Protection
- [ ] Private keys encrypted before storage
- [ ] Sensitive fields (secrets, witnesses) handled carefully
- [ ] Database backups encrypted
- [ ] Point-in-time recovery tested

### Access Control
- [ ] Database user has minimal required permissions
- [ ] No direct database access from untrusted networks
- [ ] Prepared statements used (SQL injection prevention)

## 7. Operational Security

### Logging
- [ ] Structured logging enabled for production
- [ ] Sensitive data redacted from logs
- [ ] Audit logging for financial operations
- [ ] Log retention policy configured

### Monitoring
- [ ] Health check endpoint functional
- [ ] Database connectivity monitored
- [ ] Lightning backend connectivity monitored
- [ ] Rate limit exhaustion alerts configured

### Deployment
- [ ] Environment variables used for secrets
- [ ] Secrets not committed to version control
- [ ] Container runs as non-root user
- [ ] No unnecessary ports exposed

## 8. Testnet First Policy

Before any mainnet deployment:
- [ ] All functionality tested on testnet/signet
- [ ] Interoperability tested with nutshell wallet
- [ ] Interoperability tested with cashu.me
- [ ] Load testing performed
- [ ] Failure scenarios tested (network issues, database failures)

## 9. Pre-Production Checklist

### Code Review
- [ ] Security-focused code review completed
- [ ] No TODO/FIXME items in security-critical code
- [ ] All tests passing

### Configuration
- [ ] Production configuration reviewed
- [ ] Default passwords/secrets changed
- [ ] Limits appropriate for production load

### Documentation
- [ ] Runbook for common operations created
- [ ] Incident response procedure documented
- [ ] Backup/recovery procedure tested

## 10. Post-Deployment Monitoring

### Immediate (First 24 hours)
- [ ] Monitor for unusual error rates
- [ ] Monitor for rate limit exhaustion
- [ ] Verify Lightning connectivity stable
- [ ] Check database performance metrics

### Ongoing
- [ ] Regular security updates applied
- [ ] Keyset rotation schedule established
- [ ] Backup verification schedule established
- [ ] Periodic security review scheduled

---

## Severity Levels

- **CRITICAL**: Must fix before any deployment (double-spend, key exposure)
- **HIGH**: Must fix before production deployment (input validation gaps)
- **MEDIUM**: Should fix before significant exposure (logging improvements)
- **LOW**: Nice to have (additional monitoring)

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| Security Reviewer | | | |
| Operations | | | |

---

*Last Updated: December 2025*
*Applicable to: Swift Cashu Mint v0.1.0*
