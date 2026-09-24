//
//  macpaper.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AppKit
import AVFoundation

@main
struct macpaper: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Settings") {
            SettingsView()
                .environmentObject(macpaperService())
                .frame(minWidth: 550, idealWidth: 600, minHeight: 500, idealHeight: 550)
                .font(Font(font_loader.regular(size: 13)))
        }
        .windowStyle(DefaultWindowStyle())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var status_item: NSStatusItem?
    var _mwin: NSWindow?
    var _settingsWin: NSWindow?
    var _mwin_open = false
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("glassBackground") private var glassBackground = false
    var updater = Updater()
    private let service = macpaperService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }
        
        font_loader.regFonts()
        
        performFirstLaunchMigration()
        make_paper_sb_item()
        start_launchAgent()

        if checkForUpdates {
            updater.checkForUpdates()
        }

        service.launchGlasswpDaemon()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// A screen can be plugged in at any moment, and the desktops it brings
    /// have no picture of their own until something decorates them: without
    /// this they stay on the system default.
    @objc private func displaysDidChange() {
        service.refreshScreenCount()
        macpaperService.restoreWallpapersAfterDisplayChange()
    }

    /* doing this would kill the actual wallpaper too
    func applicationWillTerminate(_ notification: Notification) {
        let killTask = Process()
        killTask.launchPath = "/usr/bin/pkill"
        killTask.arguments = ["-9", "-f", "macpaper Wallpaper Service (glasswp)"]
        try? killTask.run()
        killTask.waitUntilExit()
    }
    */

    private func performFirstLaunchMigration() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        
        let moonleafConfig = home.appendingPathComponent(".config/moonleaf")
        let oldConfig = home.appendingPathComponent(".local/share/macpaper")

        try? fm.createDirectory(at: moonleafConfig, withIntermediateDirectories: true)

        let newSettings = moonleafConfig.appendingPathComponent("settings.json")
        let oldSettings = oldConfig.appendingPathComponent("settings.json")
        
        if !fm.fileExists(atPath: newSettings.path) && fm.fileExists(atPath: oldSettings.path) {
            let items = (try? fm.contentsOfDirectory(at: oldConfig, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                let dest = moonleafConfig.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.createSymbolicLink(at: dest, withDestinationURL: item)
                }
            }
        }
    }

    func start_launchAgent() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.naomisphere.moonleaf.wallpaper.plist")

        if FileManager.default.fileExists(atPath: launchAgent.path) {
            let service = macpaperService()
            service.wp_doPersist(true)
        }
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    func make_paper_sb_item() {
        status_item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = status_item?.button {
            if let resourcePath = Bundle.main.path(forResource: "StatusBarIcon", ofType: "png"),
               let iconImage = NSImage(contentsOfFile: resourcePath) {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "moonleaf")
            }
        }

        status_item?.menu = sb_item_menu()
    }

    func remove_sb_item() {
        if let item = status_item {
            NSStatusBar.system.removeStatusItem(item)
        }
        status_item = nil
    }

    @objc func show_manager() {
        if _mwin == nil {
            let contentView = ContentView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.isReleasedWhenClosed = false
            window.center()
            window.title = "moonleaf"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = true

            let useGlass = glassBackground

            if useGlass {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = NSHostingView(rootView: contentView.font(Font(font_loader.regular(size: 13))).ignoresSafeArea())
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                window.isOpaque = true
                window.backgroundColor = NSColor(srgbRed: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)
                window.contentView = NSHostingView(rootView: contentView.font(Font(font_loader.regular(size: 13))))
            }

            window.minSize = NSSize(width: 900, height: 600)
            window.delegate = self
            _mwin = window
        }

        _mwin?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        _mwin_open = true
    }



    func close_manager() {
        _mwin?.close()
        _mwin_open = false
        NSApp.setActivationPolicy(.accessory)
    }

    func show_mwin() {
        show_manager()
    }

    func sb_item_menu() -> NSMenu {
        let menu = NSMenu()
        let service = macpaperService()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let current_wp = home.appendingPathComponent(".local/share/macpaper/current_wallpaper")
        var wallpaper_is_set = false
        var _wp: String?

        if FileManager.default.fileExists(atPath: current_wp.path),
           let currentPath = try? String(contentsOf: current_wp).trimmingCharacters(in: .whitespacesAndNewlines) {
            wallpaper_is_set = FileManager.default.fileExists(atPath: currentPath)
            _wp = currentPath
        }

        let wp_storage_dir = home.appendingPathComponent(".local/share/paper/wallpaper")
        var wallpapers: [endup_wp] = []

        if FileManager.default.fileExists(atPath: wp_storage_dir.path),
           let files = try? FileManager.default.contentsOfDirectory(at: wp_storage_dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            wallpapers = files.filter { url in
                ["mov", "mp4", "gif", "jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
            }.compactMap { url -> endup_wp? in
                let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let date = rv?.contentModificationDate, let size = rv?.fileSize else { return nil }
                return endup_wp(id: UUID(), name: url.deletingPathExtension().lastPathComponent, path: url.path, preview: nil, createdDate: date, fileSize: Int64(size))
            }.sorted { $0.createdDate > $1.createdDate }
        }

        let openItem = NSMenuItem(title: NSLocalizedString("sb_open_mgr", comment: "Open Manager"), action: #selector(show_manager), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        if !wallpapers.isEmpty {
            let wpSubmenu = NSMenu()

            for wallpaper in wallpapers.prefix(8) {
                let item = NSMenuItem(title: wallpaper.name, action: #selector(apply_wp(_:)), keyEquivalent: "")
                item.representedObject = wallpaper
                item.target = self

                let ext = (wallpaper.path as NSString).pathExtension.lowercased()
                if ["jpg", "jpeg", "png"].contains(ext) {
                    if let img = NSImage(contentsOfFile: wallpaper.path) {
                        let thumb = NSImage(size: NSSize(width: 20, height: 14))
                        thumb.lockFocus()
                        img.draw(in: NSRect(x: 0, y: 0, width: 20, height: 14), from: .zero, operation: .copy, fraction: 1)
                        thumb.unlockFocus()
                        item.image = thumb
                    }
                } else if let img = generateVideoThumbnailSync(path: wallpaper.path) {
                    item.image = img
                }

                if let currentPath = _wp, currentPath == wallpaper.path {
                    item.state = .on
                }
                wpSubmenu.addItem(item)
            }

            if wallpapers.count > 8 {
                wpSubmenu.addItem(NSMenuItem.separator())
                let showAllItem = NSMenuItem(title: NSLocalizedString("sb_show_all", comment: "Show All..."), action: #selector(open_manager), keyEquivalent: "")
                showAllItem.target = self
                wpSubmenu.addItem(showAllItem)
            }

            let wpMenuItem = NSMenuItem(title: NSLocalizedString("sb_wallpapers", comment: "Wallpapers"), action: nil, keyEquivalent: "")
            wpMenuItem.submenu = wpSubmenu
            menu.addItem(wpMenuItem)
        } else {
            let noWpItem = NSMenuItem(title: NSLocalizedString("sb_no_wallpapers", comment: "No wallpapers found"), action: nil, keyEquivalent: "")
            noWpItem.isEnabled = false
            menu.addItem(noWpItem)
        }

        menu.addItem(NSMenuItem.separator())

        let volumeItem = NSMenuItem()
        let volumeView = NSHostingView(rootView: MiniVolumeSlider(volume: service.volume))
        volumeView.frame = NSRect(x: 0, y: 0, width: 200, height: 30)
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        menu.addItem(NSMenuItem.separator())

        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.naomisphere.macpaper.wallpaper.plist")
        let is_agent_enabled = FileManager.default.fileExists(atPath: launchAgent.path)

        let persistItem = NSMenuItem(title: NSLocalizedString("sb_perst_tooltip", comment: "Auto-start wallpaper"), action: #selector(toggle_launchAgent), keyEquivalent: "")
        persistItem.target = self
        persistItem.state = is_agent_enabled ? .on : .off
        menu.addItem(persistItem)

        if wallpaper_is_set {
            let unsetItem = NSMenuItem(title: NSLocalizedString("sb_unset_wp", comment: "Unset Wallpaper"), action: #selector(unset_wp), keyEquivalent: "")
            unsetItem.target = self
            menu.addItem(unsetItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: NSLocalizedString("sb_settings", comment: "Settings"), action: #selector(show_settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: NSLocalizedString("sb_about", comment: "About moonleaf"), action: #selector(show_about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("sb_quit", comment: "Quit moonleaf"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func generateVideoThumbnailSync(path: String) -> NSImage? {
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 20, height: 14)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: 20, height: 14))
        return img
    }

    @objc func apply_wp(_ sender: NSMenuItem) {
        guard let wallpaper = sender.representedObject as? endup_wp else { return }
        let service = macpaperService()
        service.set_wp(wallpaper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.status_item?.menu = self.sb_item_menu()
        }
    }

    @objc func toggle_launchAgent() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.naomisphere.macpaper.wallpaper.plist")
        let is_agent_enabled = FileManager.default.fileExists(atPath: launchAgent.path)
        let service = macpaperService()
        service.wp_doPersist(!is_agent_enabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.status_item?.menu = self.sb_item_menu()
        }
    }

    @objc func unset_wp() {
        let service = macpaperService()
        service.unset_wp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.status_item?.menu = self.sb_item_menu()
        }
    }

    @objc func open_manager() { show_mwin() }

    @objc func show_settings() {
        if let existing = _settingsWin {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView().environmentObject(macpaperService())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let managerWindow = _mwin {
            let mf = managerWindow.frame
            let sf = window.frame.size
            window.setFrameOrigin(NSPoint(x: mf.midX - sf.width / 2, y: mf.midY - sf.height / 2))
        } else {
            window.center()
        }

        window.title = NSLocalizedString("settings", comment: "Settings")
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: settingsView.font(Font(font_loader.regular(size: 13))))
        window.isReleasedWhenClosed = false
        
        _settingsWin = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refresh_wallpapers() {
        let service = macpaperService()
        service.fetch_wallpapers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.status_item?.menu = self.sb_item_menu()
        }
    }

    @objc func show_about() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        let alert = NSAlert()
        alert.messageText = "moonleaf"
        alert.informativeText = String(format: NSLocalizedString("sb_about_text", comment: ""), version, build)
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("sb_about_github", comment: "GitHub"))
        alert.addButton(withTitle: NSLocalizedString("sb_about_kofi", comment: "Support on Ko-fi"))
        alert.addButton(withTitle: NSLocalizedString("browse_cancel", comment: "OK"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/naomisphere/moonleaf")!)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/naomisphere")!)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let closingWindow = notification.object as? NSWindow
        if closingWindow == _mwin {
            _mwin_open = false
            _mwin = nil
        } else if closingWindow == _settingsWin {
            _settingsWin = nil
        }
        
        if _mwin == nil && _settingsWin == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender == _mwin else { return frameSize }
        return NSSize(width: max(frameSize.width, 900), height: max(frameSize.height, 600))
    }
}

struct MiniVolumeSlider: View {
    @State var volume: Double

    var body: some View {
        HStack {
            Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2")
                .font(Font(font_loader.regular(size: 11)))
                .foregroundColor(.secondary)

            Slider(value: $volume, in: 0...1)
                .frame(width: 120)
                .onChange(of: volume) { newValue in
                    let service = macpaperService()
                    service.chvol(newValue)
                }

            Text("\(Int(volume * 100))%")
                .font(Font(font_loader.regular(size: 10)))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }
}