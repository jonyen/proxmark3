import Foundation
import IOKit

/// Finds the Proxmark3's serial port by walking the IOKit registry.
///
/// Deliberately identifies the device by its USB vendor name and never by the
/// port name: an Anker Type-C hub also enumerates as `/dev/tty.usbmodem…` and
/// has been mistaken for a Proxmark3 before.
enum DeviceFinder {

    static let vendorName = "proxmark.org"

    /// Every serial port belonging to an attached Proxmark3, usually one.
    static func findPorts() -> [String] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            guard property(of: service, named: "USB Vendor Name") == vendorName else { continue }

            // The dial-in device lives on a child node (the CDC ACM interface),
            // so search downward rather than reading this node directly.
            if let port = searchProperty(of: service, named: "IODialinDevice") {
                ports.append(port)
            }
        }
        return ports
    }

    private static func property(of service: io_object_t, named name: String) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(
            service, name as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return raw as? String
    }

    private static func searchProperty(of service: io_object_t, named name: String) -> String? {
        guard let raw = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            name as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else { return nil }
        return raw as? String
    }
}
