import Foundation
import AVFoundation
import CoreLocation
import NetworkExtension
import Combine

/// Strategy used to keep the app alive while the proxy runs in the background.
///
/// iOS suspends apps shortly after they enter the background unless a supported
/// background mode is active. The practical, sideload-friendly approaches are:
///  - `.audio`: a looping silent audio stream (playback mode)
///  - `.location`: continuous background location updates
///  - `.microphone`: silent recording keeps the process alive
///  - `.camera`: an active capture session keeps the process alive
///  - `.vpn`: a (personal) VPN tunnel configuration keeps the process alive
enum BackgroundMode: String, CaseIterable, Codable, Identifiable {
    case off
    case audio
    case location
    case vpn
    case microphone
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Выключено"
        case .audio: return "Тихий звук"
        case .location: return "Геолокация"
        case .vpn: return "VPN"
        case .microphone: return "Микрофон"
        case .camera: return "Камера"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "Приложение будет приостановлено в фоне"
        case .audio: return "Бесшумный аудио-цикл держит процесс активным"
        case .location: return "Фоновые обновления геопозиции держат процесс активным"
        case .vpn: return "Активация VPN-туннеля держит процесс активным"
        case .microphone: return "Бесшумная запись с микрофона держит процесс активным"
        case .camera: return "Работающая камера держит процесс активным"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "pause.circle"
        case .audio: return "speaker.wave.2.fill"
        case .location: return "location.fill"
        case .vpn: return "lock.shield.fill"
        case .microphone: return "mic.fill"
        case .camera: return "video.fill"
        }
    }
}

/// Keeps the app alive in the background while the proxy is running, using the
/// user-selected `BackgroundMode`.
final class BackgroundKeepAlive: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeepAlive()

    private static let defaultsKey = "background_keepalive_mode"

    /// The currently selected background strategy. Persisted across launches.
    @Published var mode: BackgroundMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
            Log.info("Фоновый режим изменён: \(mode.title)")
            if isRunning {
                restart()
            }
        }
    }

    // Audio keep-alive resources.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    // Location keep-alive resources.
    private var locationManager: CLLocationManager?

    // Microphone keep-alive resources.
    private var recorder: AVAudioRecorder?
    private var micURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tgws_mic_silence.caf")
    }

    // Camera keep-alive resources.
    private var captureSession: AVCaptureSession?

    // VPN keep-alive resources.
    private var vpnManager: NEVPNManager?

    private let queue = DispatchQueue(label: "tgws.backgroundKeepAlive", qos: .userInitiated)
    private var isRunning = false

    private override init() {
        mode = UserDefaults.standard.string(forKey: Self.defaultsKey)
            .flatMap(BackgroundMode.init(rawValue:)) ?? .audio
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Lifecycle

    /// Starts the keep-alive loop using the current mode.
    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            switch self.mode {
            case .audio:
                self.startAudio()
            case .location:
                self.startLocation()
            case .vpn:
                self.startVPN()
            case .microphone:
                self.startMicrophone()
            case .camera:
                self.startCamera()
            case .off:
                self.isRunning = false
            }
        }
    }

    /// Stops any running keep-alive loop.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopAudio()
            self.stopLocation()
            self.stopVPN()
            self.stopMicrophone()
            self.stopCamera()
            self.isRunning = false
        }
    }

    /// Re-applies the currently selected mode (called when the mode changes while active).
    private func restart() {
        stop()
        start()
    }

    // MARK: - Audio strategy

    private func startAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            scheduleSilence()
            player.play()
            Log.debug("Фоновый режим «Тихий звук» активен")
        } catch {
            Log.warning("Фоновый аудио-режим не удался: \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Schedules 10 seconds of silence, re-scheduling itself endlessly.
    private func scheduleSilence() {
        let frameCount = AVAudioFrameCount(format.sampleRate * 10)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        // The buffer is zero-filled (silence) by default; no audio is audible.
        player.scheduleBuffer(buffer) { [weak self] in
            self?.scheduleSilence()
        }
    }

    // MARK: - Location strategy

    private func startLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            Log.warning("Службы геолокации недоступны")
            return
        }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 500
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        locationManager = manager

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            Log.debug("Фоновый режим «Геолокация» активен")
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        default:
            Log.warning("Нет разрешения на геолокацию — запросите его в настройках приложения")
        }
    }

    private func stopLocation() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            Log.debug("Разрешение на геолокацию получено — фоновый режим активен")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.warning("Ошибка фоновой геолокации: \(error.localizedDescription)")
    }

    // MARK: - VPN strategy

    private func startVPN() {
        let manager = NEVPNManager.shared()
        manager.loadFromPreferences { [weak self] error in
            guard let self else { return }
            if let error = error {
                Log.warning("Не удалось загрузить VPN-конфигурацию: \(error.localizedDescription)")
                return
            }
            // Best-effort: enable and start the existing personal VPN configuration.
            manager.isEnabled = true
            do {
                try manager.connection.startVPNTunnel()
                self.vpnManager = manager
                Log.debug("Фоновый режим «VPN» активирован")
            } catch {
                Log.warning("Не удалось запустить VPN-туннель: \(error.localizedDescription). "
                            + "Требуется entitlement Personal VPN и настроенная конфигурация.")
            }
        }
    }

    private func stopVPN() {
        vpnManager?.connection.stopVPNTunnel()
        vpnManager = nil
    }

    // MARK: - Microphone strategy

    private func startMicrophone() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            guard let self, granted else {
                Log.warning("Нет разрешения на микрофон")
                return
            }
            self.queue.async {
                do {
                    try session.setCategory(.record, mode: .default, options: [])
                    try session.setActive(true)
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatAppleIMA4),
                        AVSampleRateKey: 8000.0,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 32000
                    ]
                    let rec = try AVAudioRecorder(url: self.micURL, settings: settings)
                    rec.isMeteringEnabled = true
                    rec.prepareToRecord()
                    // Long silent recording; iOS keeps the process alive while recording.
                    rec.record(forDuration: 86400)
                    self.recorder = rec
                    Log.debug("Фоновый режим «Микрофон» активен")
                } catch {
                    Log.warning("Фоновый микрофон не удался: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopMicrophone() {
        recorder?.stop()
        recorder = nil
        try? FileManager.default.removeItem(at: micURL)
    }

    // MARK: - Camera strategy

    private func startCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self, granted else {
                Log.warning("Нет разрешения на камеру")
                return
            }
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                Log.warning("Фоновая камера недоступна")
                return
            }
            session.addInput(input)
            session.startRunning()
            self.captureSession = session
            Log.debug("Фоновый режим «Камера» активен")
        }
    }

    private func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
    }
}