import CoreGraphics

/// Features triggered by holding a modifier key (while scrolling, or for Precise Sensitivity while
/// moving the pointer), in priority order:
/// when two enabled features share a key, the earlier one wins and the later one is blocked.
enum ScrollModifierFeature: Int, CaseIterable, Comparable {
    case zoom
    case horizontal
    case fast
    case preciseSensitivity

    var title: String {
        switch self {
        case .zoom: return "Zoom"
        case .horizontal: return "Horizontal Scroll"
        case .fast: return "Fast Scroll"
        case .preciseSensitivity: return "Precision Mode"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ScrollModifierConfig {
    let feature: ScrollModifierFeature
    let isEnabled: Bool
    let key: String
}

enum ScrollModifiers {
    static let fastMultiplier = 3.0

    static func flag(for key: String) -> CGEventFlags? {
        switch key {
        case "Command": return .maskCommand
        case "Option": return .maskAlternate
        case "Control": return .maskControl
        case "Shift": return .maskShift
        default: return nil
        }
    }

    /// Maps each blocked feature to the higher-priority feature that uses the same key.
    static func conflicts(_ configs: [ScrollModifierConfig]) -> [ScrollModifierFeature: ScrollModifierFeature] {
        var owners: [String: ScrollModifierFeature] = [:]
        var blocked: [ScrollModifierFeature: ScrollModifierFeature] = [:]
        for config in configs.sorted(by: { $0.feature < $1.feature }) {
            guard config.isEnabled, flag(for: config.key) != nil else { continue }
            if let owner = owners[config.key] {
                blocked[config.feature] = owner
            } else {
                owners[config.key] = config.feature
            }
        }
        return blocked
    }

    /// Features whose key is held and that aren't blocked by a higher-priority feature.
    static func activeFeatures(_ configs: [ScrollModifierConfig], flags: CGEventFlags) -> Set<ScrollModifierFeature> {
        let blocked = conflicts(configs)
        var active = Set<ScrollModifierFeature>()
        for config in configs where config.isEnabled && blocked[config.feature] == nil {
            if let flag = flag(for: config.key), flags.contains(flag) {
                active.insert(config.feature)
            }
        }
        return active
    }
}
