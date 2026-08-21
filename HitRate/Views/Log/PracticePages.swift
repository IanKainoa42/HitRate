import SwiftUI
import SwiftData
import CheerRulesKit

// The nine-pocket pages feature: build a page of up to nine cards (a saved
// lineup, like a slotted card-binder page), then run the whole page at
// practice — every pocket logs reps for its card into the same session.
// Training-floor register throughout: these are app UI, not share cards.

// MARK: - Pre-practice chooser

/// Shown from the practice pill when the team has saved pages: run a page,
/// run the freeform counter, or manage pages. Presentation timing (opening
/// the cover AFTER this sheet dismisses) is the caller's job.
struct PracticeStartSheet: View {
    let pages: [PracticePage]
    let groups: [StuntGroup]
    let onFreeform: () -> Void
    let onRunPage: (PracticePage) -> Void
    let onNewPage: () -> Void
    let onEditPage: (PracticePage) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Theme.kicker("START PRACTICE")
                .padding(.top, 18)

            Button {
                dismiss()
                onFreeform()
            } label: {
                HStack(spacing: 9) {
                    BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                    Text("FREEFORM COUNTER")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                    Spacer()
                    Text("THE FULL GRID")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .opacity(0.7)
                }
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Theme.kicker("PAGES")
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(pages) { page in
                        pageRow(page)
                    }
                    Button {
                        dismiss()
                        onNewPage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("NEW PAGE")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1.2)
                            Spacer()
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .wellBackground()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FloorBackdrop().ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pageRow(_ page: PracticePage) -> some View {
        let slotted = page.slots(in: groups)
        return Button {
            dismiss()
            onRunPage(page)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Text("\(slotted.count) card\(slotted.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Theme.label3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .wellBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                dismiss()
                onEditPage(page)
            } label: { Label("Edit page", systemImage: "pencil") }
            Button(role: .destructive) {
                page.deletedAt = .now
                try? context.save()
            } label: { Label("Move to Trash", systemImage: "trash") }
        }
    }
}

// MARK: - Page builder

/// A card minted inside the builder. Held in local state until Save so a
/// cancelled build never strands a zero-rep skill on the roster (the ladder
/// renders those as MINTED cards in the share deck). Its UUID is chosen up
/// front so it can sit in `slotIDs` beside real skills.
private struct FreshCard: Identifiable {
    let id: UUID
    let name: String
    let category: SkillCategory
}

/// One occupied pocket — an existing card, or one minted here and not yet saved.
private enum Pocket: Identifiable {
    case existing(StuntGroup)
    case fresh(FreshCard)

    var id: UUID {
        switch self {
        case .existing(let g): g.id
        case .fresh(let c): c.id
        }
    }
    var name: String {
        switch self {
        case .existing(let g): g.displayName
        case .fresh(let c): c.name
        }
    }
    var isFresh: Bool { if case .fresh = self { true } else { false } }
}

/// Build or edit a page: name it, then fill the 3×3 grid — either from the
/// folder's existing deck or by minting a brand-new card right here. Tapping a
/// filled pocket removes it; the + pocket opens the picker below.
struct PageBuilderView: View {
    let team: Team?
    var existing: PracticePage? = nil
    var nextOrderIndex: Int = 0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // The builder can MINT skills, so it can't run off a roster snapshot passed
    // down from Home — a card created here has to resolve into its pocket on
    // the same render. House rule: every view that reads groups queries them.
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]

    @State private var name = ""
    @State private var slotIDs: [UUID] = []
    @State private var fresh: [FreshCard] = []
    @State private var newName = ""
    @State private var picking = false
    @State private var seeded = false
    @FocusState private var mintFocused: Bool

    private var groups: [StuntGroup] { allGroups.inTeam(team) }

    private var available: [StuntGroup] {
        groups.filter { !slotIDs.contains($0.id) }
    }

    private var isFull: Bool { slotIDs.count >= PracticePage.capacity }

    /// Pockets in slot order, resolving each id to a real card or a fresh one.
    private var pockets: [Pocket] {
        slotIDs.compactMap { id in
            if let g = groups.first(where: { $0.id == id }) { return .existing(g) }
            if let c = fresh.first(where: { $0.id == id }) { return .fresh(c) }
            return nil
        }
    }

    /// The suggested skill names, shared with the intro's mint screen. Each
    /// carries its United category — that's what sets the card's outcome words
    /// and drivers, and what decides whether a page run's armed severity can
    /// trust the slot index, so it is never cosmetic.
    private var suggestionBank: [(name: String, category: SkillCategory)] {
        OnboardingFocus.allCases.flatMap { f in
            f.suggestions.map { (name: $0, category: f.category) }
        }
    }

    private var takenNames: Set<String> {
        Set(groups.map { $0.name.lowercased() }).union(fresh.map { $0.name.lowercased() })
    }

    /// Suggestions narrowed by what's typed so far, minus anything already on
    /// the roster or already minted in this build.
    private var suggestions: [(name: String, category: SkillCategory)] {
        let q = newName.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = takenNames
        return suggestionBank.filter { s in
            !taken.contains(s.name.lowercased())
                && (q.isEmpty || s.name.lowercased().contains(q))
        }
        .prefix(6)
        .map { $0 }
    }

    private var canMintTyped: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !isFull && !takenNames.contains(trimmed.lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TextField("", text: $name,
                      prompt: Text("Page name (e.g. Tuesday Full-Out)")
                        .foregroundStyle(Theme.label3))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
                .tint(Theme.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .wellBackground()

            pocketGrid

            if picking {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        mintRow
                        if !available.isEmpty {
                            Theme.kicker("ADD FROM YOUR DECK")
                                .padding(.top, 4)
                            deckChips
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FloorBackdrop().ignoresSafeArea())
        .onAppear {
            guard !seeded else { return }
            seeded = true
            if let existing {
                name = existing.name
                // Prune slots whose skill was deleted/trashed since the page
                // was built — otherwise invisible dangling ids eat pocket
                // capacity forever.
                let live = Set(groups.map(\.id))
                slotIDs = existing.slotIDs.filter { live.contains($0) }
            } else {
                picking = true
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label2)
                .buttonStyle(.plain)
            Spacer()
            Text(existing == nil ? "NEW PAGE" : "EDIT PAGE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.label2)
            Spacer()
            Button("Save") { save() }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(slotIDs.isEmpty ? Theme.label3 : Theme.accent)
                .buttonStyle(.plain)
                .disabled(slotIDs.isEmpty)
        }
        .padding(.top, 16)
    }

    private var pocketGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  spacing: 8) {
            ForEach(pockets) { p in
                filledPocket(p)
            }
            if !isFull {
                addPocket
            }
            ForEach(0..<max(0, PracticePage.capacity - slotIDs.count - 1), id: \.self) { _ in
                emptyPocket
            }
        }
    }

    private func filledPocket(_ p: Pocket) -> some View {
        Button {
            remove(p.id)
        } label: {
            VStack(spacing: 5) {
                Text(p.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                if p.isFresh {
                    Text("NEW")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                }
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .wellBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(p.name) from this page")
    }

    /// The pop-up text line behind the + pocket: type a card name (suggestions
    /// narrow as you type) and it drops straight into the next pocket. The card
    /// is only actually minted on Save.
    private var mintRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Theme.kicker("MINT A NEW CARD")
            HStack(spacing: 8) {
                TextField("", text: $newName,
                          prompt: Text("Name a skill…").foregroundStyle(Theme.label3))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .tint(Theme.accent)
                    .focused($mintFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { mintTyped() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .wellBackground()
                Button { mintTyped() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canMintTyped ? Theme.accentText : Theme.label3)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canMintTyped ? Theme.accent : Theme.well))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canMintTyped)
            }
            if !suggestions.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(suggestions, id: \.name) { s in
                        Button {
                            mint(s.name, category: s.category)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text(s.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.label2)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .wellBackground(cornerRadius: 999)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFull)
                    }
                }
            }
        }
    }

    private var addPocket: some View {
        Button {
            picking = true
            mintFocused = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                Text("ADD")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .wellBackground()
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Theme.accent.opacity(0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyPocket: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(Theme.label3.opacity(0.35))
            .frame(height: 88)
    }

    private var deckChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(available, id: \.persistentModelID) { g in
                Button {
                    guard !isFull else { return }
                    slotIDs.append(g.id)
                } label: {
                    Text(g.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.label)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .wellBackground(cornerRadius: 999)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Minting

    private func mint(_ rawName: String, category: SkillCategory) {
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isFull, !takenNames.contains(trimmed.lowercased()) else { return }
        let card = FreshCard(id: UUID(), name: trimmed, category: category)
        fresh.append(card)
        slotIDs.append(card.id)
        newName = ""
    }

    private func mintTyped() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        // A typed name that matches a known skill keeps that skill's United
        // category rather than falling back to the stunts default.
        let match = suggestionBank.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        mint(trimmed, category: match?.category ?? .stunts)
    }

    private func remove(_ id: UUID) {
        slotIDs.removeAll { $0 == id }
        // An un-slotted fresh card is discarded outright — it was never a real
        // skill, and keeping it would hide its name from the suggestions.
        fresh.removeAll { $0.id == id }
    }

    private func save() {
        // Mint the new cards that actually made it into a pocket, keeping the
        // ids they were slotted under.
        var number = (groups.map(\.number).max() ?? 0) + 1
        var order = (groups.map(\.orderIndex).max() ?? -1) + 1
        for card in fresh where slotIDs.contains(card.id) {
            let g = StuntGroup(name: card.name, number: number, orderIndex: order, id: card.id)
            g.category = card.category
            g.team = team
            context.insert(g)
            number += 1
            order += 1
        }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.name = trimmed.isEmpty ? existing.name : trimmed
            existing.slotIDs = slotIDs
        } else {
            let page = PracticePage(name: trimmed.isEmpty ? "Page \(nextOrderIndex + 1)" : trimmed,
                                    orderIndex: nextOrderIndex)
            page.team = team
            page.slotIDs = slotIDs
            context.insert(page)
        }
        try? context.save()
        dismiss()
    }
}
