# E2E Test Suite Ready

## Test Runner
- Command: `xcodebuild -project HitRate.xcodeproj -scheme HitRate -destination 'platform=iOS Simulator,name=iPhone 17' build && xcrun simctl install booted /Users/ianrichardson/Library/Developer/Xcode/DerivedData/HitRate-ehzkrjprviksdsfluymjsrngrhku/Build/Products/Debug-iphonesimulator/HitRate.app && xcrun simctl launch booted com.ianrichardson.HitRate --run-e2e-tests`
- Expected: all tests pass with exit code 0

## Coverage Summary
| Tier | Count | Description |
|------|------:|-------------|
| 1. Feature Coverage | 20 | Setup stepper inputs, goal gradient math, ephemeral isolation, custom outcomes, summary Canvas tape, exit warnings |
| 2. Boundary & Corner | 20 | Stepper boundaries, goal rate bounds, empty renames, custom outcome empty fallbacks, Canvas tape sizes, paywall limits |
| 3. Cross-Feature | 4 | Large mat isolation, customized names in summary/cards, custom outcomes archived, stats & milestones sync |
| 4. Real-World Application | 5 | Woodward '26 camp workflow, Camp with Discard, Low Reps edge, display customization, multi-team co-existence |
| **Total** | **49** | |

## Feature Checklist
| Feature | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---------|:------:|:------:|:------:|:------:|
| R1: Zero-Setup Entry & Defaults | 5 | 5 | ✓ | ✓ |
| R2: Ephemeral Isolation & Inline Rename | 5 | 5 | ✓ | ✓ |
| R3: Wrap-Up Summary & Free Cards | 5 | 5 | ✓ | ✓ |
| R4: Loss Aversion Warning & Archive | 5 | 5 | ✓ | ✓ |
