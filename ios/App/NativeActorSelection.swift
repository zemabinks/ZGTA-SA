// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Admission of one requested appearance, independent of server-owned skin
/// identity. Callers must fence asynchronous work before changing the model;
/// a successful network command is not evidence that its resources are ready.
final class NativeActorSelection {
    enum Domain: String, Equatable { case native, legacy }
    enum Phase: String, Equatable { case pending, applied, unavailable, cancelled }

    struct Request: Equatable {
        let token: UUID
        let domain: Domain
        let skin: Int
        let sourceIdentity: String
    }

    struct State: Equatable {
        let request: Request
        let phase: Phase
        let nativeSkin: Int?
        let message: String?

        func allowsLegacySpawn(skin: Int, artworkReady: Bool) -> Bool {
            artworkReady && request.domain == .legacy && request.skin == skin &&
                phase == .applied && nativeSkin != nil
        }

        func legacyClassMessage(skin: Int) -> String {
            guard request.domain == .legacy, request.skin == skin else {
                return "Skin \(skin)\nWAITING FOR CHARACTER MODEL"
            }
            switch phase {
            case .pending: return "Skin \(skin)\nLOADING CHARACTER MODEL"
            case .applied: return "Skin \(skin)"
            case .unavailable:
                return "Skin \(skin)\n\(message ?? "CHARACTER MODEL UNAVAILABLE"). Choose Previous or Next to retry."
            case .cancelled:
                return "Skin \(skin)\nCHARACTER MODEL REQUEST CANCELLED. Choose Previous or Next to retry."
            }
        }
    }

    private(set) var state: State?
    var onChange: ((State) -> Void)?

    /// Even an unsupported newer request supersedes a pending older request.
    /// Domain switching therefore cannot leave independent native/SA-MP intents.
    @discardableResult func begin(domain: Domain, skin: Int, sourceIdentity: String) -> Request {
        let request = Request(token: UUID(), domain: domain, skin: skin, sourceIdentity: sourceIdentity)
        let supported = domain == .native ? (0...65535).contains(skin) :
            ((0...311).contains(skin) || (20001...30000).contains(skin))
        let valid = supported && !sourceIdentity.isEmpty
        publish(.init(request: request, phase: valid ? .pending : .unavailable, nativeSkin: nil,
                      message: valid ? nil : "UNSUPPORTED CHARACTER MODEL REQUEST"))
        return request
    }

    /// Must precede any visible model/skin mutation, including cached successes.
    /// Pending-only ownership makes duplicate completions harmless.
    func owns(_ request: Request, sourceIdentity: String) -> Bool {
        state?.request == request && state?.phase == .pending &&
            request.sourceIdentity == sourceIdentity
    }

    @discardableResult func applied(_ request: Request, nativeSkin: Int, sourceIdentity: String) -> Bool {
        guard (0...65535).contains(nativeSkin), owns(request, sourceIdentity: sourceIdentity) else { return false }
        publish(.init(request: request, phase: .applied, nativeSkin: nativeSkin, message: nil))
        return true
    }

    @discardableResult func unavailable(_ request: Request, sourceIdentity: String, message: String) -> Bool {
        guard owns(request, sourceIdentity: sourceIdentity) else { return false }
        publish(.init(request: request, phase: .unavailable, nativeSkin: nil,
                      message: String(message.prefix(512))))
        return true
    }

    /// Explicit lifecycle cancellation never changes canonical identity or the
    /// already drawn model. It only revokes permission for deferred publication.
    func cancel() {
        guard let state, state.phase != .cancelled else { return }
        publish(.init(request: state.request, phase: .cancelled, nativeSkin: nil, message: nil))
    }

    @discardableResult func invalidateSource(_ sourceIdentity: String) -> Bool {
        guard let state, state.request.sourceIdentity != sourceIdentity else { return false }
        let changed = state.phase != .cancelled
        cancel()
        return changed
    }

    private func publish(_ state: State) {
        self.state = state
        onChange?(state)
    }
}
