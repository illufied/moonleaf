//
//  SpaceWallpapers.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation

/// Wallpaper assignment for individual Mission Control desktops (Spaces).
///
/// `NSWorkspace.setDesktopImageURL` only reaches the desktop that is on screen,
/// so the desktops you are not looking at cannot be decorated through AppKit.
/// Their wallpapers live in the system wallpaper store
/// (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`);
/// that store is what this type reads and writes.
enum SpaceWallpapers {
    /// One desktop: `displayUUID` is the screen it belongs to, `uuid` is the
    /// Space identifier. The first desktop of a screen uses an empty string.
    struct Space: Hashable {
        let displayUUID: String
        let uuid: String
        let isCurrent: Bool
    }

    private static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    // MARK: - Desktops

    /// Every desktop of every online screen, in Mission Control order.
    static func liveSpaces() -> [Space] {
        guard let skyLight = skyLight,
              let connectionSymbol = dlsym(skyLight, "SLSMainConnectionID"),
              let copySymbol = dlsym(skyLight, "SLSCopyManagedDisplaySpaces") else { return [] }

        typealias ConnectionFn = @convention(c) () -> Int32
        typealias CopyDisplaysFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

        let connection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)()
        guard let displays = unsafeBitCast(copySymbol, to: CopyDisplaysFn.self)(connection)?
            .takeRetainedValue() as? [[String: Any]] else { return [] }

        var spaces: [Space] = []
        for display in displays {
            guard let displayUUID = display["Display Identifier"] as? String,
                  let entries = display["Spaces"] as? [[String: Any]] else { continue }
            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64
            for entry in entries {
                guard let uuid = entry["uuid"] as? String else { continue }
                let identifier = entry["ManagedSpaceID"] as? UInt64
                spaces.append(Space(displayUUID: displayUUID,
                                    uuid: uuid,
                                    isCurrent: identifier != nil && identifier == current))
            }
        }
        return spaces
    }

    /// Makes WallpaperAgent drop what it holds in memory and read the store
    /// again, so wallpapers written for the desktops that are not on screen
    /// show up straight away.
    static func reload() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["WallpaperAgent"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Store

    /// Desktop uuid -> wallpaper path currently configured for it.
    static func currentAssignments() -> [String: String] {
        guard let store = readStore(),
              let spaces = store["Spaces"] as? [String: Any] else { return [:] }

        var assignments: [String: String] = [:]
        for (uuid, entry) in spaces {
            guard let entry = entry as? [String: Any],
                  let desktop = (entry["Default"] as? [String: Any])?["Desktop"] as? [String: Any],
                  let content = desktop["Content"] as? [String: Any],
                  let path = path(inContent: content) else { continue }
            assignments[uuid] = path
        }
        return assignments
    }

    /// Points the given desktops at their wallpaper.
    @discardableResult
    static func assign(_ wallpapers: [Space: String]) -> Bool {
        guard !wallpapers.isEmpty, var store = readStore() else { return false }

        let idle = idleTemplate(in: store)
        var spaces = store["Spaces"] as? [String: Any] ?? [:]
        let now = Date()
        for (space, path) in wallpapers {
            var entry = spaces[space.uuid] as? [String: Any] ?? [:]
            entry["Default"] = desktopEntry(entry["Default"], path: path, now: now, idle: idle)
            var displays = entry["Displays"] as? [String: Any] ?? [:]
            displays[space.displayUUID] = desktopEntry(displays[space.displayUUID], path: path, now: now, idle: idle)
            entry["Displays"] = displays
            spaces[space.uuid] = entry
        }
        store["Spaces"] = spaces

        // The per-display section is what a screen that is plugged in again
        // reads before its desktops exist, so the display keeps the picture it
        // had instead of falling back to the system default.
        var displays = store["Displays"] as? [String: Any] ?? [:]
        for displayUUID in Set(wallpapers.keys.map { $0.displayUUID }) {
            let onDisplay = wallpapers
                .filter { $0.key.displayUUID == displayUUID }
                .sorted { $0.key.uuid < $1.key.uuid }
            guard let path = (onDisplay.first { $0.key.isCurrent } ?? onDisplay.first)?.value else { continue }
            displays[displayUUID] = desktopEntry(displays[displayUUID], path: path, now: now, idle: idle)
        }
        store["Displays"] = displays

        return write(store)
    }

    /// A desktop entry as macOS 26 stores it: the desktop picture plus the
    /// picture shown when the system goes idle. WallpaperAgent rejects the whole
    /// store when either is missing, so a fresh entry copies the idle picture
    /// that is already configured elsewhere.
    private static func desktopEntry(_ existing: Any?, path: String, now: Date, idle: [String: Any]) -> [String: Any] {
        var entry = existing as? [String: Any] ?? [:]
        entry["Type"] = "individual"
        // A desktop the store used to share between all screens keeps a linked
        // block behind; it would point at a picture this entry no longer uses.
        entry.removeValue(forKey: "Linked")
        if entry["Idle"] == nil {
            entry["Idle"] = idle
        }

        var desktop = entry["Desktop"] as? [String: Any] ?? [:]
        var content = desktop["Content"] as? [String: Any] ?? [:]
        // Only the picker changes: the option blob keeps the scaling and
        // placement the desktop was using.
        content["Choices"] = [[
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [String](),
            "Configuration": configuration(for: path),
        ]]
        content["EncodedOptionValues"] = content["EncodedOptionValues"] ?? "$null"
        content["Shuffle"] = content["Shuffle"] ?? "$null"
        desktop["Content"] = content
        desktop["LastSet"] = now
        desktop["LastUse"] = now
        entry["Desktop"] = desktop
        return entry
    }

    /// The idle picture any entry in the store already carries, or the plain
    /// system default when the store has none yet.
    private static func idleTemplate(in store: [String: Any]) -> [String: Any] {
        for key in ["SystemDefault", "AllSpacesAndDisplays"] {
            if let idle = (store[key] as? [String: Any])?["Idle"] as? [String: Any] {
                return idle
            }
        }
        for entry in (store["Spaces"] as? [String: Any] ?? [:]).values {
            let entry = entry as? [String: Any] ?? [:]
            if let idle = (entry["Default"] as? [String: Any])?["Idle"] as? [String: Any] {
                return idle
            }
            for display in (entry["Displays"] as? [String: Any] ?? [:]).values {
                if let idle = (display as? [String: Any])?["Idle"] as? [String: Any] {
                    return idle
                }
            }
        }
        let now = Date()
        return [
            "Content": [
                "Choices": [[
                    "Provider": "default",
                    "Files": [String](),
                    "Configuration": Data(),
                ]],
                "EncodedOptionValues": "$null",
                "Shuffle": "$null",
            ],
            "LastSet": now,
            "LastUse": now,
        ]
    }

    private static func write(_ store: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: store, format: .binary, options: 0) else { return false }
        return (try? data.write(to: storeURL, options: .atomic)) != nil
    }

    private static func configuration(for path: String) -> Data {
        let configuration: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": URL(fileURLWithPath: path).absoluteString],
        ]
        return (try? PropertyListSerialization.data(
            fromPropertyList: configuration, format: .binary, options: 0)) ?? Data()
    }

    private static func path(inContent content: [String: Any]) -> String? {
        guard let choices = content["Choices"] as? [[String: Any]],
              let configuration = choices.first?["Configuration"] as? Data,
              let decoded = try? PropertyListSerialization.propertyList(
                from: configuration, format: nil) as? [String: Any],
              let relative = (decoded["url"] as? [String: String])?["relative"],
              let url = URL(string: relative) else { return nil }
        return url.path
    }

    private static func readStore() -> [String: Any]? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
