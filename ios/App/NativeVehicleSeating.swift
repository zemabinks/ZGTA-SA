import Foundation

/// Per-model clip identities from the public client's original entry groups,
/// model flags and astride families; game tables remain served by the Mac.
struct NativeVehicleSeating: Decodable {
    struct Definition: Decodable {
        let astride: Bool
        let clips: [String:String]
        let boarding: [String:[String]]
        func clip(_ role: String) -> String { clips[role] ?? clips["sit"] ?? "ped/car_sit" }
    }
    let models: [String:Definition]
}
