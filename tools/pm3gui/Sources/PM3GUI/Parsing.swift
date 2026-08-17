import Foundation

/// Parsers for `lf` command output.
///
/// Every pattern here was taken from output captured off a real Proxmark3 and a
/// real T5577 — see `docs/pm3-gui/HANDOFF.md` for the transcripts.
enum PM3Output {

    /// What a `lf search` found.
    enum ReadOutcome: Equatable {
        /// A readable EM410x ID, the case the Write button copies from.
        case em410x(id: String)
        /// A credential this app cannot clone — HID Prox, Indala and friends.
        /// Worth naming rather than calling the tag empty.
        case otherCredential(kind: String, chipset: String?)
        /// A chip is on the antenna but carries no ID — typically a blank T5577.
        case blankChip(name: String)
        /// Nothing on the antenna.
        case nothing

        var summary: String {
            switch self {
            case .em410x(let id):
                return "EM410x \(id)"
            case .otherCredential(let kind, let chipset):
                let chip = chipset.map { " on \($0)" } ?? ""
                return "\(kind)\(chip) — not EM410x, cannot be cloned here"
            case .blankChip(let name):
                return "\(name) chip detected, but no EM410x ID on it"
            case .nothing:
                return "No tag found"
            }
        }
    }

    static func parseRead(_ output: String) -> ReadOutcome {
        if let id = emID(in: output) {
            return .em410x(id: id)
        }
        // `lf search` announces a hit it understood as "Valid <something> found!".
        // For EM410x that is handled above, so anything left is a credential
        // this app has no write path for.
        if let kind = validCredential(in: output) {
            return .otherCredential(kind: kind, chipset: chipset(in: output))
        }
        if let chip = chipset(in: output) {
            return .blankChip(name: chip)
        }
        return .nothing
    }

    /// `[+] Valid HID Prox ID found!`
    static func validCredential(in output: String) -> String? {
        firstMatch(of: #/Valid (.+?)(?: ID)? found!/#, in: output)
    }

    /// `[+] EM 410x ID 0102030405`
    static func emID(in output: String) -> String? {
        firstMatch(of: #/EM 410x ID ([0-9A-Fa-f]{10})/#, in: output)
    }

    /// `[+] Chipset... T55xx`, or `[+] Chipset... EM4x05 / EM4x69` — the name can
    /// contain spaces, so take the rest of the line rather than one word.
    static func chipset(in output: String) -> String? {
        firstMatch(of: #/Chipset\.*\s*([^\n]+)/#, in: output)?
            .trimmingCharacters(in: .whitespaces)
    }

    /// `lf t55xx detect` reports `Chip type......... T55x7` on success, and
    /// `Could not detect modulation automatically` on anything that is not a
    /// T55xx. This is the gate for Write and Wipe, both of which are T55xx-only.
    static func t55xxChipType(in output: String) -> String? {
        firstMatch(of: #/Chip type\.*\s*([^\n]+)/#, in: output)?
            .trimmingCharacters(in: .whitespaces)
    }

    /// `[#] Tag T55x7 written with 0xff8060280c048142` followed by `[+] Done!`
    static func writeSucceeded(_ output: String) -> Bool {
        output.contains("written with") || output.contains("Done!")
    }

    /// Wipe prints one line per block; page 0 has eight of them.
    static func wipeSucceeded(_ output: String) -> Bool {
        output.contains("block: 07")
    }

    /// A passworded tag cannot be written without the password, so surface it.
    static func passwordSet(_ output: String) -> Bool {
        firstMatch(of: #/Password set\.*\s*(\S+)/#, in: output) == "Yes"
    }

    /// The lines worth showing a human: drop the firmware chatter and hints,
    /// keep results and errors.
    static func interestingLines(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                return trimmed.hasPrefix("[+]") || trimmed.hasPrefix("[-]")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func firstMatch(
        of regex: Regex<(Substring, Substring)>, in output: String
    ) -> String? {
        guard let match = output.firstMatch(of: regex) else { return nil }
        return String(match.1)
    }
}

/// An EM410x ID is exactly 10 hex digits; the Write field is validated against
/// this before the command is built.
enum TagID {
    static func normalise(_ raw: String) -> String? {
        let cleaned = raw.filter { !$0.isWhitespace }.uppercased()
        guard cleaned.count == 10,
              cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return cleaned
    }
}
