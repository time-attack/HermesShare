// TestFixtures.swift
// Loads JSON fixtures from the on-disk Fixtures/ folder (works in Xcode test bundles
// where SwiftPM's `Bundle.module` is not generated).

import Foundation

enum TestFixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    static func url(named name: String) -> URL? {
        let url = directory.appendingPathComponent("\(name).json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
