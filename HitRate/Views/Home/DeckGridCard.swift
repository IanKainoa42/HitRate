import SwiftUI

enum DeckSharingState: Equatable {
    case privateDeck
    case shared
    case joined

    var accessibilitySuffix: String? {
        switch self {
        case .privateDeck: nil
        case .shared: "shared deck"
        case .joined: "joined deck"
        }
    }

    var badgeLabel: String? {
        switch self {
        case .privateDeck: nil
        case .shared: "SHARED"
        case .joined: "JOINED"
        }
    }

    static func resolve(isOwner: Bool, isShared: Bool) -> Self {
        guard isOwner else { return .joined }
        return isShared ? .shared : .privateDeck
    }
}

enum DeckGridCardCopy {
    static func summary(skillCount: Int, repCount: Int) -> String {
        "\(skillCount) skill\(skillCount == 1 ? "" : "s") · "
        + "\(repCount) rep\(repCount == 1 ? "" : "s")"
    }

    static func accessibilityLabel(
        name: String,
        skillCount: Int,
        repCount: Int,
        sharingState: DeckSharingState
    ) -> String {
        let counts = summary(skillCount: skillCount, repCount: repCount)
            .replacingOccurrences(of: " · ", with: ", ")
        return ["\(name) deck", counts, sharingState.accessibilitySuffix]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// One user-defined collection rendered as a restrained stack of portrait
/// cards. It owns presentation and actions only; SwiftData stays in the parent.
struct DeckGridCard: View {
    let name: String
    let summary: FolderSummaryIndex.Summary
    let sharingState: DeckSharingState
    let isActive: Bool
    let canTrash: Bool
    let onOpen: () -> Void
    let onShare: (() -> Void)?
    let onRename: () -> Void
    let onTrash: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                deckLayer
                    .offset(x: 6, y: 7)
                    .opacity(0.42)
                deckLayer
                    .offset(x: 3, y: 4)
                    .opacity(0.72)
                cover
            }
            .aspectRatio(0.69, contentMode: .fit)
            .padding(.trailing, 6)
            .padding(.bottom, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeckGridCardCopy.accessibilityLabel(
            name: name,
            skillCount: summary.skillCount,
            repCount: summary.repCount,
            sharingState: sharingState
        ))
        .accessibilityHint("Opens this deck")
        .accessibilityAction(named: "Rename", onRename)
        .modifier(OptionalShareAccessibilityAction(action: onShare))
        .modifier(OptionalTrashAccessibilityAction(
            action: canTrash ? onTrash : nil
        ))
        .contextMenu { contextMenu }
    }

    private var deckLayer: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Theme.iconTile)
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.iconTileEdge.opacity(0.9), lineWidth: 1)
            }
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Theme.well)
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isActive ? Theme.label3.opacity(0.9) : Theme.iconTileEdge,
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DECK")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label3)

                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 10)

                    if let badge = sharingState.badgeLabel {
                        Text(badge)
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.1)
                            .foregroundStyle(Theme.label2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Theme.iconTile)
                                    .overlay {
                                        Capsule().strokeBorder(
                                            Theme.iconTileEdge.opacity(0.8),
                                            lineWidth: 1
                                        )
                                    }
                            )
                    }

                    Text(DeckGridCardCopy.summary(
                        skillCount: summary.skillCount,
                        repCount: summary.repCount
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }
                .padding(14)
            }
            .shadow(color: .black.opacity(0.24), radius: 8, y: 5)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        if let onShare {
            Button(action: onShare) {
                Label(
                    sharingState == .shared ? "Sharing code" : "Share deck",
                    systemImage: "person.2.fill"
                )
            }
        }
        if canTrash {
            Button(role: .destructive, action: onTrash) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

private struct OptionalShareAccessibilityAction: ViewModifier {
    let action: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: "Share", action)
        } else {
            content
        }
    }
}

private struct OptionalTrashAccessibilityAction: ViewModifier {
    let action: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: "Move to Trash", action)
        } else {
            content
        }
    }
}

struct NewDeckGridCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    Theme.iconTileEdge,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
                .aspectRatio(0.69, contentMode: .fit)
                .overlay {
                    VStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                        Text("NEW DECK")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.3)
                        Text("Organize it your way")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.label2)
                }
                .padding(.trailing, 6)
                .padding(.bottom, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New deck")
        .accessibilityHint("Creates another deck or explains the coach plan")
    }
}
