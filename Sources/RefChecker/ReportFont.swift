import SwiftUI

/// Scale of all text in the main (report) panel, set from Settings › Text size.
private struct ReportFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var reportFontScale: CGFloat {
        get { self[ReportFontScaleKey.self] }
        set { self[ReportFontScaleKey.self] = newValue }
    }
}

extension Font {
    /// macOS text-style sizes, multiplied by `scale` (SwiftUI's text styles do not scale on macOS).
    static func rf(_ style: Font.TextStyle, _ scale: CGFloat, _ weight: Font.Weight? = nil,
                   monospacedDigits: Bool = false) -> Font {
        let base: CGFloat
        var defaultWeight: Font.Weight = .regular
        switch style {
        case .largeTitle: base = 26
        case .title: base = 22
        case .title2: base = 17
        case .title3: base = 15
        case .headline: base = 13; defaultWeight = .bold
        case .subheadline: base = 11
        case .callout: base = 12
        case .footnote, .caption, .caption2: base = 10
        default: base = 13
        }
        let font = Font.system(size: (base * scale).rounded(), weight: weight ?? defaultWeight)
        return monospacedDigits ? font.monospacedDigit() : font
    }
}

enum TextSize {
    static let referenceListDefault = 12.0
    static let reportDefault = 13.0
}
