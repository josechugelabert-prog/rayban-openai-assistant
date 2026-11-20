import AVFoundation
import Foundation
import Security
import SwiftUI
import UIKit

private enum AssistantError: LocalizedError {
  case settings, microphone, recording, image, response, storage
  case server(Int)

  var errorDescription: String? {
    switch self {
    case .settings: "Configura la URL HTTPS y el token de tu servidor."
    case .microphone: "Permite el acceso al micrófono en Ajustes."
    case .recording: "No se pudo grabar audio. Comprueba el micrófono y vuelve a intentarlo."
    case .image: "No se pudo preparar la foto para enviarla."
    case .response: "El servidor devolvió una respuesta inválida."
    case .storage: "No se pudo acceder al llavero de iOS."
    case .server(401): "El servidor rechazó el token."
    case .server(429): "Demasiadas consultas. Espera un momento."
    case .server(let status): "La consulta falló (HTTP \(status))."
    }
  }
}

private enum AssistantCredentials {
  static func query(_ url: URL) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.raybanassistant.server",
      kSecAttrAccount as String: url.absoluteString,
    ]
  }

  static func read(_ url: URL) throws -> String {
    var lookup = query(url)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &item)
    if status == errSecItemNotFound { throw AssistantError.settings }
    guard status == errSecSuccess, let data = item as? Data,
          let value = String(data: data, encoding: .utf8) else { throw AssistantError.storage }
    return value
  }

  static func save(_ token: String, for url: URL) throws {
    let lookup = query(url)
    let data = Data(token.utf8)
    let status = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = lookup
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AssistantError.storage }
    } else if status != errSecSuccess {
      throw AssistantError.storage
    }
  }
}

private final class AssistantNoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private struct AssistantRequest: Encodable {
  let text: String
  let image: String?
  let audio: String?
}

private struct AssistantReply: Decodable {
  let answer: String
  let transcript: String?
}

@MainActor
struct AssistantView: View {
  let image: UIImage?
  @AppStorage("assistant.server") private var server = ""
  @Environment(\.scenePhase) private var scenePhase
  @State private var editorServer = ""
  @State private var editorToken = ""
  @State private var showSettings = false
  @State private var prompt = ""
  @State private var answer = ""
  @State private var transcript = ""
  @State private var error = ""
  @State private var route = ""
  @State private var audio: Data?
  @State private var recorder: AVAudioRecorder?
  @State private var recordingTimer: Task<Void, Never>?
  @State private var microphoneTask: Task<Void, Never>?
  @State private var requestTask: Task<Void, Never>?
  @State private var speaker = AVSpeechSynthesizer()

  init(image: UIImage? = nil) {
    self.image = image
  }

  var body: some View {
    Form {
      Section("Consulta") {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 220)
            .accessibilityLabel("Foto de las gafas")
        }
        TextField("Escribe una pregunta", text: $prompt, axis: .vertical)
          .lineLimit(2...5)
        Button(recorder == nil ? "Grabar (hasta 30 s)" : "Detener grabación") {
          if recorder == nil { startRecording() } else { stopRecording(keep: true) }
        }
        .disabled(requestTask != nil || microphoneTask != nil)
        if !route.isEmpty { Text("Micrófono: \(route)").font(.caption) }
        if audio != nil {
          Button("Descartar grabación", role: .destructive) { audio = nil }
        }
        Button("Enviar a OpenAI") { send() }
          .disabled(requestTask != nil || recorder != nil || microphoneTask != nil ||
                    (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                     audio == nil && image == nil))
        if requestTask != nil { ProgressView("Consultando") }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }
      if !answer.isEmpty {
        Section("Respuesta") {
          if !transcript.isEmpty { Text(transcript).foregroundStyle(.secondary) }
          Text(answer).textSelection(.enabled)
          Button("Leer respuesta") { speak() }
          .disabled(recorder != nil || microphoneTask != nil)
        }
      }
      Button("Configurar servidor") {
        editorServer = server
        editorToken = ""
        showSettings = true
      }
    }
    .sheet(isPresented: $showSettings, onDismiss: { editorToken = "" }) {
      Form {
        TextField("https://servidor.example/v1/ask", text: $editorServer)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        SecureField("Token del servidor", text: $editorToken)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Guardar") {
          do {
            let url = try endpoint(editorServer)
            let token = editorToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count >= 32, token.utf8.allSatisfy({ (33...126).contains($0) })
            else { throw AssistantError.settings }
            try AssistantCredentials.save(token, for: url)
            server = url.absoluteString
            error = ""
            showSettings = false
          } catch {
            self.error = error.localizedDescription
          }
        }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
        Button("Cancelar") { showSettings = false }
      }
    }
    .onDisappear { cleanUp() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { cleanUp() }
    }
  }

  private func endpoint(_ value: String) throws -> URL {
    let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parts = URLComponents(string: input), parts.scheme == "https",
          let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
          parts.path == "/v1/ask", parts.query == nil, parts.fragment == nil,
          let url = parts.url else { throw AssistantError.settings }
    return url
  }

  private func startRecording() {
    error = ""
    microphoneTask = Task {
      defer { microphoneTask = nil }
      let granted = await AVAudioApplication.requestRecordPermission()
      guard !Task.isCancelled else { return }
      guard granted else {
        error = AssistantError.microphone.localizedDescription
        return
      }

      let session = AVAudioSession.sharedInstance()
      let file = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
      do {
        speaker.stopSpeaking(at: .immediate)
        let options: AVAudioSession.CategoryOptions
        if #available(iOS 26.0, *) {
          options = [.allowBluetoothHFP, .defaultToSpeaker]
        } else {
          options = [.allowBluetooth, .defaultToSpeaker]
        }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true)
        if let bluetooth = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
          try? session.setPreferredInput(bluetooth)
        }
        let recording = try AVAudioRecorder(url: file, settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 16_000,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 32_000,
        ])
        guard recording.record(forDuration: 30) else { throw AssistantError.recording }
        audio = nil
        recorder = recording
        route = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        recordingTimer = Task {
          try? await Task.sleep(for: .seconds(30))
          if !Task.isCancelled { stopRecording(keep: true) }
        }
      } catch {
        try? FileManager.default.removeItem(at: file)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        self.error = error.localizedDescription
      }
    }
  }

  private func stopRecording(keep: Bool) {
    recordingTimer?.cancel()
    recordingTimer = nil
    guard let recording = recorder else { return }
    recording.stop()
    recorder = nil
    defer {
      try? FileManager.default.removeItem(at: recording.url)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    if keep {
      if let data = try? Data(contentsOf: recording.url), !data.isEmpty { audio = data }
      else { error = AssistantError.recording.localizedDescription }
    }
  }

  private func cleanUp() {
    microphoneTask?.cancel()
    requestTask?.cancel()
    stopRecording(keep: false)
    audio = nil
    route = ""
    speaker.stopSpeaking(at: .immediate)
  }

  private func jpeg(_ image: UIImage) throws -> Data {
    let size = image.size
    guard size.width > 0, size.height > 0 else { throw AssistantError.image }
    let scale = min(1, 1600 / max(size.width, size.height))
    let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let data = UIGraphicsImageRenderer(size: target, format: format)
      .jpegData(withCompressionQuality: 0.8) { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
      }
    guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else { throw AssistantError.image }
    return data
  }

  private func send() {
    error = ""
    requestTask = Task {
      defer { requestTask = nil }
      do {
        let url = try endpoint(server)
        let token = try AssistantCredentials.read(url)
        let imageData = try image.map { try jpeg($0).base64EncodedString() }
        var request = URLRequest(url: url, timeoutInterval: 95)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AssistantRequest(
          text: prompt, image: imageData, audio: audio?.base64EncodedString()))
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request, delegate: AssistantNoRedirect())
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AssistantError.response }
        guard http.statusCode == 200 else { throw AssistantError.server(http.statusCode) }
        let reply = try JSONDecoder().decode(AssistantReply.self, from: data)
        answer = reply.answer
        transcript = reply.transcript ?? ""
        audio = nil
        if !transcript.isEmpty { speak() }
      } catch {
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }

  private func speak() {
    speaker.stopSpeaking(at: .immediate)
    speaker.usesApplicationAudioSession = false
    let utterance = AVSpeechUtterance(string: answer)
    utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
    speaker.speak(utterance)
  }
}
