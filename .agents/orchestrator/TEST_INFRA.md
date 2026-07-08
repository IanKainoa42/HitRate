# E2E Test Infra: Quick Clinic / Guest Coach

## Test Philosophy
- Opaque-box, requirement-driven.
- Verifies database isolation, UI defaults, outcome customization, wrap-up sheets, and premium archiving.
- Uses command-line arguments (`--run-e2e-tests`) to invoke tests on the simulator and write results to `/tmp/hitrate-test-results.json` on the macOS host.

## Feature Inventory
| # | Feature | Source | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|---|
| 1 | R1: Zero-Setup Entry & Smart Defaults | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | R2: Ephemeral Isolation & Personalization | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 3 | R3: Reciprocity Wrap-Up Sheet & Share Cards | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 4 | R4: Ethical Loss Aversion & Anchored Pro | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |

## Test Architecture
- **Test Runner**: Activated via command-line argument `--run-e2e-tests`. App executes tests on launch, writes a JSON report to `/tmp/hitrate-test-results.json`, and exits.
- **Verification Script**: Host shell command that launches the booted simulator with `--run-e2e-tests`, waits for the file, parses it, and returns exit code 0 on success.

## Coverage Thresholds
- Tier 1 (Feature Coverage): 20 tests
- Tier 2 (Boundaries & Edge Cases): 20 tests
- Tier 3 (Cross-Feature Combinations): 4 tests
- Tier 4 (Real-World Application Scenarios): 5 tests
- **Total: 49 test cases**
