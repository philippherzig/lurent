import Foundation

/// Shorthand for a localized string from `Localizable.strings` (main bundle),
/// with optional `String(format:)` arguments.
///
/// German is the development/base language: the keys are the German source
/// strings themselves, so a German user (or any unsupported language) falls back
/// to the key verbatim. Every other supported language ships a `<lang>.lproj/
/// Localizable.strings` translating those keys.
///
/// SwiftUI `Text`/`Label`/`Section`/`Picker`/`.help` with *string literals*
/// localize on their own via `LocalizedStringKey`; this helper covers the spots
/// that can't — plain `String` values (enum labels, error/status messages) and
/// format strings with interpolated arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}
