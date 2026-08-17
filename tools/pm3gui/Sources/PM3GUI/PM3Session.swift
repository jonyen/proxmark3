import Foundation
import CPM3

enum PM3Error: LocalizedError {
    case openFailed(port: String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .openFailed(let port): return "Could not open \(port)"
        case .notConnected: return "Not connected"
        }
    }
}

/// The captured result of one `pm3_console` call.
///
/// `code` is the library's return value. It is *not* a found/not-found signal —
/// `lf search` returns -10 while still reporting a chipset it recognised — so
/// callers should parse `output` and treat `code` only as a transport hint.
struct ConsoleResult {
    let command: String
    let code: Int32
    let output: String
}

/// Serialised access to libpm3.
///
/// The library keeps a single global current device and its console call blocks
/// for as long as the operation takes (seconds, for an LF search), so every
/// call is funnelled onto one dedicated thread and awaited from the UI.
final class PM3Session: @unchecked Sendable {

    private let queue = DispatchQueue(label: "org.proxmark3.gui.device")
    private var device: OpaquePointer?

    var isConnected: Bool {
        queue.sync { device != nil }
    }

    func open(port: String) async throws -> String {
        try await run {
            if self.device != nil {
                pm3_close(self.device)
                self.device = nil
            }
            guard let dev = port.withCString({ pm3_open($0) }) else {
                throw PM3Error.openFailed(port: port)
            }
            self.device = dev
            return pm3_name_get(dev).map(String.init(cString:)) ?? port
        }
    }

    func close() async {
        try? await run {
            if let dev = self.device {
                pm3_close(dev)
                self.device = nil
            }
            return ()
        }
    }

    func console(_ command: String) async throws -> ConsoleResult {
        try await run {
            guard let dev = self.device else { throw PM3Error.notConnected }
            let code = command.withCString { pm3_console(dev, $0, true, true) }
            let output = pm3_grabbed_output_get(dev).map(String.init(cString:)) ?? ""
            return ConsoleResult(command: command, code: code, output: output)
        }
    }

    private func run<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
