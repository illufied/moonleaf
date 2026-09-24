//
//  glasswp.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import AVFoundation
import AppKit
import Accelerate
import Foundation
import MediaToolbox
import CoreImage

let g_lock = NSLock()
var g_display_bins = [Float](repeating: 0, count: 96)
let g_bar_count = 64

final class ScreenPlayer {
    let screen: NSScreen
    private(set) var window: NSWindow
    var currentFilePath: String = ""

    
    private var mp: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var currentLayer: CALayer?
    private var loopObserver: NSObjectProtocol?
    private var playerStatusObserver: NSKeyValueObservation?

    
    private var vizView: VisualizerView?
    private var vizEngine: RealVisualizerEngine?

    
    var scalingMode: String = "fill"
    var videoFilter: String = "none"
    var vizMode: String = "disabled"
    var vizColorMode: String = "rainbow"
    var vizCustomColor: String = "#FF00FF"
    var vizTransparency: Double = 0.6
    var vizBarCount: Int = 64
    var vizMaxHeight: Double = 0.5
    var vizMinHeight: Double = 4.0
    var isDaemon: Bool = false

    init(screen: NSScreen, isDaemon: Bool = false) {
        self.screen = screen
        self.isDaemon = isDaemon
        
        let wnd = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        wnd.isOpaque = !isDaemon  
        wnd.backgroundColor = .clear  
        wnd.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        wnd.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        wnd.ignoresMouseEvents = true
        wnd.makeKeyAndOrderFront(nil)
        self.window = wnd
    }

    

    func play(filePath: String, fade: Bool = true) {
        guard let contentView = window.contentView else { return }
        currentFilePath = filePath
        contentView.wantsLayer = true

        let oldLayer   = currentLayer
        let oldPlayer  = mp
        let oldObs     = loopObserver

        if let obs = oldObs { NotificationCenter.default.removeObserver(obs) }
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil

        let ext = (filePath as NSString).pathExtension.lowercased()
        let isStaticImage = ["jpg", "jpeg", "png"].contains(ext)
        let isGIF         = ext == "gif"

        
        
        if (isStaticImage || isGIF) && vizMode != "disabled" {
            vizView?.removeFromSuperview()
            vizView = nil
            vizEngine = nil
        }

        var newLayer: CALayer!

        if isStaticImage {
            newLayer = makeStaticImageLayer(filePath: filePath, bounds: contentView.bounds)
            mp = nil
            playerItem = nil
        } else if isGIF {
            newLayer = makeGIFLayer(filePath: filePath, bounds: contentView.bounds)
            mp = nil
            playerItem = nil
        } else {
            let (layer, player, item) = makeVideoLayer(filePath: filePath, bounds: contentView.bounds)
            newLayer   = layer
            mp         = player
            playerItem = item

            if vizMode != "disabled" {
                vizView?.removeFromSuperview()
                vizView   = nil
                vizEngine = nil
                setupVisualizer(on: window, item: item)
            }
        }

        newLayer.opacity = fade ? 0.0 : 1.0
        contentView.layer?.addSublayer(newLayer)

        if let vv = vizView {
            vv.removeFromSuperview()
            contentView.addSubview(vv)
        }

        currentLayer = newLayer

        if fade {
            if isStaticImage || isGIF {
                crossfade(newLayer: newLayer, oldLayer: oldLayer, oldPlayer: oldPlayer)
            } else if let item = playerItem {
                playerStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak newLayer, weak oldLayer, weak oldPlayer] observedItem, _ in
                    guard observedItem.status == .readyToPlay else { return }
                    DispatchQueue.main.async {
                        guard let nl = newLayer else { return }
                        self?.crossfade(newLayer: nl, oldLayer: oldLayer, oldPlayer: oldPlayer)
                        self?.playerStatusObserver?.invalidate()
                        self?.playerStatusObserver = nil
                    }
                }
            }
        } else {
            oldLayer?.opacity = 1.0
            oldLayer?.removeFromSuperlayer()
            oldPlayer?.pause()
        }
    }

    /// Stops drawing on this screen and leaves the window transparent, so the
    /// desktop picture the system keeps per desktop stays visible. The last
    /// file is remembered in `currentFilePath` for when drawing resumes.
    func clear() {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        mp?.pause()
        mp = nil
        playerItem = nil
        currentLayer?.removeFromSuperlayer()
        currentLayer = nil
        vizView?.removeFromSuperview()
        vizView = nil
        vizEngine = nil
    }

    func updateVolume(_ vol: Float) {
        mp?.volume = vol
    }

    func applySettings(scaling: String, filter: String, viz: String,
                       colorMode: String, customColor: String,
                       transparency: Double, barCount: Int,
                       maxHeight: Double, minHeight: Double) {
        scalingMode     = scaling
        videoFilter     = filter
        vizMode         = viz
        vizColorMode    = colorMode
        vizCustomColor  = customColor
        vizTransparency = transparency
        vizBarCount     = barCount
        vizMaxHeight    = maxHeight
        vizMinHeight    = minHeight
    }

    func resizeToScreen() {
        window.setFrame(screen.frame, display: true)
        if let contentView = window.contentView {
            currentLayer?.frame = contentView.bounds
        }
    }

    

    private func getVideoGravity() -> AVLayerVideoGravity {
        switch scalingMode {
        case "fit": return .resizeAspect
        case "stretch": return .resize
        default: return .resizeAspectFill
        }
    }

    private func getContentsGravity() -> CALayerContentsGravity {
        switch scalingMode {
        case "fit": return .resizeAspect
        case "stretch": return .resize
        case "center": return .center
        default: return .resizeAspectFill
        }
    }

    private func applyFilter(to item: AVPlayerItem) {
        guard videoFilter != "none" else { return }
        let filterName: String
        let localFilter = videoFilter
        switch videoFilter {
        case "grayscale": filterName = "CIColorControls"
        case "invert":    filterName = "CIColorInvert"
        case "sepia":     filterName = "CISepiaTone"
        default: return
        }
        let composition = AVVideoComposition(asset: item.asset) { request in
            var image = request.sourceImage
            if let filter = CIFilter(name: filterName) {
                filter.setValue(image, forKey: kCIInputImageKey)
                if localFilter == "grayscale" { filter.setValue(0.0, forKey: kCIInputSaturationKey) }
                else if localFilter == "sepia" { filter.setValue(1.0, forKey: kCIInputIntensityKey) }
                if let output = filter.outputImage { image = output }
            }
            request.finish(with: image, context: nil)
        }
        item.videoComposition = composition
    }

    private func makeStaticImageLayer(filePath: String, bounds: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        if let img = NSImage(contentsOfFile: filePath) {
            if scalingMode == "tile" {
                layer.backgroundColor = NSColor(patternImage: img).cgColor
            } else {
                var finalImg = img
                if videoFilter != "none", let tiffData = img.tiffRepresentation {
                    let ciImage = CIImage(data: tiffData)
                    let filterName: String
                    switch videoFilter {
                    case "grayscale": filterName = "CIColorControls"
                    case "invert":    filterName = "CIColorInvert"
                    case "sepia":     filterName = "CISepiaTone"
                    default: filterName = ""
                    }
                    if filterName != "", let filter = CIFilter(name: filterName), let input = ciImage {
                        filter.setValue(input, forKey: kCIInputImageKey)
                        if videoFilter == "grayscale" { filter.setValue(0.0, forKey: kCIInputSaturationKey) }
                        else if videoFilter == "sepia"  { filter.setValue(1.0, forKey: kCIInputIntensityKey) }
                        if let output = filter.outputImage {
                            let rep = NSCIImageRep(ciImage: output)
                            let newNSImage = NSImage(size: rep.size)
                            newNSImage.addRepresentation(rep)
                            finalImg = newNSImage
                        }
                    }
                }
                layer.contents = finalImg
                layer.contentsGravity = getContentsGravity()
            }
        }
        return layer
    }

    private func makeVideoLayer(filePath: String, bounds: CGRect) -> (CALayer, AVPlayer, AVPlayerItem) {
        let url  = URL(fileURLWithPath: filePath)
        let item = AVPlayerItem(url: url)
        applyFilter(to: item)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(readVolume())

        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = getVideoGravity()

        player.play()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        mp         = player
        playerItem = item

        return (layer, player, item)
    }

    private func makeGIFLayer(filePath: String, bounds: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: bounds.size)
        layer.contentsGravity = getContentsGravity()

        guard let data = FileManager.default.contents(atPath: filePath),
              let rep = NSBitmapImageRep(data: data),
              let frameCountVal = rep.value(forProperty: NSBitmapImageRep.PropertyKey.frameCount) as? Int,
              frameCountVal > 1 else {
            layer.contents = NSImage(contentsOfFile: filePath)
            return layer
        }

        var frames: [CGImage] = []
        var keyTimes: [NSNumber] = []
        var totalDuration: Double = 0
        var cumulative: Double   = 0

        for i in 0..<frameCountVal {
            rep.setProperty(NSBitmapImageRep.PropertyKey.currentFrame, withValue: NSNumber(value: i))
            let delay = (rep.value(forProperty: NSBitmapImageRep.PropertyKey.currentFrameDuration) as? Double) ?? 0.1
            keyTimes.append(NSNumber(value: cumulative))
            totalDuration += delay
            cumulative    += delay
            if let cg = rep.cgImage { frames.append(cg) }
        }

        guard !frames.isEmpty, totalDuration > 0 else {
            layer.contents = NSImage(contentsOfFile: filePath)
            return layer
        }

        let normalizedTimes = keyTimes.map { NSNumber(value: $0.doubleValue / totalDuration) }
        layer.contents = frames[0]

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values         = frames
        anim.keyTimes       = normalizedTimes
        anim.duration       = totalDuration
        anim.repeatCount    = .infinity
        anim.calculationMode = .discrete
        layer.add(anim, forKey: "gifAnimation")
        return layer
    }

    private func crossfade(newLayer: CALayer, oldLayer: CALayer?, oldPlayer: AVPlayer?) {
        let duration: CFTimeInterval = 1.2
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = Float(0.0)
        fadeIn.toValue   = Float(1.0)
        fadeIn.duration  = duration
        fadeIn.timingFunction  = timing
        fadeIn.fillMode        = .forwards
        fadeIn.isRemovedOnCompletion = false
        newLayer.add(fadeIn, forKey: "fadeIn")
        newLayer.opacity = 1.0

        if let old = oldLayer {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = Float(1.0)
            fadeOut.toValue   = Float(0.0)
            fadeOut.duration  = duration
            fadeOut.timingFunction  = timing
            fadeOut.fillMode        = .forwards
            fadeOut.isRemovedOnCompletion = false
            old.add(fadeOut, forKey: "fadeOut")
            old.opacity = 0.0
        }

        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            oldLayer?.removeFromSuperlayer()
            oldPlayer?.pause()
        }
    }

    private func setupVisualizer(on window: NSWindow, item: AVPlayerItem) {
        guard let contentView = window.contentView else { return }
        let vv = VisualizerView(frame: contentView.bounds)
        vv.autoresizingMask = [.width, .height]
        vv.barCount         = vizBarCount
        vv.colorMode        = vizColorMode
        vv.customColorHex   = vizCustomColor
        vv.transparency     = vizTransparency
        vv.maxHeight        = vizMaxHeight
        vv.minBarHeight     = CGFloat(vizMinHeight)
        contentView.addSubview(vv)
        vizView = vv

        let engine = RealVisualizerEngine(barCount: vizBarCount)
        engine.onUpdate = { [weak vv] bins in vv?.updateBins(bins) }
        engine.attach(to: item)
        vizEngine = engine
    }

    private func readVolume() -> Double {
        let volFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/volume")
        if let data = try? Data(contentsOf: volFile),
           let str = String(data: data, encoding: .utf8),
           let intVal = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Double(max(0, min(100, intVal))) / 100.0
        }
        return 0.5
    }
}

class GlasswpApp: NSObject, NSApplicationDelegate {
    var screenPlayers: [ScreenPlayer] = []
    var entryFilePath: String = ""
    var isDaemon: Bool = false

    /// While this is on, the desktop pictures are owned by the per-desktop
    /// rotation: this overlay spans every desktop, so anything it draws would
    /// hide them. Read once at start-up so a daemon that outlives the app
    /// still agrees with the setting.
    private var perDesktopMode: Bool = UserDefaults(suiteName: "com.naomisphere.macpaper")?
        .bool(forKey: "moonleaf_perSpaceShuffle") ?? false

    
    var vizMode: String      = "disabled"
    var vizColorMode: String = "rainbow"
    var vizCustomColor: String = "#FF00FF"
    var vizTransparency: Double = 0.6
    var vizBarCount: Int     = 64
    var vizMaxHeight: Double = 0.5
    var vizMinHeight: Double = 4.0
    var scalingMode: String  = "fill"
    var videoFilter: String  = "none"

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadVisualizerSettings()
        setupWindows()
        
        
        
        if isDaemon {
            
            
        } else if !perDesktopMode && !entryFilePath.isEmpty && FileManager.default.fileExists(atPath: entryFilePath) {
            for player in screenPlayers {
                player.play(filePath: entryFilePath, fade: false)
            }
        } else {
            
            for player in screenPlayers {
                
            }
        }
        
        registerNotifications()
    }

    /// Point every screen at either the overlay picture or the system desktop
    /// pictures, depending on the per-desktop setting.
    private func applyDrawingMode() {
        if perDesktopMode {
            for p in screenPlayers { p.clear() }
            return
        }
        for p in screenPlayers {
            let path = p.currentFilePath.isEmpty ? entryFilePath : p.currentFilePath
            guard !path.isEmpty else { continue }
            p.play(filePath: path, fade: false)
        }
    }

    

    private func setupWindows() {
        for screen in NSScreen.screens {
            let player = makePlayer(for: screen)
            screenPlayers.append(player)
        }
    }

    private func makePlayer(for screen: NSScreen) -> ScreenPlayer {
        let p = ScreenPlayer(screen: screen, isDaemon: isDaemon)
        applyCurrentSettings(to: p)
        return p
    }

    private func applyCurrentSettings(to p: ScreenPlayer) {
        p.applySettings(
            scaling: scalingMode,
            filter: videoFilter,
            viz: vizMode,
            colorMode: vizColorMode,
            customColor: vizCustomColor,
            transparency: vizTransparency,
            barCount: vizBarCount,
            maxHeight: vizMaxHeight,
            minHeight: vizMinHeight
        )
    }

    

    private func registerNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleVolumeChange(_:)),
            name: Notification.Name("com.naomisphere.moonleaf.volumeChanged"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleVizSettingsChange),
            name: Notification.Name("com.naomisphere.moonleaf.visualizerSettingsChanged"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleAutoPause(_:)),
            name: Notification.Name("com.naomisphere.moonleaf.autoPauseChanged"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleChangeWallpaper(_:)),
            name: Notification.Name("com.naomisphere.moonleaf.changeWallpaper"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handlePerDesktopMode(_:)),
            name: Notification.Name("com.naomisphere.moonleaf.perDesktopMode"), object: nil)

        
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenParameterChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func handleVolumeChange(_ notification: Notification) {
        if let vol = notification.userInfo?["volume"] as? Float {
            DispatchQueue.main.async {
                for p in self.screenPlayers { p.updateVolume(vol) }
            }
        }
    }

    @objc private func handleVizSettingsChange() {
        loadVisualizerSettings()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for p in self.screenPlayers {
                self.applyCurrentSettings(to: p)
            }
            self.applyDrawingMode()
        }
    }

    @objc private func handleAutoPause(_ notification: Notification) {
        if let enabled = notification.userInfo?["ap_is_enabled"] as? Bool, enabled {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(handleWorkspaceChange),
                name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        } else {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
    }

    @objc private func handleWorkspaceChange() {}
    @objc private func handleChangeWallpaper(_ notification: Notification) {
        guard let path = notification.userInfo?["filePath"] as? String else { return }
        let screenIndex = notification.userInfo?["screenIndex"] as? Int

        DispatchQueue.main.async {
            if self.perDesktopMode {
                
                self.entryFilePath = path
                if let idx = screenIndex, idx >= 0, idx < self.screenPlayers.count {
                    self.screenPlayers[idx].currentFilePath = path
                } else {
                    for p in self.screenPlayers { p.currentFilePath = path }
                }
                return
            }
            if let idx = screenIndex {
                guard idx >= 0 && idx < self.screenPlayers.count else { return }
                self.screenPlayers[idx].play(filePath: path, fade: true)
            } else {
                
                for p in self.screenPlayers {
                    p.play(filePath: path, fade: true)
                }
                self.entryFilePath = path
            }
        }
    }

    @objc private func handlePerDesktopMode(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        DispatchQueue.main.async {
            guard self.perDesktopMode != enabled else { return }
            self.perDesktopMode = enabled
            self.applyDrawingMode()
        }
    }
    @objc private func handleScreenParameterChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let current = NSScreen.screens

            
            var keepPlayers: [ScreenPlayer] = []
            for p in self.screenPlayers {
                if current.contains(p.screen) {
                    keepPlayers.append(p)
                } else {
                    p.window.close()
                }
            }

            
            let existingScreens = Set(keepPlayers.map { ObjectIdentifier($0.screen) })
            for screen in current {
                if !existingScreens.contains(ObjectIdentifier(screen)) {
                    let p = self.makePlayer(for: screen)
                    
                    let path = self.entryFilePath.isEmpty ? keepPlayers.first?.currentFilePath ?? "" : self.entryFilePath
                    if !self.perDesktopMode && !path.isEmpty {
                        p.play(filePath: path, fade: false)
                    }
                    keepPlayers.append(p)
                }
            }
            self.screenPlayers = keepPlayers
        }
    }

    

    private func loadVisualizerSettings() {
        let settingsFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moonleaf/settings.json")
        guard FileManager.default.fileExists(atPath: settingsFile.path),
              let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        vizMode         = settings["visualizer_mode"]        as? String ?? "disabled"
        vizColorMode    = settings["visualizer_colorMode"]   as? String ?? "rainbow"
        vizCustomColor  = settings["visualizer_customColor"] as? String ?? "#FF00FF"
        vizTransparency = settings["visualizer_transparency"] as? Double ?? 0.6
        vizBarCount     = settings["visualizer_barCount"]    as? Int    ?? 64
        vizMaxHeight    = settings["visualizer_maxHeight"]   as? Double ?? 0.5
        vizMinHeight    = settings["visualizer_minHeight"]   as? Double ?? 4.0
        scalingMode     = settings["scalingMode"]            as? String ?? "fill"
        videoFilter     = settings["videoFilter"]            as? String ?? "none"
    }
}

final class RealVisualizerEngine {
    private let barCount: Int
    private let fftSize = 2048
    private var fftSetup: OpaquePointer?
    private var hannWindow = [Float]()
    private var realIn = [Float]()
    private var imagIn = [Float]()
    private var realOut = [Float]()
    private var imagOut = [Float]()
    private var smoothed = [Float]()
    private var tap: MTAudioProcessingTap?
    private var displayTimer: DispatchSourceTimer?
    var onUpdate: (([Float]) -> Void)?

    init(barCount: Int) {
        self.barCount = barCount
        smoothed = [Float](repeating: 0, count: barCount)
        g_display_bins = [Float](repeating: 0, count: barCount)

        let n = fftSize
        hannWindow = (0..<n).map { i in
            0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(n - 1)))
        }
        realIn  = [Float](repeating: 0, count: n)
        imagIn  = [Float](repeating: 0, count: n)
        realOut = [Float](repeating: 0, count: n)
        imagOut = [Float](repeating: 0, count: n)

        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        displayTimer = timer
    }

    deinit {
        displayTimer?.cancel()
        if let s = fftSetup { vDSP_DFT_DestroySetup(s) }
    }

    func attach(to playerItem: AVPlayerItem) {
        let retainedSelf = Unmanaged.passRetained(self)
        let clientPtr = retainedSelf.toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientPtr,
            `init`: { (tap, clientInfo, tapStorageOut) in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { (tap) in
                Unmanaged<RealVisualizerEngine>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .release()
            },
            prepare: nil,
            unprepare: nil,
            process: { (tap, frameCount, flags, bufferList, framesOut, flagsOut) in
                MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, nil, framesOut)
                let engine = Unmanaged<RealVisualizerEngine>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                engine.processAudioBuffer(bufferList, frameCount: frameCount)
            }
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tapRef)

        guard status == noErr, let builtTap = tapRef else {
            retainedSelf.release()
            return
        }
        tap = builtTap

        playerItem.asset.loadTracks(withMediaType: .audio) { [weak playerItem] tracks, _ in
            guard let track = tracks?.first, let item = playerItem else { return }
            let inputParams = AVMutableAudioMixInputParameters(track: track)
            inputParams.audioTapProcessor = builtTap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [inputParams]
            DispatchQueue.main.async { item.audioMix = mix }
        }
    }

    func processAudioBuffer(_ bufferListPtr: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        guard frameCount > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        guard let first = buffers.first, let rawData = first.mData else { return }

        let samples = UnsafeBufferPointer<Float>(
            start: rawData.assumingMemoryBound(to: Float.self),
            count: Int(frameCount))

        let n = min(fftSize, Int(frameCount))
        for i in 0..<n  { realIn[i] = samples[i] * hannWindow[i] }
        for i in n..<fftSize { realIn[i] = 0 }
        for i in 0..<fftSize { imagIn[i] = 0 }

        guard let setup = fftSetup else { return }
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        let halfN = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfN)
        for i in 0..<halfN {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        g_lock.lock()
        let displayCount  = self.barCount
        let maxFreqIndex  = min(halfN, Int(Float(n) * 8000.0 / 44100.0))
        let minFreqIndex  = 1
        var newBins       = [Float](repeating: 0, count: displayCount)

        if maxFreqIndex > minFreqIndex {
            let logMin = log10(Float(minFreqIndex))
            let logMax = log10(Float(maxFreqIndex))
            for i in 0..<displayCount {
                let currentLog = logMin + Float(i) * (logMax - logMin) / Float(displayCount - 1)
                let nextLog    = logMin + Float(i + 1) * (logMax - logMin) / Float(displayCount - 1)
                let startIndex = min(maxFreqIndex - 1, max(minFreqIndex, Int(pow(10, currentLog))))
                var endIndex   = min(maxFreqIndex, Int(pow(10, nextLog)))
                if endIndex <= startIndex { endIndex = startIndex + 1 }
                var sum: Float = 0
                for j in startIndex..<endIndex { sum += magnitudes[j] }
                newBins[i] = sum / Float(endIndex - startIndex)
            }
        }

        for i in 0..<displayCount {
            let old  = self.smoothed[i]
            let raw  = newBins[i]
            let mapped = min(1.0, sqrt(raw) * 0.15)
            self.smoothed[i] = old * 0.8 + mapped * 0.2
            g_display_bins[i] = self.smoothed[i]
        }
        g_lock.unlock()
    }

    private func tick() {
        g_lock.lock()
        let bins = Array(g_display_bins.prefix(barCount))
        g_lock.unlock()
        onUpdate?(bins)
    }
}

class VisualizerView: NSView {
    var barCount: Int     = 64
    var colorMode: String = "rainbow"
    var customColorHex: String = "#FF00FF"
    var transparency: Double = 0.6
    var maxHeight: Double  = 0.5
    var minBarHeight: CGFloat = 4.0
    private var bins: [Float] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func updateBins(_ newBins: [Float]) {
        bins = newBins
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !bins.isEmpty else { return }
        let n        = min(bins.count, barCount)
        let barWidth = (bounds.width / CGFloat(n)) * 0.7
        let gap      = (bounds.width / CGFloat(n)) * 0.3
        let maxBH    = bounds.height * CGFloat(maxHeight)
        let alpha    = CGFloat(transparency)

        for i in 0..<n {
            let x = CGFloat(i) * (barWidth + gap) + gap / 2
            let h = max(minBarHeight, CGFloat(bins[i]) * maxBH)
            let rect = NSRect(x: x, y: 0, width: barWidth, height: h)
            let color: NSColor
            if colorMode == "rainbow" {
                color = NSColor(hue: CGFloat(i) / CGFloat(n), saturation: 0.9, brightness: 0.95, alpha: alpha)
            } else {
                color = hexColor(customColorHex, alpha: alpha)
            }
            color.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            path.fill()
        }
    }

    private func hexColor(_ hex: String, alpha: CGFloat) -> NSColor {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt32(h, radix: 16) else {
            return NSColor(hue: 0.8, saturation: 0.9, brightness: 0.95, alpha: alpha)
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8)  & 0xFF) / 255
        let b = CGFloat(value         & 0xFF) / 255
        return NSColor(red: r, green: g, blue: b, alpha: alpha)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = GlasswpApp()

let args = CommandLine.arguments
var filePath: String = ""

if args.contains("--daemon") {
    delegate.isDaemon = true
    
    let filteredArgs = args.filter { $0 != "--daemon" }
    if filteredArgs.count >= 2 {
        
        let path = filteredArgs[1]
        if FileManager.default.fileExists(atPath: path) {
            filePath = path
        }
    }
} else if args.count >= 2 {
    let path = args[1]
    if FileManager.default.fileExists(atPath: path) {
        filePath = path
    }
}

delegate.entryFilePath = filePath

if !delegate.isDaemon && filePath.isEmpty {
    print("error: file not found: \(args.last ?? "")")
    print("usage: glasswp [--daemon] <wallpaper_file>")
    print("       glasswp --daemon")
    exit(1)
}

app.delegate = delegate
app.run()