// AgentHarnessClient.swift
// Pairs with a Hermes harness server (harness/server.mjs) and streams live agent
// session state over WebSocket. Reconnects automatically and refetches the preview
// screenshot whenever the server bumps `screenshotSeq`.

import Foundation
import HermesShared
import UIKit

@MainActor
final class AgentHarnessClient: ObservableObject {
    enum ConnectionPhase: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Not connected"
            case .connecting: return "Connecting…"
            case .connected: return "Live"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var phase: ConnectionPhase = .disconnected
    @Published private(set) var state: AgentSessionState?
    @Published private(set) var screenshot: UIImage?
    @Published private(set) var lastEventDate: Date?

    /// Persisted so the app re-pairs automatically on next launch.
    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverKey) }
    }
    private var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: Self.tokenKey) }
    }

    var isPaired: Bool { token != nil }

    private static let serverKey = "agentHarness.serverURL"
    private static let tokenKey = "agentHarness.token"

    private var socketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var lastScreenshotSeq = 0
    private var manuallyDisconnected = false

    private let session = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        // Fail fast instead of spinning forever when the server is unreachable —
        // our own reconnect loop handles retries.
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return config
    }())

    var onStateChange: ((AgentSessionState) -> Void)?
    var onSessionEnd: (() -> Void)?

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Self.serverKey) ?? "http://192.168.1.1:8642"
        token = UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    // MARK: - Pairing

    /// Exchanges a 6-digit code shown by the harness server for a long-lived token.
    func pair(code: String) async {
        guard let base = normalizedBaseURL() else {
            phase = .failed("Invalid server URL")
            return
        }
        phase = .connecting
        do {
            var request = URLRequest(url: base.appendingPathComponent("api/pair"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "code": code.trimmingCharacters(in: .whitespaces),
                "deviceName": UIDevice.current.name,
            ])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["token"] as? String else {
                let body = String(data: data, encoding: .utf8) ?? ""
                phase = .failed("Pairing rejected: \(body.prefix(120))")
                return
            }
            token = newToken
            connect()
        } catch {
            phase = .failed("Pairing failed: \(error.localizedDescription)")
        }
    }

    func unpair() {
        disconnect()
        token = nil
        state = nil
        screenshot = nil
        lastScreenshotSeq = 0
    }

    // MARK: - Connection

    func connect() {
        guard let token, let wsURL = webSocketURL(token: token) else { return }
        manuallyDisconnected = false
        reconnectTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)

        phase = .connecting
        let task = session.webSocketTask(with: wsURL)
        socketTask = task
        task.resume()

        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
    }

    func disconnect() {
        manuallyDisconnected = true
        reconnectTask?.cancel()
        receiveLoopTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        phase = .disconnected
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled, task === socketTask {
            do {
                let message = try await task.receive()
                if phase != .connected { phase = .connected }
                switch message {
                case .string(let text):
                    handle(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { handle(text: text) }
                @unknown default:
                    break
                }
            } catch {
                guard task === socketTask, !manuallyDisconnected else { return }
                phase = .failed("Connection lost")
                scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, !self.manuallyDisconnected else { return }
            self.connect()
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let envelope = try? AgentHarnessCoding.decoder().decode(AgentHarnessEnvelope.self, from: data)
        else { return }

        lastEventDate = Date()
        switch envelope.type {
        case .hello, .state:
            if let newState = envelope.state {
                state = newState
                onStateChange?(newState)
                if newState.screenshotSeq != lastScreenshotSeq {
                    lastScreenshotSeq = newState.screenshotSeq
                    if newState.screenshotSeq == 0 {
                        screenshot = nil   // new session cleared the preview
                    } else {
                        Task { await fetchScreenshot() }
                    }
                }
            }
        case .sessionEnd:
            if let newState = envelope.state {
                state = newState
                onStateChange?(newState)
            }
            onSessionEnd?()
        case .ping:
            break
        }
    }

    // MARK: - Screenshot

    private func fetchScreenshot() async {
        guard let token, let base = normalizedBaseURL() else { return }
        var components = URLComponents(
            url: base.appendingPathComponent("api/screenshot"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            screenshot = UIImage(data: data)
        } catch {
            // Preview image is best-effort; next seq bump will retry.
        }
    }

    // MARK: - URL plumbing

    private func normalizedBaseURL() -> URL? {
        var raw = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "http://" + raw }
        raw = raw.replacingOccurrences(of: "ws://", with: "http://")
        raw = raw.replacingOccurrences(of: "wss://", with: "https://")
        if raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    private func webSocketURL(token: String) -> URL? {
        guard let base = normalizedBaseURL(),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }
}
