import SwiftUI
import AppKit

struct ContentView: View {
    @State private var controller = TagController()
    @State private var confirmingWipe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionSection
            Divider()
            tagSection
            Divider()
            logSection
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 460)
        .confirmationDialog(
            "Wipe this tag?",
            isPresented: $confirmingWipe,
            titleVisibility: .visible
        ) {
            Button("Wipe Tag", role: .destructive) {
                Task { await controller.wipe() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every block on the tag is reset to defaults. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(controller.isConnected ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(controller.status.label)
                    .font(.headline)
                if controller.status.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            HStack {
                if controller.detectedPorts.isEmpty {
                    Text("No Proxmark3 detected")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Port", selection: $controller.selectedPort) {
                        ForEach(controller.detectedPorts, id: \.self) { port in
                            Text(port).tag(port)
                        }
                    }
                    .labelsHidden()
                    .disabled(controller.isConnected)
                }

                Button("Rescan") { controller.refreshPorts() }
                    .disabled(controller.isConnected)
                    .accessibilityIdentifier("rescan")

                if controller.isConnected {
                    Button("Disconnect") { Task { await controller.disconnect() } }
                        .accessibilityIdentifier("connectToggle")
                } else {
                    Button("Connect") { Task { await controller.connect() } }
                        .accessibilityIdentifier("connectToggle")
                        .keyboardShortcut(.defaultAction)
                        .disabled(controller.status.isBusy)
                }
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tag ID")
                    .frame(width: 60, alignment: .leading)
                TextField("10 hex digits", text: $controller.tagID)
                    .accessibilityIdentifier("tagID")
                    .accessibilityLabel("Tag ID, 10 hex digits")
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(controller.status.isBusy)
            }

            if let capture = controller.captured {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Captured")
                            .frame(width: 60, alignment: .leading)
                        Text("\(capture.kind)  \(capture.raw)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("rawValue")
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(capture.raw, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .accessibilityIdentifier("copyRaw")
                        Spacer()
                    }
                    Text(capture.isCloneable
                         ? "Swap a blank T5577 onto the antenna, then Write to Blank."
                         : "Held for reference. In-app cloning supports HID only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 68)
                }
            }

            HStack(spacing: 12) {
                Button("Read Tag") { Task { await controller.read() } }
                    .accessibilityIdentifier("read")
                    .disabled(!controller.isConnected || controller.status.isBusy)

                Button("Write Tag") { Task { await controller.write() } }
                    .accessibilityIdentifier("write")
                    .disabled(!controller.canWrite)

                if controller.captured != nil {
                    Button("Write to Blank") { Task { await controller.cloneRaw() } }
                        .accessibilityIdentifier("cloneRaw")
                        .disabled(!controller.canCloneRaw)
                }

                Spacer()

                Button("Wipe Tag") { confirmingWipe = true }
                    .accessibilityIdentifier("wipe")
                    .disabled(!controller.isConnected || controller.status.isBusy)
                    .tint(.red)
            }

            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(controller.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(6)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: controller.log.count) { _, count in
                    proxy.scrollTo(count - 1)
                }
            }
        }
    }
}
