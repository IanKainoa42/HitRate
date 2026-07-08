# Project Context

## Workspace Information
- **Path**: /Users/ianrichardson/Projects/HitRate
- **Repository**: HitRate
- **Bundle ID**: com.ianrichardson.HitRate

## Key Architectural Concepts (from AGENTS.md)
- **AppMode**: athlete/coach, stores buckets as `StuntGroup`.
- **xcodegen**: owns the project and `Info.plist`. Edit `project.yml`, run `xcodegen generate` to build.
- **Rarity**: dynamic, based on difficulty tier, not hit rate. Stat cards are flat.
- **App UI ("training floor")**: Graphite `FloorBackdrop`, inset wells, green accent `0x34D26A`, Barlow Condensed font for numerals.
- **Onboarding/Share Cards ("court at night")**: Navy `CourtBackdrop`, coral/electric colors, Space Grotesk font.
- **LogView layouts**: Pad (pick one group, tap 4 outcome wells) and Grid (matrix log for single-kind). Grid matches coach mode.
- **OutcomeNames**: @Observable model wrapping outcome names (e.g. stunt/tumbling).

## Active Tasks
- Initializing Phase 1 (Exploration) to map out how the Quick Clinic will integrate into these components.
