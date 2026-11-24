// SPDX-License-Identifier: AGPL-3.0-only
import MetalKit
import UniformTypeIdentifiers

/// Displays the verified local model with the same mesh, material, texture and
/// Metal draw path the world renderer uses for stock objects.
final class NativeISOModelViewController: UIViewController, UIDocumentPickerDelegate, MTKViewDelegate {
    private static let worker = DispatchQueue(label: "org.zgtasa.install-model", qos: .userInitiated)
    private let store = NativeResourceStore.shared
    private let showsRegion: Bool
    private var world: NativeWorldRenderer?
    private lazy var canvas = world?.view ?? MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    private var identifier: String { showsRegion ? "isoRegion" : "isoModel" }
    private let status = UILabel()
    private let choose = UIButton(configuration: .filled())
    private let cancel = UIButton(configuration: .plain())
    private var job: NativeISOExtraction.Cancellation?
    private var scene: InstalledModelScene?
    private var awaitingFrame = false
    private var heading: Float = -0.85
    private var elevation: Float = 0.24
    private enum Display { case model(InstalledModelScene), region(NativeInstalledWorldSection) }

    init(showsRegion: Bool = false) {
        self.showsRegion = showsRegion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic installation screen") }

    deinit { job?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if showsRegion { world = NativeWorldRenderer() }
        canvas.colorPixelFormat = .bgra8Unorm
        canvas.depthStencilPixelFormat = .depth32Float
        if !showsRegion { canvas.clearColor = MTLClearColorMake(0.11, 0.13, 0.15, 1) }
        canvas.isPaused = true
        canvas.enableSetNeedsDisplay = true
        if !showsRegion { canvas.delegate = self }
        canvas.isAccessibilityElement = true
        canvas.accessibilityIdentifier = "\(identifier).render"
        canvas.accessibilityLabel = showsRegion ? "East Los Santos map section" : "Original model"
        canvas.accessibilityTraits = .image
        canvas.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(orbit(_:))))
        if showsRegion { canvas.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))) }

        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.accessibilityIdentifier = "\(identifier).status"
        status.text = showsRegion ? "Checking installed map section…" : "Checking installed model…"
        choose.setTitle("Select ISO", for: .normal)
        choose.accessibilityIdentifier = "\(identifier).choose"
        choose.isEnabled = false
        choose.addAction(UIAction { [weak self] _ in self?.showPicker() }, for: .touchUpInside)
        cancel.setTitle("Cancel import", for: .normal)
        cancel.isHidden = true
        cancel.addAction(UIAction { [weak self] _ in
            self?.job?.cancel()
            self?.cancel.isEnabled = false
            self?.status.text = "Cancelling import…"
        }, for: .touchUpInside)
        let close = UIButton(configuration: .plain())
        close.setTitle("Close", for: .normal)
        close.accessibilityIdentifier = "\(identifier).close"
        close.addAction(UIAction { [weak self] _ in
            self?.job?.cancel()
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [choose, cancel, close])
        buttons.spacing = 12
        let stack = UIStackView(arrangedSubviews: [status, canvas, buttons])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        ])
        loadModel(from: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.setNeedsDisplay()
    }

    private func showPicker() {
        guard job == nil, presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "iso") ?? .data], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first { loadModel(from: url) }
    }

    private func loadModel(from url: URL?) {
        guard job == nil else { return }
        let operation = NativeISOExtraction.Cancellation()
        job = operation
        choose.isEnabled = false
        cancel.isEnabled = true
        cancel.isHidden = url == nil
        if url != nil { status.text = "Opening disc image…" }
        let device = canvas.device
        let region = showsRegion
        Self.worker.async { [weak self, store] in
            let progress: (String) -> Void = { [weak self] text in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.job === operation, !operation.isCancelled else { return }
                    self.status.text = text
                }
            }
            let result = Result { () throws -> Display? in
                if region {
                    let installed: NativeISORegionInstallation.Region?
                    if let url { installed = try NativeISORegionInstallation.install(from: url, store: store, cancellation: operation, progress: progress) }
                    else { installed = try NativeISORegionInstallation.load(from: store) }
                    guard let installed else { return nil }
                    guard !operation.isCancelled else { throw NativeISOExtraction.Failure.cancelled }
                    guard let device else { throw NativeRenderWareModel.Failure.gpu("Metal is unavailable on this device") }
                    return .region(try NativeInstalledWorldSection(region: installed, device: device))
                }
                let asset: NativeISOModelInstallation.Asset
                if let url {
                    asset = try NativeISOModelInstallation.install(from: url, store: store, cancellation: operation, progress: progress)
                } else {
                    guard let saved = try NativeISOModelInstallation.load(from: store) else { return nil }
                    asset = saved
                }
                guard !operation.isCancelled else { throw NativeISOExtraction.Failure.cancelled }
                guard let device else { throw NativeRenderWareModel.Failure.gpu("Metal is unavailable on this device") }
                return .model(try InstalledModelScene(asset: asset, device: device))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.job === operation else { return }
                self.job = nil
                self.choose.isEnabled = true
                self.cancel.isHidden = true
                switch result {
                case .success(.model(let saved)):
                    self.scene = saved
                    self.awaitingFrame = true
                    self.status.text = "Rendering installed model…"
                    self.canvas.setNeedsDisplay()
                case .success(.region(let section)):
                    guard let world = self.world else { self.status.text = "The native world renderer could not start."; return }
                    self.status.text = "Rendering installed map section…"
                    world.showInstalledSection(section) { [weak self] result in
                        guard let self, self.job == nil else { return }
                        switch result {
                        case .success: self.status.text = section.summary; self.canvas.accessibilityLabel = section.summary
                        case .failure(let error): self.status.text = Self.describe(error)
                        }
                    }
                case .success(nil):
                    self.status.text = region ? "Select your original San Andreas PC ISO to install an East Los Santos map section."
                                             : "Select your original San Andreas PC ISO to install the plant model and its texture."
                case .failure(let error):
                    self.status.text = Self.describe(error)
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let rendering = error as? NativeRenderWareModel.Failure { return rendering.description }
        return error.localizedDescription
    }

    @objc private func orbit(_ sender: UIPanGestureRecognizer) {
        guard sender.state == .changed else { return }
        let delta = sender.translation(in: canvas)
        sender.setTranslation(.zero, in: canvas)
        if showsRegion {
            world?.orbitInstalledSection(horizontal: Float(delta.x) * 0.009, vertical: Float(delta.y) * 0.009)
            return
        }
        guard scene != nil else { return }
        heading -= Float(delta.x) * 0.009
        elevation = min(1.4, max(-1.4, elevation + Float(delta.y) * 0.009))
        canvas.setNeedsDisplay()
    }

    @objc private func zoom(_ sender: UIPinchGestureRecognizer) {
        guard sender.state == .changed else { return }
        world?.zoomInstalledSection(by: Float(sender.scale))
        sender.scale = 1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let scene, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        guard let buffer = scene.queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            status.text = "Metal could not start a frame."
            return
        }
        let aspect = Float(drawable.texture.width) / Float(drawable.texture.height)
        let viewProjection = scene.camera(aspect: aspect, heading: heading, elevation: elevation)
        do {
            for index in scene.drawOrder {
                try scene.model.encode(drawIndex: index, encoder: encoder, pipelines: scene.pipelines,
                                       viewProjection: viewProjection, modelTransform: matrix_identity_float4x4)
            }
        } catch {
            encoder.endEncoding()
            status.text = Self.describe(error)
            return
        }
        encoder.endEncoding()
        if awaitingFrame {
            awaitingFrame = false
            buffer.addCompletedHandler { [weak self] command in
                let failure = command.error?.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.scene === scene, self.job == nil else { return }
                    self.status.text = failure ?? scene.summary
                    if failure == nil { self.canvas.accessibilityLabel = scene.summary }
                }
            }
        }
        buffer.present(drawable)
        buffer.commit()
    }
}

private final class InstalledModelScene {
    let model: NativeRenderWareModel.Uploaded
    let pipelines: NativeRenderWareModel.Pipelines
    let queue: MTLCommandQueue
    let drawOrder: [Int]
    let summary: String
    private let center: SIMD3<Float>
    private let radius: Float

    init(asset: NativeISOModelInstallation.Asset, device: MTLDevice) throws {
        let plan = asset.plan
        guard !plan.textures.isEmpty, !plan.draws.isEmpty,
              !plan.diagnostics.contains(where: { if case .missingTexture = $0 { return true }; return false }) else {
            throw NativeRenderWareModel.Failure.malformed("the installed material has no matching original texture")
        }
        guard let library = device.makeDefaultLibrary(), let commands = device.makeCommandQueue() else {
            throw NativeRenderWareModel.Failure.gpu("the app shader library or command queue is unavailable")
        }
        queue = commands
        pipelines = try .init(device: device, library: library, color: .bgra8Unorm)
        model = try .init(plan: plan, device: device)
        let bound = try NativeRenderWareModel.Bounds(plan: plan)
        center = bound.center
        radius = bound.radius
        var opaque: [Int] = [], blended: [Int] = []
        for (index, draw) in plan.draws.enumerated() {
            let geometry = plan.geometries[plan.instances[draw.instance].geometry]
            if geometry.materials[geometry.parts[draw.part].material].usesBlending { blended.append(index) }
            else { opaque.append(index) }
        }
        drawOrder = opaque + blended
        let filename = URL(fileURLWithPath: asset.manifest.modelPath).lastPathComponent
        let dictionary = URL(fileURLWithPath: asset.manifest.texturePath).lastPathComponent
        let textures = plan.textures.map(\.name).joined(separator: ", ")
        summary = "Rendered \(filename) · \(dictionary) · \(textures)"
    }

    func camera(aspect: Float, heading: Float, elevation: Float) -> simd_float4x4 {
        let halfFov = Float.pi / 8
        let fit = atan(tan(halfFov) * min(1, aspect))
        let distance = radius * 1.05 / sin(fit)
        let direction = SIMD3(cos(heading) * cos(elevation), sin(heading) * cos(elevation), sin(elevation))
        let view = NativeWorldRenderer.lookAt(eye: center + direction * distance, target: center)
        return NativeWorldRenderer.perspective(aspect: aspect, verticalFov: 45,
                                               near: distance - radius * 1.1, far: distance + radius * 1.1) * view
    }
}
