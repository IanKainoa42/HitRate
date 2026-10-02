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
