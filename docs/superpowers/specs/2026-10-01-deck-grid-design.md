# HitRate Deck Grid Design

## Purpose

Make HitRate's organization model immediately understandable by presenting each user-defined collection as a physical deck of cards. A deck can represent a team, athlete, season, private lesson, or any other grouping the user chooses. The design must make that metaphor clear without adding decorative navigation or changing how data is stored.

Success means a user can open HitRate, scan their decks in a conventional grid, distinguish them by name and summary, and tap one to reach the dashboard they already use.

## Scope

This redesign covers the launch collection screen and the user-facing terminology associated with that collection.

- Replace the current folder-row list with a two-column grid of deck cards.
- Replace user-facing `folder` language with `deck` in creation, joining, sharing, trash, account prompts, dashboard navigation, and related accessibility text.
- Keep the existing dashboard, logging, statistics, milestones, card sharing, sync, entitlement, and trash behavior.
- Keep each skill in exactly one deck.
- Keep `Team` as the underlying SwiftData and Firestore model. This avoids a storage migration and preserves existing local and shared data.

The redesign does not add cross-deck statistics, nested decks, seasons as a new data type, cards shared across multiple decks, drag-and-drop ordering, or custom deck artwork.

## Navigation

After onboarding, a cold launch opens the deck grid. Tapping a deck sets `currentTeamID` and opens the existing `HomeView` for that deck. The dashboard's back action returns to the grid.

Finishing onboarding continues to open the newly created deck directly so a first-time user can start immediately. Creating a new deck from the grid also opens that empty deck so the user can add skills. Join links and join codes retain their current behavior and add the joined deck to the same grid.

The existing `RootView` navigation state remains authoritative. No new navigation framework or persistent route state is introduced.

## Deck Grid

The screen stays in HitRate's graphite training-floor visual register. It uses a vertically scrolling `LazyVGrid` with two equal flexible columns and predictable row/column spacing.

Each grid item contains:

- A portrait card-shaped deck cover.
- Two thin, slightly offset card layers behind the cover.
- A soft, restrained shadow that supplies depth without glow or floating animation.
- The deck name on the cover, with a sensible line limit.
- A compact summary showing skill and rep counts.
- A subtle shared or joined state when applicable.

All decks have equal visual hierarchy. There is no featured deck, shelf, box-opening animation, dramatic tilt, or horizontally paged carousel. Green remains reserved for HitRate's go/hit/improving signal; deck covers use neutral training-floor tones rather than arbitrary status colors.

The final grid cell is always a card-proportioned `New Deck` affordance. When the user's entitlement permits another deck, tapping it starts creation; otherwise it presents the existing coach paywall. The existing `Join a deck with a code` action remains visible outside the grid so joining cannot be confused with creating.

## Deck Actions

Tapping the card opens the deck. Secondary operations remain outside the primary tap target:

- Share or view a sharing code.
- Rename.
- Move to Trash.

These operations may remain in a context menu, with the shared/joined state visible on the card. Buttons must not be nested inside the card's primary `Button`.

Moving a deck to Trash remains recoverable and retains all skills and reps. The confirmation message uses deck terminology and reports the affected counts. At least one active deck remains required, matching current behavior.

## Data and Compatibility

`Team` remains the source of truth for a deck. Existing `StuntGroup.team` relationships already enforce one-deck ownership for skills, and stats already scope themselves through the active team. No SwiftData schema or Firestore document shape changes are required.

Existing installs automatically see their current teams/folders as decks. IDs, join codes, ownership, memberships, sync listeners, tombstones, order indices, and `currentTeamID` remain unchanged.

Internal type and protocol names may continue to use `Team` or `Folder` where renaming would create migration or sync risk. User-visible strings, accessibility labels, and comments describing the product concept should use `deck`.

## Component Boundaries

`FolderListView` remains the launch collection screen but should be renamed only if that can be done without mixing in unrelated work. Its responsibilities remain querying decks, building summaries, presenting collection-level sheets, and routing selection through `onOpen`.

A focused reusable deck-card view owns the portrait stack rendering and visible summary. It receives display data and actions rather than querying SwiftData itself. This keeps visual iteration isolated from sync, entitlement, and navigation behavior.

`FolderSummaryIndex` continues to calculate skill and rep counts. `RootView` continues to own the open-deck route. Existing sharing, joining, entitlement, and account components remain the behavioral implementations behind the revised labels.

## Accessibility and Dynamic Content

Each deck card is one large primary tap target with an accessibility label containing the deck name, skill count, rep count, and shared/joined state. Rename, share, and trash actions remain separately discoverable through the context menu and accessibility actions.

Deck names support Dynamic Type, truncate only after using the available two-line cover area, and do not overlap summary information. The grid must remain usable with long names, zero counts, large counts, one deck, and an odd number of decks.

## Verification

Verification must cover:

- Build with the active supported Xcode toolchain.
- Cold launch lands on the deck grid for an onboarded user.
- Existing decks retain their skills, reps, sharing state, and ownership.
- Tapping every deck opens the matching dashboard rather than a fallback deck.
- Back navigation returns to the grid.
- Creating and joining a deck adds the correct grid item and opens/scopes it correctly.
- Rename and recoverable Trash flows use deck terminology and preserve data.
- Free-tier creation still presents the current paywall at the same boundary.
- Shared and joined decks remain distinguishable and their actions remain correct.
- Long names, empty decks, large counts, odd grid counts, and Dynamic Type remain readable.
- VoiceOver identifies each card and exposes its secondary operations.
- Simulator installation and launch confirm the rendered grid, card-stack depth, tap routing, and dashboard return path.

## Existing Work Protection

The checkout already contains uncommitted changes in `HitRateApp.swift`, `FolderListView.swift`, `WatchSessionBridge.swift`, and generated Xcode project files. Implementation must preserve those edits, including the in-progress `DeckIcon`, entitlement work, app delegate work, watch work, and generated schemes. Only feature-specific hunks should be staged and committed.
