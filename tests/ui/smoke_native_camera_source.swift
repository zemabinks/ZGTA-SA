// SPDX-License-Identifier: AGPL-3.0-only
// Authored configuration and deterministic transport scheduling only. The
// camera and installed transport dispatch are production sources, unchanged.
import Foundation
import simd

private final class Request: NativeResourceTask {
    let url: URL
    let completion: NativeResourceTransport.Completion
    var resumes = 0, cancels = 0
    init(_ request: URLRequest, _ completion: @escaping NativeResourceTransport.Completion) {
        url = request.url!; self.completion = completion
    }
    func resume() { resumes += 1 }
    func cancel() { cancels += 1 }
    // Delivery has completed before cancellation, but its main-queue camera
    // publication is still waiting. Cancellation cannot retract that block.
    func complete(_ data: Data?, status: Int = 200) throws {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            self.completion(data, HTTPURLResponse(url: self.url, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil), nil)
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success else { throw Failure("transport delivery timeout") }
    }
}
private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}
private var checks = 0
private func check(_ value: @autoclosure () -> Bool, _ text: String) throws {
    checks += 1; if !value() { throw Failure(text) }
}
private func drain() throws {
    var finished = false
    DispatchQueue.main.async { finished = true }
    let end = Date().addingTimeInterval(5)
    while !finished && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    try check(finished, "main publication queue timeout")
}
private func configuration(_ marker: String) throws -> Data {
    let kinds = ["car", "bike", "heli", "plane"]
    let sight: [String: Double] = ["first": 50, "least": 10, "most": 80]
    // Invented values, chosen for the documented native schema. No archived
    // table, game bytes, credentials or recorded samples are included.
    let document: [String: Any] = [
        "vehicleProfiles": Dictionary(uniqueKeysWithValues: kinds.map { ($0, Array(repeating: 1.0, count: 15)) }),
        "vehicleDistances": Dictionary(uniqueKeysWithValues: kinds.map { ($0, [2.0, 3.0, 4.0]) }),
        "vehicleAngles": Dictionary(uniqueKeysWithValues: kinds.map { ($0, [0.1, 0.2, 0.3]) }),
        "cinematic": ["ground": [1.0, 2.0, 3.0, 4.0], "air": [2.0, 3.0, 4.0, 5.0]],
        "footDistances": [2.0, 3.0, 4.0],
        "footSights": ["scope": sight, "camera": sight, "rocket": sight],
        "footWeaponFov": [[22, 60]], "weaponSights": ["42": marker]
    ]
    return try JSONSerialization.data(withJSONObject: document)
}

@main private enum Main {
    static func main() {
        do { try run(); print("PASS \(checks) authored camera request/source publication checks; no HTTP, UI or retail timing claim") }
        catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
    private static func run() throws {
        try check(Thread.isMainThread, "main owner required")
        var requests: [Request] = []
        NativeResourceTransport.install { request, completion in
            let task = Request(request, completion); requests.append(task); return task
        }
        let a = ServerAddress("http://127.0.0.1:18001")!, b = ServerAddress("http://127.0.0.1:18002")!
        let alpha = try configuration("authored-a"), beta = try configuration("authored-b")
        let camera = NativeGameCamera(persistViews: false)
        camera.setDirection(heading: 1.25, pitch: -0.35)
        camera.setFootZoom(3); camera.setVehicleView(5)
        var aCalls = 0, bCalls = 0
        camera.load(server: a) { aCalls += 1 }
        try check(requests.count == 1 && requests[0].resumes == 1, "ordinary suspended request was not resumed once")
        try check(requests[0].url.path == "/game/native/camera.json", "camera resource route changed")
        try requests[0].complete(alpha)
        camera.load(server: b) { bCalls += 1 }
        try check(requests[0].cancels == 1, "replaced request not cancelled")
        try drain()
        // This is the historical rejection oracle: a finished old callback
        // must not install data or notify its obsolete owner after replacement.
        try check(aCalls == 0 && !camera.isLoaded, "obsolete completed camera request published after source replacement")
        try check(bCalls == 0 && requests[1].resumes == 1, "new source completed before its response")
        try requests[1].complete(beta); try drain()
        try check(bCalls == 1 && camera.sightForWeapon(42) == "authored-b", "current source not published exactly once")
        try check(camera.heading == 1.25 && camera.pitch == -0.35, "resource publication changed input direction")
        try check(camera.footZoom == 3 && camera.vehicleView == 5, "resource replacement changed chosen views")
        // A retry at the same origin also supersedes its earlier invocation.
        var retryOld = 0, retryNew = 0
        camera.load(server: b) { retryOld += 1 }; try requests[2].complete(alpha)
        camera.load(server: b) { retryNew += 1 }; try requests[3].complete(beta)
        try drain()
        try check(retryOld == 0 && retryNew == 1, "same-origin retry published its obsolete request")
        try check(camera.sightForWeapon(42) == "authored-b", "same-origin latest resource was not retained")
        // Rejecting the latest response must not resurrect an older queued
        // success. An already accepted table remains an explicit old fallback.
        var obsolete = 0, invalid = 0
        camera.load(server: a) { obsolete += 1 }; try requests[4].complete(alpha)
        camera.load(server: b) { invalid += 1 }; try requests[5].complete(Data("invalid".utf8))
        try drain()
        try check(obsolete == 0 && invalid == 0 && camera.sightForWeapon(42) == "authored-b", "failed latest request resurrected obsolete configuration")
        var failed = 0
        camera.load(server: a) { failed += 1 }; try requests[6].complete(alpha, status: 503); try drain()
        try check(failed == 0 && camera.sightForWeapon(42) == "authored-b", "HTTP failure replaced the accepted table")
        // Independent camera instances have distinct publication owners.
        let spectator = NativeGameCamera(persistViews: false)
        var spectatorCalls = 0, currentCalls = 0
        spectator.load(server: a) { spectatorCalls += 1 }
        camera.load(server: b) { currentCalls += 1 }
        try requests[7].complete(alpha); try requests[8].complete(beta); try drain()
        try check(spectatorCalls == 1 && currentCalls == 1, "one camera invalidated another camera's request")
        try check(spectator.sightForWeapon(42) == "authored-a" && camera.sightForWeapon(42) == "authored-b", "camera instance source contamination")
        // Source publication completion may synchronously start the next load.
        var first = 0, next = 0
        camera.load(server: a) { first += 1; camera.load(server: b) { next += 1 } }
        try requests[9].complete(alpha); try drain()
        try check(first == 1 && requests.count == 11 && requests[10].resumes == 1, "completion reentry lost the newer request")
        try requests[10].complete(beta); try drain()
        try check(next == 1 && camera.sightForWeapon(42) == "authored-b", "reentrant current request not delivered")
        try check(requests.allSatisfy { $0.resumes == 1 }, "request resumed more than once")
    }
}
