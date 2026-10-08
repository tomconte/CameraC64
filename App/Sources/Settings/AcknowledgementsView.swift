import SwiftUI

/// Something Camera C64 includes from others, as the table in
/// THIRD_PARTY_NOTICES.md lists it. Its texts are inline Markdown.
nonisolated struct Acknowledgement: Equatable, Sendable {
    var name: String
    var licence: String
    var use: String

    /// The rows of the table in THIRD_PARTY_NOTICES.md, so that the app shows
    /// the same list as the repository.
    static func included(inNotices notices: String) -> [Acknowledgement] {
        let tableLines = notices.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("|") }
        // The first two lines are the header and the separator.
        return tableLines.dropFirst(2).compactMap { line in
            let cells = line.dropFirst().split(separator: "|", omittingEmptySubsequences: false).dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 3 else { return nil }
            return Acknowledgement(name: cells[0], licence: cells[1], use: cells[2])
        }
    }
}

/// The acknowledgements (docs/UX.md, section 5): Camera C64's own licence,
/// and what it includes from others, read from the THIRD_PARTY_NOTICES.md and
/// LICENSE files that the app bundles.
struct AcknowledgementsView: View {
    private let acknowledgements = Acknowledgement.included(inNotices: Self.bundledText("THIRD_PARTY_NOTICES", "md"))
    private let licence = Self.bundledText("LICENSE", nil)

    var body: some View {
        Form {
            Section {
                Text(licence)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("Camera C64")
            } footer: {
                Text("Its source is at [github.com/tomconte/CameraC64](https://github.com/tomconte/CameraC64).")
            }
            Section {
                ForEach(acknowledgements, id: \.name) { acknowledgement in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.markdown(acknowledgement.name))
                            .font(.headline)
                        Text(Self.markdown(acknowledgement.licence))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Self.markdown(acknowledgement.use))
                            .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Included")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A text file that the app bundles, or empty if it is missing.
    static func bundledText(_ name: String, _ fileExtension: String?) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inline Markdown, such as links and code, or the text as it is if it
    /// isn't valid.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
