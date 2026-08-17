// swift-tools-version: 6.0
import PackageDescription
import Foundation

// libpm3 is built out of this same checkout, so locate it relative to this
// manifest rather than expecting it on a system search path.
// tools/pm3gui/Package.swift -> repo root
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let libDir = repoRoot.appendingPathComponent("client/experimental_lib/build").path

let package = Package(
    name: "PM3GUI",
    // Matches what libpm3 is built for on this machine; anything lower makes
    // the linker warn about the dylib's deployment target.
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(name: "CPM3", path: "Sources/CPM3"),
        .executableTarget(
            name: "PM3GUI",
            dependencies: ["CPM3"],
            linkerSettings: [
                // The dylib's install name is @rpath/libpm3rrg_rdv4.dylib, so an
                // rpath entry is what lets the built binary run without
                // DYLD_LIBRARY_PATH being set by hand.
                .unsafeFlags([
                    "-L\(libDir)",
                    "-Xlinker", "-rpath", "-Xlinker", libDir,
                ])
            ]
        ),
    ]
)
