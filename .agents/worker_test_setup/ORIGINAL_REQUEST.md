## 2026-07-07T12:05:05-07:00
You are a Worker subagent. Your task is to implement the E2E Test Suite for the Quick Clinic / Guest Coach workflow, including the test file and the launch hook.

Your working directory is: `/Users/ianrichardson/Projects/HitRate/.agents/worker_test_setup/`. Please keep a heartbeat via `progress.md` in your directory.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Please perform the following actions:
1. Create a new Swift file `HitRate/Views/QuickClinic/QuickClinicTests.swift`.
   Inside this file, implement a static method `runAndExit()` that:
   - Configures an in-memory `ModelContainer` representing the clinic ephemeral store.
   - Configures another in-memory `ModelContainer` representing the app's standard SQLite store (for migration tests).
   - Implements 49 distinct assertions/test cases across 4 Tiers:
     - Tier 1: Feature Coverage (20 assertions checking setup sheet stepper inputs, goal gradient progress bar math, ephemeral isolation, renaming, outcome customization replication, summary Canvas tape loading, free holo cards rendering, exit warning logic, Pro paywall UI model, archiving migration).
     - Tier 2: Boundary & Corner Cases (20 assertions checking stepper boundaries [1 to 12 mats], goal rate boundaries [50% to 95%], empty rename resets, custom outcome empty fallbacks, milestones not polluted by ephemeral reps, Canvas tape with 0/1/many reps, image renderer robust with empty names, archive with 0 attempts).
     - Tier 3: Cross-Feature Combinations (4 assertions checking R1+R2 large mat/isolation, R2+R3 custom names in summary/share cards, R2+R4 custom outcomes archived to SQLite, R1+R4 stats & milestones sync after upgrade).
     - Tier 4: Real-World Scenarios (5 assertions testing Camp Coach Woodward '26 workflow, Camp with Discard, Low Reps edge, Outcome customization grid/tape display, and Multi-team standard session co-existence).
   - If all 49 assertions pass, write a JSON test report to `/tmp/hitrate-test-results.json` showing a summary and details of the tests, and print `** TEST SUITE PASSED **` to stdout, then call `exit(0)`.
   - If any assertion fails, print the failure details to stderr, write the failure report to `/tmp/hitrate-test-results.json`, and call `exit(1)`.

2. Modify `HitRate/HitRateApp.swift` to invoke `QuickClinicTests.runAndExit()` in `init()` if `CommandLine.arguments.contains("--run-e2e-tests")` is true.

3. Verify that the project generates and builds successfully on the simulator target:
   - Run `xcodegen generate`.
   - Run `xcodebuild -project HitRate.xcodeproj -scheme HitRate -destination 'platform=iOS Simulator,name=iPhone 17' build`.

4. Report the paths of files created or modified, the compilation status, and any warnings. When finished, write your handoff and send a completion message.
