//
//  Settings.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var service: macpaperService
    @State private var selectedTab: SettingsTab = .general
    @State private var apiKey = ""
    @State private var showAPIKeyField = false
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var apiKeyError: String?
    @State private var showChangelogSheet = false
    @State private var changelogText: String?
    @State private var changelogLoading = false
    @State private var ap_is_enabled: Bool = false
    @State private var updateServer = ""
    @State private var updateServerError: String?
    @State private var isSavingUpdateServer = false
    @State private var updateServerSaveSuccess = false

    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false
    @AppStorage("exportFolderPath") private var exportFolderPath = ""
    @AppStorage("useAsScreensaver") private var useAsScreensaver = false
    @AppStorage("glassBackground") private var glassBackground = false

    @State private var visualizer_mode: String = "disabled"
    @State private var visualizer_colorMode: String = "rainbow"
    @State private var visualizer_customColor: String = "#FF00FF"
    @State private var visualizer_transparency: Double = 0.6
    @State private var visualizer_barCount: Int = 64
    @State private var visualizer_maxHeight: Double = 0.5
    @State private var visualizer_minHeight: Double = 4.0
    
    @State private var scalingMode: String = "fill"
    @State private var videoFilter: String = "none"

    private let updater = Updater()

    enum SettingsTab: CaseIterable, Identifiable, Hashable {
        case general, manager, playback

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return NSLocalizedString("settings_general", comment: "General")
            case .manager: return NSLocalizedString("settings_manager", comment: "Manager")
            case .playback: return NSLocalizedString("settings_playback", comment: "Playback")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .manager: return "macwindow"
            case .playback: return "play.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "gearshape.fill")
                    .font(Font(font_loader.regular(size: 24)))
                    .foregroundStyle(.blue)

                Text(NSLocalizedString("settings", comment: "Settings"))
                    .font(Font(font_loader.bold(size: 22)))

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(Font(font_loader.regular(size: 13)))
                            Text(tab.title)
                                .font(Font(font_loader.regular(size: 13)))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.blue : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 20)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .general: generalSettings
                    case .manager: managerSettings
                    case .playback: playbackSettings
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 500, idealHeight: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadAPIKey()
            ap_is_enabled = service.ap_is_enabled
            loadVisualizerSettings()
            loadExportFolder()
            checkAutoStartStatus()
            service.checkScreensaverStatus()
            loadUpdateServer()
        }
        .sheet(isPresented: $showChangelogSheet) {
            changelogSheet
        }
    }

    private var changelogSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("settings_update_log", comment: "Update Log"))
                    .font(Font(font_loader.bold(size: 18)))
                Spacer()
                Button(action: { showChangelogSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Font(font_loader.regular(size: 20)))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            if changelogLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else if let text = changelogText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(Font(font_loader.regular(size: 13)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            } else {
                Text("No changelog available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            }
        }
        .frame(width: 500, height: 420)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Section(title: NSLocalizedString("settings_startup", comment: "Startup")) {
                SToggle(
                    title: NSLocalizedString("settings_auto_start", comment: "Start at Login"),
                    description: NSLocalizedString("settings_auto_start_desc", comment: ""),
                    isOn: $autoStartEnabled
                )
                .onChange(of: autoStartEnabled) { newValue in toggleAutoStart(newValue) }
            }

            Section(title: NSLocalizedString("settings_updates", comment: "Updates")) {
                VStack(spacing: 12) {
                    SToggle(
                        title: NSLocalizedString("settings_check_updates", comment: "Check for Updates"),
                        description: NSLocalizedString("settings_check_updates_desc", comment: ""),
                        isOn: $checkForUpdates
                    )

                    HStack {
                        Spacer()
                        Button(action: fetchChangelog) {
                            HStack(spacing: 6) {
                                if changelogLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                                Text(NSLocalizedString("settings_update_log", comment: "Update Log"))
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Update Server")
                            .font(Font(font_loader.regular(size: 14)))
                        
                        HStack(spacing: 12) {
                            TextField("github.com/naomisphere/...", text: $updateServer)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: updateServer) { validateUpdateServer($0) }

                            Button(action: saveUpdateServer) {
                                if isSavingUpdateServer {
                                    ProgressView().controlSize(.small)
                                } else if updateServerSaveSuccess {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                } else {
                                    Text(NSLocalizedString("settings_save", comment: "Save"))
                                }
                            }
                            .disabled(isSavingUpdateServer)
                        }

                        if let error = updateServerError {
                            Text(error)
                                .font(Font(font_loader.regular(size: 11)))
                                .foregroundColor(.red)
                        }
                        
                        Text("github.com/naomisphere/...")
                            .font(Font(font_loader.regular(size: 11)))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            Section(title: "Wallhaven") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("settings_api_key", comment: "API Key"))
                        .font(Font(font_loader.regular(size: 14)))

                    Text(NSLocalizedString("settings_api_key_description", comment: ""))
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    if showAPIKeyField {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                SecureField(NSLocalizedString("settings_enter_api_key", comment: ""), text: $apiKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: apiKey) { validateAPIKey($0) }

                                Button(action: saveAPIKey) {
                                    if isSaving {
                                        ProgressView().controlSize(.small)
                                    } else if saveSuccess {
                                        Image(systemName: "checkmark").foregroundColor(.green)
                                    } else {
                                        Text(NSLocalizedString("settings_save", comment: "Save"))
                                    }
                                }
                                .disabled(isSaving)

                                Button(action: {
                                    showAPIKeyField = false
                                    apiKeyError = nil
                                }) {
                                    Text(NSLocalizedString("settings_cancel", comment: "Cancel"))
                                }
                            }
                            if let error = apiKeyError {
                                Text(error)
                                    .font(Font(font_loader.regular(size: 11)))
                                    .foregroundColor(.red)
                                    .padding(.leading, 4)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Text(apiKey.isEmpty ?
                                 NSLocalizedString("settings_no_api_key", comment: "") :
                                 NSLocalizedString("settings_api_key_set", comment: ""))
                                .foregroundColor(apiKey.isEmpty ? .red : .green)

                            Spacer()

                            Button(action: { showAPIKeyField = true; apiKeyError = nil }) {
                                Text(apiKey.isEmpty ?
                                     NSLocalizedString("settings_add_api_key", comment: "") :
                                     NSLocalizedString("settings_change_api_key", comment: ""))
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    private var managerSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Section(title: NSLocalizedString("settings_appearance", comment: "Appearance")) {
                SToggle(
                    title: NSLocalizedString("settings_glass_bg", comment: "Glass Background"),
                    description: NSLocalizedString("settings_glass_bg_desc", comment: ""),
                    isOn: $glassBackground
                )
            }

            Section(title: NSLocalizedString("settings_sort", comment: "Default Sort")) {
                HStack {
                    Text(NSLocalizedString("settings_sort", comment: "Sort by"))
                        .font(Font(font_loader.regular(size: 14)))

                    Spacer()

                    Picker("", selection: Binding(
                        get: { service.localSort },
                        set: { service.setLocalSort($0) }
                    )) {
                        ForEach(macpaperService.LocalSortMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 160)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            Section(title: NSLocalizedString("settings_export", comment: "Export")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("settings_export_folder", comment: "Export Folder"))
                        .font(Font(font_loader.regular(size: 14)))

                    Text(NSLocalizedString("settings_export_folder_desc", comment: ""))
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text(getDisplayFolderName())
                            .font(Font(font_loader.regular(size: 13)))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(action: chooseFolder) {
                            Text(NSLocalizedString("settings_choose_folder", comment: ""))
                        }

                        if !exportFolderPath.isEmpty {
                            Button(action: {
                                exportFolderPath = ""
                                saveExportFolder()
                            }) {
                                Text(NSLocalizedString("settings_reset_folder", comment: ""))
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            Section(title: "Import Method") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose how wallpapers are added to your library.")
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    Picker("", selection: $service.importMethod) {
                        Text("Link/Reference").tag(macpaperService.ImportMethod.link)
                        Text("Copy").tag(macpaperService.ImportMethod.copy)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: service.importMethod) { _ in service.saveSettings() }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    private var playbackSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Section(title: NSLocalizedString("settings_behavior", comment: "Behavior")) {
                SToggle(
                    title: NSLocalizedString("cfg_auto_pause", comment: "Smart Playback"),
                    description: NSLocalizedString("cfg_auto_pause_desc", comment: ""),
                    isOn: $ap_is_enabled
                )
                .onChange(of: ap_is_enabled) { service._ap_enabled($0) }
            }

            Section(title: NSLocalizedString("settings_shuffle", comment: "Shuffle")) {
                VStack(spacing: 10) {
                    SToggle(
                        title: NSLocalizedString("settings_shuffle", comment: "Shuffle Wallpapers"),
                        description: NSLocalizedString("settings_shuffle_desc", comment: ""),
                        isOn: Binding(
                            get: { service.shuffleEnabled },
                            set: { service.setShuffleEnabled($0) }
                        )
                    )

                    if service.shuffleEnabled {
                        SToggle(
                            title: NSLocalizedString("settings_per_desktop_shuffle", comment: "Different wallpaper on every desktop"),
                            description: NSLocalizedString("settings_per_desktop_shuffle_desc", comment: ""),
                            isOn: Binding(
                                get: { service.perSpaceShuffle },
                                set: { service.setPerSpaceShuffle($0) }
                            )
                        )

                        HStack {
                            Text(NSLocalizedString("settings_shuffle_interval", comment: "Change every"))
                                .font(Font(font_loader.regular(size: 13)))
                                .foregroundColor(.secondary)

                            Spacer()

                            Picker("", selection: Binding(
                                get: { service.shuffleInterval },
                                set: { service.setShuffleInterval($0) }
                            )) {
                                ForEach(macpaperService.ShuffleInterval.allCases, id: \.self) { interval in
                                    Text(interval.displayName).tag(interval)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 160)
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            Section(title: "Playback Effects") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wallpaper Scaling")
                        .font(Font(font_loader.regular(size: 14)))
                    
                    Picker("", selection: $scalingMode) {
                        Text("Fill Screen").tag("fill")
                        Text("Fit to Screen").tag("fit")
                        Text("Stretch to Fill").tag("stretch")
                        Text("Center").tag("center")
                        Text("Tile").tag("tile")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: scalingMode) { _ in saveVisualizerSettings() }
                    
                    Text("Video Filter")
                        .font(Font(font_loader.regular(size: 14)))
                        .padding(.top, 8)
                    
                    Picker("", selection: $videoFilter) {
                        Text("None").tag("none")
                        Text("Grayscale").tag("grayscale")
                        Text("Invert").tag("invert")
                        Text("Sepia").tag("sepia")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: videoFilter) { _ in saveVisualizerSettings() }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            Section(title: "Audio Visualizer (beta)") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Visualizer Mode")
                        .font(Font(font_loader.regular(size: 14)))

                    Picker("", selection: $visualizer_mode) {
                        Text("Disabled").tag("disabled")
                        Text("Wallpaper Audio").tag("wallpaper")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: visualizer_mode) { _ in saveVisualizerSettings() }

                    Text("Color Mode")
                        .font(Font(font_loader.regular(size: 14)))
                        .padding(.top, 8)

                    Picker("", selection: $visualizer_colorMode) {
                        Text("Rainbow").tag("rainbow")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: visualizer_colorMode) { _ in saveVisualizerSettings() }

                    if visualizer_colorMode == "custom" {
                        HStack {
                            Text("Color:")
                            TextField("#FF00FF", text: $visualizer_customColor)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                                .onChange(of: visualizer_customColor) { _ in saveVisualizerSettings() }
                        }
                        .padding(.top, 4)
                    }

                    HStack {
                        Text("Transparency:")
                        Slider(value: $visualizer_transparency, in: 0.1...1.0, step: 0.05)
                            .frame(width: 150)
                            .onChange(of: visualizer_transparency) { _ in saveVisualizerSettings() }
                        Text("\(Int(visualizer_transparency * 100))%")
                            .font(Font(font_loader.regular(size: 12)))
                            .frame(width: 35)
                    }
                    .padding(.top, 8)

                    HStack {
                        Text("Bar Count:")
                        Picker("", selection: $visualizer_barCount) {
                            Text("32").tag(32)
                            Text("48").tag(48)
                            Text("64").tag(64)
                            Text("80").tag(80)
                            Text("96").tag(96)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 80)
                        .onChange(of: visualizer_barCount) { _ in saveVisualizerSettings() }
                        Spacer()
                    }
                    .padding(.top, 8)

                    HStack {
                        Text("Max Height:")
                        Slider(value: $visualizer_maxHeight, in: 0.1...1.0, step: 0.05)
                            .frame(width: 150)
                            .onChange(of: visualizer_maxHeight) { _ in saveVisualizerSettings() }
                        Text("\(Int(visualizer_maxHeight * 100))%")
                            .font(Font(font_loader.regular(size: 12)))
                            .frame(width: 35)
                    }
                    .padding(.top, 4)

                    HStack {
                        Text("Min Height:")
                        Slider(value: $visualizer_minHeight, in: 1.0...20.0, step: 1.0)
                            .frame(width: 150)
                            .onChange(of: visualizer_minHeight) { _ in saveVisualizerSettings() }
                        Text("\(Int(visualizer_minHeight))px")
                            .font(Font(font_loader.regular(size: 12)))
                            .frame(width: 35)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            Section(title: NSLocalizedString("settings_volume", comment: "Volume")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(NSLocalizedString("settings_default_volume", comment: "Default Volume"))
                            .font(Font(font_loader.regular(size: 14)))
                        Spacer()
                        Text("\(Int(service.volume * 100))%")
                            .font(Font(font_loader.regular(size: 12)))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $service.volume, in: 0...1, step: 0.05)
                        .onChange(of: service.volume) { service.chvol($0) }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    private func fetchChangelog() {
        changelogLoading = true
        showChangelogSheet = true
        updater.fetchChangelog { text in
            self.changelogText = text
            self.changelogLoading = false
        }
    }

    private func loadVisualizerSettings() {
        let settingsFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/settings.json")

        guard FileManager.default.fileExists(atPath: settingsFile.path),
              let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        visualizer_mode = settings["visualizer_mode"] as? String ?? "disabled"
        visualizer_colorMode = settings["visualizer_colorMode"] as? String ?? "rainbow"
        visualizer_customColor = settings["visualizer_customColor"] as? String ?? "#FF00FF"
        visualizer_transparency = settings["visualizer_transparency"] as? Double ?? 0.6
        visualizer_barCount = settings["visualizer_barCount"] as? Int ?? 64
        visualizer_maxHeight = settings["visualizer_maxHeight"] as? Double ?? 0.5
        visualizer_minHeight = settings["visualizer_minHeight"] as? Double ?? 4.0
        scalingMode = settings["scalingMode"] as? String ?? "fill"
        videoFilter = settings["videoFilter"] as? String ?? "none"
    }

    private func saveVisualizerSettings() {
        let settingsFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/settings.json")

        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsFile.path),
           let data = try? Data(contentsOf: settingsFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        settings["visualizer_mode"] = visualizer_mode
        settings["visualizer_colorMode"] = visualizer_colorMode
        settings["visualizer_customColor"] = visualizer_customColor
        settings["visualizer_transparency"] = visualizer_transparency
        settings["visualizer_barCount"] = visualizer_barCount
        settings["visualizer_maxHeight"] = visualizer_maxHeight
        settings["visualizer_minHeight"] = visualizer_minHeight
        settings["scalingMode"] = scalingMode
        settings["videoFilter"] = videoFilter

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? FileManager.default.createDirectory(
                at: settingsFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: settingsFile)

            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.naomisphere.moonleaf.visualizerSettingsChanged"),
                object: nil,
                deliverImmediately: true
            )
        }
    }

    private func getDisplayFolderName() -> String {
        if exportFolderPath.isEmpty {
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.lastPathComponent
                ?? NSLocalizedString("settings_export_folder_default", comment: "")
        }
        return (exportFolderPath as NSString).lastPathComponent
    }

    private func chooseFolder() {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = NSLocalizedString("settings_choose_folder", comment: "")
        panel.prompt = NSLocalizedString("settings_choose_folder", comment: "")

        if !exportFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: exportFolderPath)
        } else if let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = picturesURL
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.exportFolderPath = url.path
                self.saveExportFolder()
            }
            if previousPolicy == .accessory && NSApp.windows.filter({ $0.isVisible }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func validateAPIKey(_ key: String) {
        if key.isEmpty { apiKeyError = nil; return }
        apiKeyError = key.count != 32 ? NSLocalizedString("settings_invalid_api_key", comment: "") : nil
    }

    private func loadAPIKey() {
        let keyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/WH_API_KEY")
        if FileManager.default.fileExists(atPath: keyFile.path),
           let key = try? String(contentsOf: keyFile) {
            apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func saveAPIKey() {
        if !apiKey.isEmpty && apiKeyError != nil { return }
        isSaving = true
        saveSuccess = false

        let keyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/WH_API_KEY")

        do {
            try FileManager.default.createDirectory(
                at: keyFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if apiKey.isEmpty {
                if FileManager.default.fileExists(atPath: keyFile.path) {
                    try FileManager.default.removeItem(at: keyFile)
                }
            } else {
                try apiKey.write(to: keyFile, atomically: true, encoding: .utf8)
            }
            saveSuccess = true
            showAPIKeyField = false
            apiKeyError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.saveSuccess = false }
        } catch {}

        isSaving = false
    }

    private func toggleAutoStart(_ enabled: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.naomisphere.macpaper.app.plist")
        let executablePath = Bundle.main.executableURL?.path
            ?? "\(Bundle.main.bundlePath)/Contents/MacOS/moonleaf"

        if enabled {
            let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.naomisphere.macpaper.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(executablePath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            do {
                try FileManager.default.createDirectory(
                    at: launchAgent.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try plist.write(to: launchAgent, atomically: true, encoding: .utf8)
                let load = Process()
                load.launchPath = "/bin/launchctl"
                load.arguments = ["load", launchAgent.path]
                load.launch()
                load.waitUntilExit()
            } catch { autoStartEnabled = false }
        } else {
            let unload = Process()
            unload.launchPath = "/bin/launchctl"
            unload.arguments = ["unload", launchAgent.path]
            try? unload.run()
            unload.waitUntilExit()
            try? FileManager.default.removeItem(at: launchAgent)
        }
    }

    private func checkAutoStartStatus() {
        let launchAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.naomisphere.macpaper.app.plist")
        autoStartEnabled = FileManager.default.fileExists(atPath: launchAgent.path)
    }

    private func loadExportFolder() {
        let settingsFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/export_folder")

        if FileManager.default.fileExists(atPath: settingsFile.path),
           let path = try? String(contentsOf: settingsFile) {
            exportFolderPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if exportFolderPath.isEmpty,
           let picturesPath = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path {
            exportFolderPath = picturesPath
        }
    }

    private func saveExportFolder() {
        let settingsFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/export_folder")
        do {
            try FileManager.default.createDirectory(
                at: settingsFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if exportFolderPath.isEmpty {
                if FileManager.default.fileExists(atPath: settingsFile.path) {
                    try FileManager.default.removeItem(at: settingsFile)
                }
            } else {
                try exportFolderPath.write(to: settingsFile, atomically: true, encoding: .utf8)
            }
        } catch {}
    }

    private func validateUpdateServer(_ server: String) {
        if server.isEmpty {
            updateServerError = nil
            return
        }
        if !server.lowercased().hasPrefix("github.com/naomisphere") {
            updateServerError = "Server must start with github.com/naomisphere"
        } else {
            updateServerError = nil
        }
    }

    private func loadUpdateServer() {
        let serverFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/update_server")
        if FileManager.default.fileExists(atPath: serverFile.path),
           let server = try? String(contentsOf: serverFile) {
            let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("github.com/naomisphere") {
                updateServer = trimmed
            }
        }
    }

    private func saveUpdateServer() {
        validateUpdateServer(updateServer)
        if updateServerError != nil { return }
        
        isSavingUpdateServer = true
        let serverFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/macpaper/update_server")
        
        do {
            try FileManager.default.createDirectory(
                at: serverFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if updateServer.isEmpty {
                if FileManager.default.fileExists(atPath: serverFile.path) {
                    try FileManager.default.removeItem(at: serverFile)
                }
            } else {
                try updateServer.write(to: serverFile, atomically: true, encoding: .utf8)
            }
            updateServerSaveSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { updateServerSaveSuccess = false }
        } catch {}
        isSavingUpdateServer = false
    }
}

struct Section<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Font(font_loader.bold(size: 16)))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.leading, 4)
            content
        }
    }
}

struct SToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font(font_loader.regular(size: 14)))
                Text(description)
                    .font(Font(font_loader.regular(size: 12)))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}