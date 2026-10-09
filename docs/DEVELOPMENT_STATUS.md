# Development Status

Last updated: 2026-10-09

## Current stage

**Stage: Initial documentation and architecture.**

The repository has been created and the first planning documents are being added. The documentation describes the intended system, not a completed implementation.

## Milestones

| Area | Status | Notes |
|---|---|---|
| Project overview | Documented | Initial vision and scope recorded |
| Architecture | Documented | Proposed modules and boundaries recorded |
| Contract specifications | Drafted | Requires decisions and review before implementation is finalized |
| Asset support policy | Drafted | No production asset registry yet |
| Security checklist | Drafted | Not an audit |
| Smart contracts | Not yet verified in this repository | Existing working copies, if any, must be reviewed and ported carefully |
| DEX adapter | Not implemented/verified here | A real protocol-specific integration is required |
| Tests | Not yet verified in this repository | Must be added and run |
| Indexer/API | Planned | Off-chain service design and implementation remain outstanding |
| Deployment | Not deployed by this repository's documented workflow | No production deployment claimed |
| Audit | Not audited | No independent audit claimed |

## Next actions

1. Confirm the initial documentation is in place.
2. Decide the target EVM network and development toolchain.
3. Review the current PaymentSystem, EscrowManager, and TradeExecutor code against the documented requirements.
4. Resolve design decisions about fees, trade lifecycle, supported tokens, and privileged roles.
5. Add the contracts and a reproducible build/test setup.
6. Implement a test suite before any real-fund use.

Update this document whenever a milestone changes, and link to test runs or review evidence when available.
