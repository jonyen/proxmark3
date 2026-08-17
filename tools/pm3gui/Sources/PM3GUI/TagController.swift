import Foundation
import Observation

/// Drives the four actions the GUI exists for: connect, read, write, wipe.
@MainActor
@Observable
final class TagController {

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(name: String)
        case busy(String)

        var isBusy: Bool {
            switch self {
            case .connecting, .busy: return true
            case .disconnected, .connected: return false
            }
        }

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected(let name): return name
            case .busy(let what): return "\(what)…"
            }
        }
    }

    private let session = PM3Session()

    var status: Status = .disconnected
    var detectedPorts: [String] = []
    var selectedPort: String = ""
    /// The ID Read populated, and the one Write will clone. Editable as an override.
    var tagID: String = ""
    var log: [String] = []
    var lastError: String?

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var canWrite: Bool {
        isConnected && !status.isBusy && TagID.normalise(tagID) != nil
    }

    init() {
        refreshPorts()
    }

    func refreshPorts() {
        detectedPorts = DeviceFinder.findPorts()
        if selectedPort.isEmpty || !detectedPorts.contains(selectedPort) {
            selectedPort = detectedPorts.first ?? ""
        }
    }

    // MARK: - Actions

    func connect() async {
        refreshPorts()
        guard !selectedPort.isEmpty else {
            fail("No Proxmark3 found. Plug one in and press Rescan.")
            return
        }
        lastError = nil
        status = .connecting
        note("Opening \(selectedPort)")
        do {
            let name = try await session.open(port: selectedPort)
            status = .connected(name: name)
            note("Connected to \(name)")
            // hw status doubles as proof the link really works, not just that
            // the serial port opened.
            let result = try await session.console("hw status")
            note("Firmware responded (\(result.output.split(separator: "\n").count) lines)")
        } catch {
            status = .disconnected
            fail(error.localizedDescription)
        }
    }

    func disconnect() async {
        await session.close()
        status = .disconnected
        note("Disconnected")
    }

    func read() async {
        await perform("Reading") {
            let result = try await self.session.console("lf search")
            let outcome = PM3Output.parseRead(result.output)
            switch outcome {
            case .em410x(let id):
                self.tagID = id
                self.note("Read \(outcome.summary)")
            case .otherCredential, .blankChip, .nothing:
                self.note(outcome.summary)
            }
        }
    }

    func write() async {
        guard let id = TagID.normalise(tagID) else {
            fail("ID must be exactly 10 hex digits")
            return
        }
        await perform("Writing") {
            try await self.requireT55xx()
            let result = try await self.session.console("lf em 410x clone --id \(id)")
            guard PM3Output.writeSucceeded(result.output) else {
                throw PM3GUIError.commandFailed("Write did not report success")
            }
            self.note("Wrote \(id) to tag")
            // Read back, so success on screen means the tag actually carries the ID.
            let verify = try await self.session.console("lf search")
            if PM3Output.emID(in: verify.output) == id {
                self.note("Verified: tag reads back \(id)")
            } else {
                self.note("Written, but read-back did not match")
            }
        }
    }

    func wipe() async {
        await perform("Wiping") {
            try await self.requireT55xx()
            let result = try await self.session.console("lf t55xx wipe")
            guard PM3Output.wipeSucceeded(result.output) else {
                throw PM3GUIError.commandFailed("Wipe did not complete all blocks")
            }
            self.note("Wiped tag to default configuration")
        }
    }

    /// Both Write and Wipe are T55xx-only commands. Running them against, say,
    /// an EM4x05 card wastes time and reports failures that look like bugs, so
    /// confirm what is on the antenna first and say so plainly if it is wrong.
    private func requireT55xx() async throws {
        let detect = try await session.console("lf t55xx detect")
        guard let chip = PM3Output.t55xxChipType(in: detect.output) else {
            throw PM3GUIError.commandFailed(
                "No T55xx tag on the antenna. Write and Wipe only work on T5577."
            )
        }
        note("Tag is \(chip)")
        if PM3Output.passwordSet(detect.output) {
            throw PM3GUIError.commandFailed(
                "Tag is password protected; this app cannot write to it."
            )
        }
    }

    // MARK: - Plumbing

    private func perform(_ what: String, _ body: @escaping () async throws -> Void) async {
        guard isConnected else {
            fail("Connect to a Proxmark3 first")
            return
        }
        let previous = status
        lastError = nil
        status = .busy(what)
        do {
            try await body()
        } catch {
            fail(error.localizedDescription)
        }
        status = previous
    }

    private func note(_ message: String) {
        log.append(message)
    }

    private func fail(_ message: String) {
        lastError = message
        log.append("Error: \(message)")
    }
}

enum PM3GUIError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        }
    }
}
