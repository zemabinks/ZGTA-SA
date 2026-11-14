import Foundation

/// The same account, garage, and mission API used by the local browser client.
/// URLSession shares the guest session cookie obtained on the connect screen.
final class NativeGameplayClient {
    private let server: ServerAddress
    private(set) var state: [String: Any] = [:]
    private var busy = false
    var onState: (([String: Any]) -> Void)?
    var onResult: ((String) -> Void)?

    init(server: ServerAddress) { self.server = server }

    func refresh() {
        guard !busy else { return }
        URLSession.shared.dataTask(with: server.path("api/local/state")) { [weak self] data, response, error in
            guard let self else { return }
            if let data, let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (response as? HTTPURLResponse)?.statusCode == 200 {
                DispatchQueue.main.async {
                    self.state = state
                    self.onState?(state)
                }
            } else if let error {
                DispatchQueue.main.async { self.onResult?("GAMEPLAY: \(error.localizedDescription)") }
            }
        }.resume()
    }

    func perform(_ action: String, payload: [String: Any] = [:]) {
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: server.path("api/local/action"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload.merging(["action": action]) { _, new in new })
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            DispatchQueue.main.async {
                self.busy = false
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   let next = body["state"] as? [String: Any] {
                    self.state = next
                    self.onState?(next)
                    self.onResult?((body["message"] as? String) ?? "DONE")
                } else {
                    self.onResult?((body["error"] as? String) ?? error?.localizedDescription ?? "Action failed")
                }
            }
        }.resume()
    }
}
