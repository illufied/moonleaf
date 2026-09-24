//
//  macpaperService.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import Combine
import AppKit

class macpaperService: NSObject, ObservableObject {
    @Published var wallpapers: [endup_wp] = []
    @Published var isLoading = false
    @Published var current_wp: String?
    @Published var volume: Double = 0.5
    @Published var wp_is_agent: Bool = false
    @Published var ap_is_enabled: Bool = false
    @Published var showVideos: Bool = true
    @Published var showImages: Bool = true
    @Published var selected_wp: endup_wp? = nil
    @Published var favorites: Set<String> = []
    @Published var localSort: LocalSortMode = .date
    @Published var shuffleEnabled: Bool = false
    @Published var shuffleInterval: ShuffleInterval = .oneHour
    @Published var perSpaceShuffle: Bool = false
    @Published var importMethod: ImportMethod = .link
    @Published var currentPath: URL?
    @Published var navStack: [URL] = []

    @Published var screenWallpapers: [Int: String] = [:]

    @Published var screenCount: Int = 1

    var isAtRoot: Bool {
        return navStack.isEmpty
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let wp_storage_dir = home.appendingPathComponent(".local/share/paper/wallpaper")
    static let settings_file = home.appendingPathComponent(".config/moonleaf/settings.json")

    private let wrapped_obj: String
    private let wallpaper_cli: String
    private let glasswp_path: String
    private let wp_storage_dir = macpaperService.wp_storage_dir
    private let settings_file = macpaperService.settings_file
    private let export_folder_file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/moonleaf/export_folder")
    private let screen_wallpapers_file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/moonleaf/screen_wallpapers.json")
    private static var shuffleLoop: DispatchSourceTimer?

    enum LocalSortMode: String, CaseIterable {
        case date = "date"
        case name = "name"
        case size = "size"

        var displayName: String {
            switch self {
            case .date: return NSLocalizedString("sort_by_date", comment: "Date Added")
            case .name: return NSLocalizedString("sort_by_name", comment: "Name")
            case .size: return NSLocalizedString("sort_by_size", comment: "File Size")
            }
        }
    }

    enum ShuffleInterval: String, CaseIterable {
        case fifteenMin = "15min"
        case oneHour = "1hr"
        case threeHour = "3hr"
        case daily = "daily"

        var displayName: String {
            switch self {
            case .fifteenMin: return NSLocalizedString("shuffle_interval_15min", comment: "15 minutes")
            case .oneHour: return NSLocalizedString("shuffle_interval_1hr", comment: "1 hour")
            case .threeHour: return NSLocalizedString("shuffle_interval_3hr", comment: "3 hours")
            case .daily: return NSLocalizedString("shuffle_interval_daily", comment: "Daily")
            }
        }

        var seconds: Double {
            switch self {
            case .fifteenMin: return 15 * 60
            case .oneHour: return 60 * 60
            case .threeHour: return 3 * 60 * 60
            case .daily: return 24 * 60 * 60
            }
        }
    }

    enum ImportMethod: String, CaseIterable {
        case copy = "copy"
        case link = "link"
    }

    override init() {
        let app_path = Bundle.main.bundlePath
        wrapped_obj = "\(app_path)/Contents/MacOS/moonleaf-bin"
        wallpaper_cli = "\(app_path)/Contents/Resources/bin/wallpaper"
        glasswp_path = "\(app_path)/Contents/Resources/bin/glasswp"
        super.init()
        syncConfigs()
        loadSettings()
        loadVolume()
        screenCount = NSScreen.screens.count
        loadScreenWallpapers()
        macpaperService.syncShuffleLoop()
    }

    public func launchGlasswpDaemon() {
        
        if checkIfGlasswpIsRunning() { return }
        
        guard FileManager.default.fileExists(atPath: glasswp_path) else { return }
        
        let task = Process()
        task.launchPath = glasswp_path
        task.arguments = ["--daemon"]
        task.launch()
    }

    func select_wp(_ wallpaper: endup_wp?) {
        selected_wp = wallpaper
    }

    func toggleFavorite(_ wallpaper: endup_wp) {
        if favorites.contains(wallpaper.path) {
            favorites.remove(wallpaper.path)
        } else {
            favorites.insert(wallpaper.path)
        }
        saveFavorites()
    }

    func isFavorite(_ wallpaper: endup_wp) -> Bool {
        return favorites.contains(wallpaper.path)
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "moonleaf_favorites"),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            favorites = Set(paths)
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favorites)) {
            UserDefaults.standard.set(data, forKey: "moonleaf_favorites")
        }
    }

    func setLocalSort(_ mode: LocalSortMode) {
        localSort = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "moonleaf_localSort")
        applyLocalSort()
    }

    private func applyLocalSort() {
        switch localSort {
        case .date:
            wallpapers = wallpapers.sorted { $0.createdDate > $1.createdDate }
        case .name:
            wallpapers = wallpapers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            wallpapers = wallpapers.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func setShuffleEnabled(_ enabled: Bool) {
        shuffleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: macpaperService.shuffleEnabledKey)
        macpaperService.syncShuffleLoop()
    }

    func setShuffleInterval(_ interval: ShuffleInterval) {
        shuffleInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: macpaperService.shuffleIntervalKey)
        if shuffleEnabled {
            macpaperService.restartShuffleLoop()
        }
    }

    private static let shuffleEnabledKey = "moonleaf_shuffleEnabled"
    private static let shuffleIntervalKey = "moonleaf_shuffleInterval"
    private static let perSpaceShuffleKey = "moonleaf_perSpaceShuffle"
    private static let lastShuffleKey = "moonleaf_lastShuffle"

    /// Turns the per-desktop rotation on or off. Switching it on applies it
    /// right away, otherwise nothing would happen until the next interval.
    func setPerSpaceShuffle(_ enabled: Bool) {
        perSpaceShuffle = enabled
        UserDefaults.standard.set(enabled, forKey: macpaperService.perSpaceShuffleKey)
        if enabled && shuffleEnabled {
            macpaperService.rotateDesktops()
        }
    }

    /// Arms the rotation loop when the setting is on and no loop is running yet.
    ///
    /// The loop is deliberately process-wide: every window, menu and settings
    /// pane builds its own short-lived `macpaperService`, so an instance-owned
    /// timer dies with whatever window happened to create it.
    static func syncShuffleLoop() {
        let enabled = UserDefaults.standard.bool(forKey: shuffleEnabledKey)
        guard enabled else {
            shuffleLoop?.cancel()
            shuffleLoop = nil
            return
        }
        guard shuffleLoop == nil else { return }
        let intervalRaw = UserDefaults.standard.string(forKey: shuffleIntervalKey)
        let interval = intervalRaw.flatMap(ShuffleInterval.init(rawValue:)) ?? .oneHour
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + interval.seconds, repeating: interval.seconds)
        timer.setEventHandler { macpaperService.shuffleTick() }
        timer.resume()
        shuffleLoop = timer
    }

    private static func restartShuffleLoop() {
        shuffleLoop?.cancel()
        shuffleLoop = nil
        syncShuffleLoop()
    }

    /// Long-lived instance the rotation loop drives, so the post-set work
    /// (screensaver copy, screen bookkeeping, animated-wallpaper notification)
    /// is not dropped when a throwaway instance goes away first.
    private static let rotationService = macpaperService()

    private static func shuffleTick() {
        let candidates = library_candidates()
        guard !candidates.isEmpty else { return }

        if UserDefaults.standard.bool(forKey: perSpaceShuffleKey) {
            rotateDesktops(candidates)
            return
        }

        guard let next = random_library_wallpaper(from: candidates) else { return }
        DispatchQueue.main.async {
            rotationService.set_wp(next)
        }
    }

    /// Still images and videos in the library root that the Show Images/Videos
    /// settings keep visible; folders are skipped, they are not settable.
    private static func library_candidates() -> [endup_wp] {
        let settings = load_settings_json()
        let showImages = (settings["showImages"] ?? "true") == "true"
        let showVideos = (settings["showVideos"] ?? "true") == "true"
        return scan_library(wp_storage_dir).filter {
            !$0.isFolder && is_visible($0, showImages: showImages, showVideos: showVideos)
        }
    }

    /// Never returns the file that was used for the previous rotation.
    private static func random_library_wallpaper(from candidates: [endup_wp]) -> endup_wp? {
        guard candidates.count > 1 else { return candidates.first }

        let previous = UserDefaults.standard.string(forKey: lastShuffleKey)
        let pool = candidates.filter { $0.path != previous }
        guard let next = (pool.isEmpty ? candidates : pool).randomElement() else { return nil }
        UserDefaults.standard.set(next.path, forKey: lastShuffleKey)
        return next
    }

    /// Gives every desktop its own wallpaper.
    ///
    /// Desktops rotate: a desktop never keeps the image it shows right now, and
    /// images that are on a desktop already are picked last, so the library
    /// cycles through the desktops instead of repeating.
    static func rotateDesktops() {
        rotateDesktops(library_candidates())
    }

    private static func rotateDesktops(_ candidates: [endup_wp]) {
        let stills = candidates.filter {
            ["jpg", "jpeg", "png"].contains(($0.path as NSString).pathExtension.lowercased())
        }
        let spaces = SpaceWallpapers.liveSpaces()
        guard !stills.isEmpty, !spaces.isEmpty else { return }

        let current = SpaceWallpapers.currentAssignments()
        let onScreen = Set(current.values)
        var claimed = Set<String>()
        var assignment: [SpaceWallpapers.Space: String] = [:]

        for space in spaces {
            let previous = current[space.uuid]
            let unused = stills.filter {
                !onScreen.contains($0.path) && !claimed.contains($0.path) && $0.path != previous
            }
            let fresh = stills.filter { !claimed.contains($0.path) && $0.path != previous }
            let remaining = stills.filter { !claimed.contains($0.path) }
            let pool = !unused.isEmpty ? unused : (!fresh.isEmpty ? fresh : (!remaining.isEmpty ? remaining : stills))
            guard let pick = pool.randomElement() else { continue }
            claimed.insert(pick.path)
            assignment[space] = pick.path
        }
        guard !assignment.isEmpty else { return }
        guard SpaceWallpapers.assign(assignment) else { return }

        // WallpaperAgent keeps the desktops in memory and only re-reads the
        // store when it starts or when a desktop is switched to, so it is
        // restarted here: that is what makes every desktop show its new
        // wallpaper now instead of only the ones visited next.
        SpaceWallpapers.reload()

        if let visible = spaces.first(where: { $0.isCurrent }), let path = assignment[visible] {
            rotationService.mark_current_wallpaper(path)
        }
    }

    func _ap_enabled(_ enabled: Bool) {
        ap_is_enabled = enabled
        saveSettings()

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.autoPauseChanged"),
            object: nil,
            userInfo: ["ap_is_enabled": enabled],
            deliverImmediately: true
        )
    }

    static func load_settings_json() -> [String: String] {
        guard let data = try? Data(contentsOf: settings_file),
              let settings = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return settings
    }

    private func loadSettings() {
        let settings = macpaperService.load_settings_json()
        ap_is_enabled = (settings["ap_is_enabled"] == "true")
        showVideos = (settings["showVideos"] ?? "true") == "true"
        showImages = (settings["showImages"] ?? "true") == "true"
        if let methodRaw = settings["import_method"], let method = ImportMethod(rawValue: methodRaw) {
            importMethod = method
        }

        currentPath = wp_storage_dir

        loadFavorites()

        if let sortRaw = UserDefaults.standard.string(forKey: "moonleaf_localSort"),
           let sort = LocalSortMode(rawValue: sortRaw) {
            localSort = sort
        }

        shuffleEnabled = UserDefaults.standard.bool(forKey: "moonleaf_shuffleEnabled")

        perSpaceShuffle = UserDefaults.standard.bool(forKey: "moonleaf_perSpaceShuffle")

        if let intervalRaw = UserDefaults.standard.string(forKey: "moonleaf_shuffleInterval"),
           let interval = ShuffleInterval(rawValue: intervalRaw) {
            shuffleInterval = interval
        }
    }

    private func loadVolume() {
        let volFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/volume")
        if let data = try? Data(contentsOf: volFile),
           let str = String(data: data, encoding: .utf8),
           let intVal = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            volume = Double(max(0, min(100, intVal))) / 100.0
        }
    }

    func saveSettings() {
        do {
            let settings: [String: String] = [
                "ap_is_enabled": ap_is_enabled ? "true" : "false",
                "showVideos": showVideos ? "true" : "false",
                "showImages": showImages ? "true" : "false",
                "import_method": importMethod.rawValue
            ]
            let data = try JSONEncoder().encode(settings)
            try FileManager.default.createDirectory(
                at: settings_file.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: settings_file)
        } catch {}
    }

    func chvol(_ new_vol: Double) {
        volume = new_vol
        let volumeFloat = Float(new_vol)

        
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.volumeChanged"),
            object: nil,
            userInfo: ["volume": volumeFloat],
            deliverImmediately: true
        )
        
        
        let vol_in_percentage = Int(new_vol * 100)
        let volFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/volume")
        try? "\(vol_in_percentage)".write(to: volFile, atomically: true, encoding: .utf8)
    }

    /// Lists every folder and media file directly inside `directory`, unsorted
    /// and unfiltered; callers decide what to keep visible.
    static func scan_library(_ directory: URL) -> [endup_wp] {
        let scanPath = directory.resolvingSymlinksInPath()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scanPath,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]) else {
            return []
        }

        let validExts = ["mov", "mp4", "gif", "jpg", "jpeg", "png"]
        return files.compactMap { url -> endup_wp? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
            let isFolder = isDir.boolValue
            if !isFolder && !validExts.contains(url.pathExtension.lowercased()) { return nil }

            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = rv?.contentModificationDate
                ?? (attrs?[.modificationDate] as? Date)
                ?? Date.distantPast
            let fileSize = rv?.fileSize.map(Int64.init)
                ?? (attrs?[.size] as? Int64)
                ?? 0

            return endup_wp(
                id: UUID(),
                name: url.deletingPathExtension().lastPathComponent,
                path: url.path,
                preview: nil,
                createdDate: modDate,
                fileSize: fileSize,
                isFolder: isFolder
            )
        }
    }

    static func is_visible(_ wallpaper: endup_wp, showImages: Bool, showVideos: Bool) -> Bool {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        if !showVideos && ["mov", "mp4", "gif"].contains(ext) { return false }
        if !showImages && !wallpaper.isFolder && ["jpg", "jpeg", "png"].contains(ext) { return false }
        return true
    }

    func fetch_wallpapers() {
        isLoading = true

        try? FileManager.default.createDirectory(at: wp_storage_dir, withIntermediateDirectories: true)
        let scanPath = currentPath ?? wp_storage_dir

        DispatchQueue.global(qos: .background).async { [weak self] in
            let items = macpaperService.scan_library(scanPath)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.wallpapers = items.filter {
                    macpaperService.is_visible($0, showImages: self.showImages, showVideos: self.showVideos)
                }
                self.applyLocalSort()
                self.isLoading = false
            }
        }
    }

    func set_still_wp(_ wallpaper: endup_wp) {
        set_wp(wallpaper)
    }

    func set_wp(_ wallpaper: endup_wp) {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        let isMoving = ["mov", "mp4", "gif"].contains(ext)
        let isStill = ["jpg", "jpeg", "png"].contains(ext)

        guard isMoving || isStill else { return }

        DispatchQueue.main.async { self.selected_wp = wallpaper }

        copyWallpaperForScreensaver(wallpaper)

        
        if isStill {
            let cliPath = Bundle.main.bundlePath + "/Contents/Resources/bin/wallpaper"
            if FileManager.default.fileExists(atPath: cliPath) {
                _exec_wallpaper(["set", wallpaper.path]) { [weak self] success in
                    guard let self = self else { return }
                    
                    self.postOverlayNotification(path: wallpaper.path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.current_wp = wallpaper.path
                        self.screenWallpapers.removeAll()
                        self.saveScreenWallpapers()
                    }
                }
            } else {
                
                self.postOverlayNotification(path: wallpaper.path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.current_wp = wallpaper.path
                    self.screenWallpapers.removeAll()
                    self.saveScreenWallpapers()
                }
            }
            return
        }

        
        
        self.postOverlayNotification(path: wallpaper.path)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.current_wp = wallpaper.path
            self.screenWallpapers.removeAll()
            self.saveScreenWallpapers()
        }
    }

    private func postOverlayNotification(path: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
            object: nil,
            userInfo: ["filePath": path],
            deliverImmediately: true
        )
    }

    /// Records a wallpaper that the rotation loop already applied: screensaver
    /// copy, overlay notice and the "current" marker the browser shows.
    private func mark_current_wallpaper(_ path: String) {
        let wallpaper = endup_wp(
            id: UUID(),
            name: (path as NSString).lastPathComponent,
            path: path,
            preview: nil,
            createdDate: Date(),
            fileSize: 0
        )
        copyWallpaperForScreensaver(wallpaper)
        postOverlayNotification(path: path)

        DispatchQueue.main.async {
            self.current_wp = path
            self.screenWallpapers.removeAll()
            self.saveScreenWallpapers()
        }
    }

    private func checkIfGlasswpIsRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "glasswp"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func set_wp_on_screen(_ wallpaper: endup_wp, screenIndex: Int) {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        let isMoving = ["mov", "mp4", "gif"].contains(ext)
        let isStill = ["jpg", "jpeg", "png"].contains(ext)
        guard isMoving || isStill else { return }

        
        if isStill {
            set_wp(wallpaper)
            return
        }

        
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
            object: nil,
            userInfo: ["filePath": wallpaper.path, "screenIndex": screenIndex],
            deliverImmediately: true
        )

        DispatchQueue.main.async {
            self.screenWallpapers[screenIndex] = wallpaper.path
            self.saveScreenWallpapers()
            self.current_wp = wallpaper.path
        }
    }

    private func copyWallpaperForScreensaver(_ wallpaper: endup_wp) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let screensaverDir = home.appendingPathComponent("Library/Application Support/macpaper")
        let fileExtension = (wallpaper.path as NSString).pathExtension
        let destURL = screensaverDir.appendingPathComponent("current_screensaver_wallpaper.\(fileExtension)")

        do {
            try FileManager.default.createDirectory(at: screensaverDir, withIntermediateDirectories: true)
            let oldFiles = try? FileManager.default.contentsOfDirectory(at: screensaverDir, includingPropertiesForKeys: nil)
            oldFiles?.filter { $0.deletingPathExtension().lastPathComponent == "current_screensaver_wallpaper" }.forEach {
                try? FileManager.default.removeItem(at: $0)
            }
            try FileManager.default.copyItem(atPath: wallpaper.path, toPath: destURL.path)
        } catch {}
    }

    private func set_wp_after_unset(_ wallpaper: endup_wp) {
        
        _exec([wrapped_obj, "--set", wallpaper.path]) { [weak self] success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.current_wp = wallpaper.path
                }
            } else {
                self?.current_wp = nil
            }
        }
    }

    private func _unset_wp(completion: @escaping () -> Void) {
        DispatchQueue.main.async { self.selected_wp = nil }
        current_wp = nil
        wp_is_agent = false
        
        let killTask = Process()
        killTask.launchPath = "/usr/bin/pkill"
        killTask.arguments = ["-9", "-f", "glasswp"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        _exec([wrapped_obj, "--unset"]) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion()
            }
        }
    }

    func unset_wp() {
        selected_wp = nil
        _unset_wp {}
    }

    func wp_doPersist(_ enabled: Bool) {
        wp_is_agent = enabled

        if enabled {
            _exec([wrapped_obj, "--persist"]) { [weak self] success in
                DispatchQueue.main.async { self?.wp_is_agent = success }
            }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.naomisphere.macpaper.wallpaper.plist")
            let unload = Process()
            unload.launchPath = "/bin/launchctl"
            unload.arguments = ["unload", launchAgent.path]
            try? unload.run()
            unload.waitUntilExit()
            try? FileManager.default.removeItem(at: launchAgent)
            DispatchQueue.main.async { self.wp_is_agent = false }
        }
    }

    func getExportFolder() -> URL {
        if FileManager.default.fileExists(atPath: export_folder_file.path),
           let path = try? String(contentsOf: export_folder_file).trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    }

    func get_wp_storage_dir() -> URL {
        return wp_storage_dir
    }

    private func _exec(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        guard FileManager.default.isExecutableFile(atPath: arguments[0]) else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = arguments[0]
            task.arguments = Array(arguments.dropFirst())
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.launch()
            task.waitUntilExit()
            DispatchQueue.main.async { completion(task.terminationStatus == 0) }
        }
    }

    private func _exec_wallpaper(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        let cliPath = Bundle.main.bundlePath + "/Contents/Resources/bin/wallpaper"
        // `Process.launch()` raises an uncaught NSException when the helper is
        // missing or not executable, which kills the whole app.
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = cliPath
            task.arguments = arguments
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.launch()
            task.waitUntilExit()
            DispatchQueue.main.async { completion(task.terminationStatus == 0) }
        }
    }

    func installScreensaver() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let destFolder = home.appendingPathComponent("Library/Screen Savers")
        let destURL = destFolder.appendingPathComponent("macpaperSaver.saver")

        guard let saverPath = Bundle.main.path(forResource: "macpaperSaver", ofType: "saver") else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(atPath: saverPath, toPath: destURL.path)

            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "useAsScreensaver")
                if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
        } catch {
            DispatchQueue.main.async {
                UserDefaults.standard.set(false, forKey: "useAsScreensaver")
            }
        }
    }

    func uninstallScreensaver() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saverURL = home.appendingPathComponent("Library/Screen Savers/macpaperSaver.saver")
        if FileManager.default.fileExists(atPath: saverURL.path) {
            try? FileManager.default.removeItem(at: saverURL)
            DispatchQueue.main.async {
                UserDefaults.standard.set(false, forKey: "useAsScreensaver")
            }
        }
    }

    func checkScreensaverStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saverURL = home.appendingPathComponent("Library/Screen Savers/macpaperSaver.saver")
        DispatchQueue.main.async {
            UserDefaults.standard.set(
                FileManager.default.fileExists(atPath: saverURL.path),
                forKey: "useAsScreensaver")
        }
    }
    func back() {
        guard !navStack.isEmpty else { return }
        currentPath = navStack.removeLast()
        fetch_wallpapers()
    }

    func navigateTo(folder: endup_wp) {
        guard folder.isFolder else { return }
        if let current = currentPath {
            navStack.append(current)
        }
        currentPath = URL(fileURLWithPath: folder.path)
        fetch_wallpapers()
    }

    private func syncConfigs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacyDir = home.appendingPathComponent(".local/share/macpaper")
        let newDir = home.appendingPathComponent(".config/moonleaf")
        
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        
        if let files = try? FileManager.default.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) {
            for file in files {
                let dest = newDir.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.createSymbolicLink(at: dest, withDestinationURL: file)
                }
            }
        }
    }

    

    func refreshScreenCount() {
        screenCount = NSScreen.screens.count
    }

    private func saveScreenWallpapers() {
        do {
            var encoded: [String: String] = [:]
            for (idx, path) in screenWallpapers {
                encoded[String(idx)] = path
            }
            let data = try JSONEncoder().encode(encoded)
            try FileManager.default.createDirectory(
                at: screen_wallpapers_file.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: screen_wallpapers_file)
        } catch {}
    }

    private func loadScreenWallpapers() {
        guard FileManager.default.fileExists(atPath: screen_wallpapers_file.path),
              let data = try? Data(contentsOf: screen_wallpapers_file),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }

        var loaded: [Int: String] = [:]
        for (key, path) in decoded {
            if let idx = Int(key) { loaded[idx] = path }
        }
        screenWallpapers = loaded

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (idx, path) in loaded {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
                    object: nil,
                    userInfo: ["filePath": path, "screenIndex": idx],
                    deliverImmediately: true
                )
            }
        }
    }
}

struct endup_wp: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let preview: String?
    let createdDate: Date
    let fileSize: Int64
    var isFolder: Bool = false
}