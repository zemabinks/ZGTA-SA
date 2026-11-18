// SPDX-License-Identifier: AGPL-3.0-only
// Independently authored requests and UI boundaries. No original model bytes.
import Foundation
import CoreGraphics

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard value() else { fatalError(message) }
}

enum AlertStyle { case actionSheet }
enum ActionStyle { case `default`, cancel }
final class UIAlertAction {
    let title: String?
    var isEnabled = true
    let handler: ((UIAlertAction) -> Void)?
    init(title: String?, style: ActionStyle, handler: ((UIAlertAction) -> Void)? = nil) {
        self.title = title; self.handler = handler
    }
}
class Controller {
    var title: String?
    var dismissed = false
    var onDismiss: (() -> Void)?
    func dismiss(animated: Bool, completion: (() -> Void)? = nil) { dismissed = true; onDismiss?(); completion?() }
}
final class Popover { var sourceView: View?; var sourceRect = CGRect.zero }
final class UIAlertController: Controller {
    var message: String?
    var actions: [UIAlertAction] = []
    let popoverPresentationController: Popover? = Popover()
    init(title: String?, message: String?, preferredStyle: AlertStyle) { super.init(); self.title = title; self.message = message }
    func addAction(_ action: UIAlertAction) { actions.append(action) }
}
final class View { var window: Bool? = true; let bounds = CGRect(x: 0, y: 0, width: 960, height: 540) }
enum NativeSAMPArtworkSession {
    enum Phase { case idle, catalog, downloading, importing, acknowledgement, ready, failed, cancelled }
    struct Status { var phase: Phase }
}
final class Artwork { var status = NativeSAMPArtworkSession.Status(phase: .idle) }
final class Legacy {
    var sent: [[String: Any]] = [], success = true
    func send(_ packet: [String: Any]) -> Bool { sent.append(packet); return success }
}
final class Network { var legacy: Legacy? = Legacy() }
final class Label { var text: String? }
final class AdmissionRenderer {
    let selection = NativeActorSelection()
    var actorSelectionState: NativeActorSelection.State? { selection.state }
}
final class ClassPanelOwner {
    let view = View(), status = Label(), network = Network()
    var renderer: AdmissionRenderer? = AdmissionRenderer()
    var legacyArtwork: Artwork?, legacyClassSkin: Int?
    var legacyClassPresentation: UUID?
    var presentedViewController: Controller?
    var resets = 0
    func resetControls() { resets += 1 }
    func present(_ panel: Controller, animated: Bool) {
        presentedViewController = panel
        panel.onDismiss = { [weak self, weak panel] in
            if self?.presentedViewController === panel { self?.presentedViewController = nil }
        }
    }
    func dismiss(animated: Bool) { presentedViewController = nil }
    // ACTUAL_CLASS_METHODS
}

func helperChecks() {
    let domains: [NativeActorSelection.Domain] = [.native, .legacy]
    for oldDomain in domains { for newDomain in domains {
        for oldSkin in [0, 3, 7, 20001] { for newSkin in [0, 3, 7, 20001] {
            let owner = NativeActorSelection()
            var events: [NativeActorSelection.State] = []
            owner.onChange = { events.append($0) }
            let old = owner.begin(domain: oldDomain, skin: oldSkin, sourceIdentity: "source-a")
            let fresh = owner.begin(domain: newDomain, skin: newSkin, sourceIdentity: "source-a")
            check(old.token != fresh.token, "Each occurrence needs distinct ownership")
            check(!owner.owns(old, sourceIdentity: "source-a"), "New domain left old request live")
            check(!owner.applied(old, nativeSkin: oldSkin, sourceIdentity: "source-a"), "Stale completion was applied")
            check(!owner.unavailable(old, sourceIdentity: "source-a", message: "old error"), "Old error overwrote new pending state")
            check(events.count == 2 && owner.state?.request == fresh && owner.state?.phase == .pending, "Stale completion emitted a callback")
            check(owner.applied(fresh, nativeSkin: newSkin, sourceIdentity: "source-a"), "Current request failed admission")
            check(!owner.applied(fresh, nativeSkin: newSkin, sourceIdentity: "source-a"), "Duplicate admission emitted twice")
            check(events.count == 3 && owner.state?.nativeSkin == newSkin, "Applied state missing")
        }}
    }}
    for domain in domains {
        for invalid in [-1, 65536, Int.min, Int.max] {
            let owner = NativeActorSelection()
            let old = owner.begin(domain: .native, skin: 0, sourceIdentity: "source-a")
            let bad = owner.begin(domain: domain, skin: invalid, sourceIdentity: "source-a")
            check(owner.state?.phase == .unavailable && owner.state?.request == bad, "Unsupported request has no typed failure")
            check(!owner.applied(old, nativeSkin: 0, sourceIdentity: "source-a"), "Unsupported newer request left prior CJ live")
        }
        let owner = NativeActorSelection()
        let first = owner.begin(domain: domain, skin: 0, sourceIdentity: "source-a")
        check(!owner.owns(first, sourceIdentity: "source-b"), "Source swap retained publication permission")
        check(!owner.applied(first, nativeSkin: 0, sourceIdentity: "source-b"), "New source admitted old assets")
        check(owner.invalidateSource("source-b") && owner.state?.phase == .cancelled, "Source change did not revoke pending admission")
        check(!owner.invalidateSource("source-b"), "Repeated source change emitted cancellation twice")
        let second = owner.begin(domain: domain, skin: 0, sourceIdentity: "source-b")
        owner.cancel(); owner.cancel()
        check(!owner.applied(second, nativeSkin: 0, sourceIdentity: "source-b"), "Lifecycle cancellation was undone by late load")
        let retry = owner.begin(domain: domain, skin: 0, sourceIdentity: "source-b")
        check(owner.applied(retry, nativeSkin: 0, sourceIdentity: "source-b"), "Explicit retry remained cancelled")
        owner.cancel()
        check(owner.state?.nativeSkin == nil && owner.state?.phase == .cancelled, "Cancelled applied state enabled class SPAWN")
    }
    let custom = NativeActorSelection()
    for skin in [311, 20001, 30000] {
        _ = custom.begin(domain: .legacy, skin: skin, sourceIdentity: "source-a")
        check(custom.state?.phase == .pending, "Valid legacy ID rejected")
    }
    for skin in [312, 20000, 30001, 65535] {
        _ = custom.begin(domain: .legacy, skin: skin, sourceIdentity: "source-a")
        check(custom.state?.phase == .unavailable, "Unsupported legacy ID admitted")
    }
    let empty = custom.begin(domain: .native, skin: 7, sourceIdentity: "")
    check(!custom.owns(empty, sourceIdentity: ""), "Missing resource authority admitted request")
    let live = custom.begin(domain: .native, skin: 7, sourceIdentity: "a")
    check(!custom.applied(live, nativeSkin: -1, sourceIdentity: "a") && custom.state?.phase == .pending, "Invalid mapped ID altered state")
    check(custom.unavailable(live, sourceIdentity: "a", message: String(repeating: "x", count: 2048)), "Failure was not reported")
    check(custom.state?.message?.count == 512, "Unbounded resource failure retained")

    let reentrant = NativeActorSelection()
    var replacement: NativeActorSelection.Request?
    reentrant.onChange = { state in
        if state.request.skin == 0 && state.phase == .pending {
            replacement = reentrant.begin(domain: .legacy, skin: 3, sourceIdentity: "source-a")
        }
    }
    let outer = reentrant.begin(domain: .native, skin: 0, sourceIdentity: "source-a")
    check(!reentrant.owns(outer, sourceIdentity: "source-a") && reentrant.state?.request == replacement, "Synchronous observer stole replacement intent")
}

func classChecks() {
    let owner = ClassPanelOwner()
    let selection = owner.renderer!.selection
    selection.onChange = { [weak owner] in owner?.actorSelectionChanged($0) }
    let request = selection.begin(domain: .legacy, skin: 0, sourceIdentity: "a")
    owner.showLegacyClass(skin: 0)
    let panel = owner.presentedViewController as! UIAlertController
    let spawn = panel.actions.first { $0.title == "SPAWN" }!
    check(!spawn.isEnabled && panel.message!.contains("LOADING"), "Pending CJ class exposed SPAWN")
    check(panel.actions.map(\.title) == ["Previous", "SPAWN", "Next", "Back to servers"], "Class navigation/recovery disappeared")
    _ = selection.applied(request, nativeSkin: 0, sourceIdentity: "a")
    check(spawn.isEnabled && panel.message == "Skin 0", "Admitted CJ did not enable normal SPAWN")
    owner.legacyArtwork = Artwork()
    for phase in [NativeSAMPArtworkSession.Phase.catalog, .downloading, .importing, .acknowledgement, .failed, .cancelled] {
        owner.legacyArtwork!.status.phase = phase; owner.updateLegacyClassAdmission()
        check(!spawn.isEnabled && panel.message!.contains("SERVER MODEL DOWNLOADS"), "Model admission bypassed existing artwork barrier")
    }
    owner.legacyArtwork!.status.phase = .ready; owner.updateLegacyClassAdmission()
    check(spawn.isEnabled, "Both admitted barriers did not enable SPAWN")
    spawn.handler?(spawn)
    check(owner.network.legacy!.sent.count == 1 && owner.network.legacy!.sent[0]["t"] as? String == "spawn", "Normal action did not send protocol SPAWN")

    let fresh = selection.begin(domain: .legacy, skin: 3, sourceIdentity: "a")
    check(!spawn.isEnabled && panel.message!.contains("WAITING"), "New class request left previous action active")
    owner.showLegacyClass(skin: 3)
    let next = owner.presentedViewController as! UIAlertController
    let nextSpawn = next.actions.first { $0.title == "SPAWN" }!
    check(!nextSpawn.isEnabled, "Next pending class used old applied skin")
    check(!selection.applied(request, nativeSkin: 0, sourceIdentity: "a"), "Old CJ completion regained class authority")
    check(!nextSpawn.isEnabled, "Old completion enabled wrong SPAWN")
    _ = selection.unavailable(fresh, sourceIdentity: "a", message: "MODEL UNAVAILABLE")
    check(!nextSpawn.isEnabled && next.message!.contains("Previous or Next"), "Failure left a dead-end/no recovery text")
    next.actions.first { $0.title == "Previous" }!.handler?(next.actions[0])
    next.actions.first { $0.title == "Next" }!.handler?(next.actions[2])
    check(owner.network.legacy!.sent.suffix(2).compactMap { $0["delta"] as? Int } == [-1, 1], "Normal retry navigation changed protocol")

    let native = selection.begin(domain: .native, skin: 3, sourceIdentity: "a")
    _ = selection.applied(native, nativeSkin: 3, sourceIdentity: "a")
    check(!nextSpawn.isEnabled, "Native appearance enabled unrelated legacy class")
    let retry = selection.begin(domain: .legacy, skin: 3, sourceIdentity: "a")
    _ = selection.applied(retry, nativeSkin: 3, sourceIdentity: "a")
    check(nextSpawn.isEnabled, "Fresh matching retry did not recover")
    selection.cancel()
    let sent = owner.network.legacy!.sent.count
    // Invoke the real action even though the fake UI is disabled, modelling a
    // source/lifecycle change between UIKit activation and handler execution.
    nextSpawn.handler?(nextSpawn)
    check(owner.network.legacy!.sent.count == sent, "Activation race sent SPAWN after cancellation")
    owner.legacyClassSkin = nil
    check(!owner.legacyClassCanSpawn(skin: 3), "Old class retained authority after disconnect")
    owner.updateLegacyClassAdmission()
    check(!nextSpawn.isEnabled && next.message == "CHARACTER SELECTION DISCONNECTED", "Disconnected class left an enabled stale action")
    // The raced activation queued a UI recovery. A newer ownership boundary
    // must win even when that queued closure is finally dispatched.
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    check(owner.legacyClassSkin == nil && owner.presentedViewController === next, "Delayed retry reopened an obsolete class after disconnect")
}

helperChecks()
classChecks()
// ACTUAL_RENDERER_CHECKS
print("actor-selection PASS \(checks)")
