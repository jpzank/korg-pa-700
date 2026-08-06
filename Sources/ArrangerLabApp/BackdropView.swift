import AppKit
import ArrangerLabCore
import SpriteKit
import SwiftUI

struct BackdropOutputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var bridge = BackdropSceneBridge()

    var body: some View {
        SpriteView(scene: bridge.scene, options: [.shouldCullNonVisibleNodes])
            .ignoresSafeArea()
            .background(Color(red: 0.018, green: 0.027, blue: 0.025))
            .overlay {
                BackdropWindowAccessor(
                    requestID: model.backdropWindowRequestID,
                    mode: model.backdropWindowMode,
                    screen: model.backdropScreen(for: model.selectedBackdropDisplayID)
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .onAppear {
                bridge.setReduceMotion(reduceMotion)
                bridge.update(model.backdropRenderState)
            }
            .onChange(of: reduceMotion) { _, value in
                bridge.setReduceMotion(value)
            }
            .onReceive(model.$backdropRenderState) { state in
                bridge.update(state)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                model.refreshBackdropDisplays()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(backdropAccessibilityLabel)
    }

    private var backdropAccessibilityLabel: String {
        if model.backdropRenderState.isBlackout { return "Backdrop em blackout" }
        guard let cue = model.backdropRenderState.cue else { return "Backdrop sem visual ativo" }
        return "Backdrop \(cue.palette.displayName), \(model.backdropStatus)"
    }
}

@MainActor
private final class BackdropSceneBridge: ObservableObject {
    let scene = BackdropScene()

    func update(_ state: BackdropRenderState) {
        scene.apply(state)
    }

    func setReduceMotion(_ enabled: Bool) {
        scene.reduceMotion = enabled
    }
}

@MainActor
private final class BackdropScene: SKScene {
    var reduceMotion = false

    private let inkTexture = BackdropScene.makeInkTexture()
    private var renderState = BackdropRenderState()
    private var knownStrokeIDs: Set<UUID> = []
    private var releasedStrokeIDs: Set<UUID> = []
    private var ambientIndex = 0
    private var lastAmbientTime: TimeInterval = 0

    override init(size: CGSize = CGSize(width: 1_920, height: 1_080)) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = BackdropVisualPalette.forPalette(.forestLight).background
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func apply(_ state: BackdropRenderState) {
        let previousPresetID = renderState.activePresetID
        let hadPerformancePaint = !renderState.strokes.isEmpty
        renderState = state
        guard !state.isBlackout else {
            knownStrokeIDs.removeAll()
            releasedStrokeIDs.removeAll()
            removeAllChildren()
            backgroundColor = BackdropVisualPalette.blackout
            return
        }

        if previousPresetID != state.activePresetID || (hadPerformancePaint && state.strokes.isEmpty) {
            knownStrokeIDs.removeAll()
            releasedStrokeIDs.removeAll()
            removeAllChildren()
        }

        let palette = BackdropVisualPalette.forPalette(state.cue?.palette ?? .forestLight)
        backgroundColor = state.cue == nil ? BackdropVisualPalette.idle : palette.background

        let retainedIDs = Set(state.strokes.map(\.id))
        knownStrokeIDs.formIntersection(retainedIDs)
        releasedStrokeIDs.formIntersection(retainedIDs)

        for stroke in state.strokes where !knownStrokeIDs.contains(stroke.id) {
            spawn(stroke, palette: palette)
            knownStrokeIDs.insert(stroke.id)
        }

        for stroke in state.strokes where stroke.releasedAtNanoseconds != nil {
            guard !releasedStrokeIDs.contains(stroke.id),
                  let node = childNode(withName: stroke.id.uuidString) else { continue }
            releasedStrokeIDs.insert(stroke.id)
            node.removeAction(forKey: "life")
            let releaseDuration = reduceMotion ? 0.35 : min(1.6, max(0.55, stroke.persistenceSeconds * 0.22))
            node.run(.sequence([
                .group([
                    .fadeOut(withDuration: releaseDuration),
                    .scale(to: 1.24, duration: releaseDuration)
                ]),
                .removeFromParent()
            ]), withKey: "release")
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard !renderState.isBlackout,
              let cue = renderState.cue,
              cue.isEnabled,
              cue.ambientMode != .quiet else { return }
        let interval: TimeInterval
        switch cue.ambientMode {
        case .quiet: return
        case .flowing: interval = reduceMotion ? 5.5 : 2.8
        case .breathing: interval = reduceMotion ? 6.5 : 3.8
        }
        guard currentTime - lastAmbientTime >= interval else { return }
        lastAmbientTime = currentTime
        spawnAmbient(cue: cue)
    }

    private func spawn(_ stroke: BackdropStroke, palette: BackdropVisualPalette) {
        guard size.width > 0, size.height > 0 else { return }
        let container = SKNode()
        container.name = stroke.id.uuidString
        container.position = CGPoint(
            x: size.width * (0.08 + stroke.normalizedX * 0.84),
            y: size.height * stroke.normalizedY
        )
        container.zPosition = stroke.kind == .chordBloom ? 1 : 2 + CGFloat(stroke.channel)
        let base = min(size.width, size.height) * stroke.radius * 2
        let color = palette.inks[stroke.pitchClass % palette.inks.count]
        let lobeCount = stroke.kind == .chordBloom ? 5 : 3

        for lobe in 0..<lobeCount {
            let phase = Double(Int(stroke.note) * 17 + Int(stroke.channel) * 31 + lobe * 53)
            let angle = phase.truncatingRemainder(dividingBy: 360) * .pi / 180
            let spread = base * (stroke.kind == .chordBloom ? 0.28 : 0.18)
            let sprite = SKSpriteNode(texture: inkTexture)
            sprite.color = color
            sprite.colorBlendFactor = 1
            sprite.blendMode = palette.blendMode
            sprite.alpha = 0
            sprite.size = CGSize(
                width: base * (0.78 + Double(lobe) * 0.11),
                height: base * (0.66 + Double((lobe + 1) % 3) * 0.14)
            )
            sprite.position = CGPoint(
                x: cos(angle) * spread,
                y: sin(angle) * spread * 0.72
            )
            sprite.zRotation = CGFloat(angle * 0.35)
            container.addChild(sprite)
            let targetAlpha = min(0.72, max(0.12, stroke.luminosity * (stroke.kind == .chordBloom ? 0.34 : 0.46)))
            sprite.run(.fadeAlpha(to: targetAlpha, duration: reduceMotion ? 0.05 : 0.18))
        }

        addChild(container)
        let lifetime = min(12, max(2.2, stroke.persistenceSeconds))
        let movement = reduceMotion ? CGVector.zero : driftVector(for: stroke, distance: base * 0.42)
        let expansion = stroke.kind == .chordBloom ? 1.85 : 1.58
        let life = SKAction.sequence([
            .group([
                .move(by: movement, duration: lifetime),
                .scale(to: expansion, duration: lifetime),
                .rotate(byAngle: reduceMotion ? 0 : 0.18, duration: lifetime)
            ]),
            .fadeOut(withDuration: reduceMotion ? 0.45 : 1.25),
            .removeFromParent()
        ])
        life.timingMode = .easeOut
        container.run(life, withKey: "life")
    }

    private func spawnAmbient(cue: BackdropCue) {
        let palette = BackdropVisualPalette.forPalette(cue.palette)
        ambientIndex = (ambientIndex + 1) % 24
        let phase = Double(ambientIndex) * 0.83
        let node = SKSpriteNode(texture: inkTexture)
        let colorIndex = (ambientIndex * 5) % palette.inks.count
        node.color = palette.inks[colorIndex]
        node.colorBlendFactor = 1
        node.blendMode = palette.blendMode
        let diameter = min(size.width, size.height) * (cue.ambientMode == .breathing ? 0.42 : 0.25)
        node.size = CGSize(width: diameter * 1.35, height: diameter)
        node.position = CGPoint(
            x: size.width * (0.16 + 0.68 * (sin(phase) * 0.5 + 0.5)),
            y: size.height * (0.24 + 0.52 * (cos(phase * 0.71) * 0.5 + 0.5))
        )
        node.alpha = 0
        node.zPosition = 0
        addChild(node)

        let opacity = 0.035 + cue.intensity * 0.055
        let lifetime = reduceMotion ? 8.5 : (cue.ambientMode == .breathing ? 7.2 : 5.8)
        let drift = reduceMotion ? CGVector.zero : CGVector(dx: cos(phase) * diameter * 0.32, dy: sin(phase) * diameter * 0.16)
        let action = SKAction.sequence([
            .fadeAlpha(to: opacity, duration: 1.1),
            .group([
                .move(by: drift, duration: lifetime),
                .scale(to: cue.ambientMode == .breathing ? 1.45 : 1.28, duration: lifetime)
            ]),
            .fadeOut(withDuration: 1.4),
            .removeFromParent()
        ])
        action.timingMode = .easeOut
        node.run(action)
    }

    private func driftVector(for stroke: BackdropStroke, distance: CGFloat) -> CGVector {
        let angle = Double(Int(stroke.note) * 29 + Int(stroke.channel) * 47)
            .truncatingRemainder(dividingBy: 360) * .pi / 180
        return CGVector(
            dx: cos(angle) * distance,
            dy: sin(angle) * distance * 0.55
        )
    }

    private static func makeInkTexture() -> SKTexture {
        let width = 256
        let height = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor(white: 1, alpha: 0.94).cgColor,
                NSColor(white: 1, alpha: 0.48).cgColor,
                NSColor(white: 1, alpha: 0).cgColor
            ] as CFArray,
            locations: [0, 0.38, 1]
        ) else {
            return SKTexture()
        }
        let center = CGPoint(x: width / 2, y: height / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(width) / 2,
            options: [.drawsAfterEndLocation]
        )
        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }
}

private struct BackdropVisualPalette {
    let background: NSColor
    let inks: [NSColor]
    let blendMode: SKBlendMode

    static let blackout = NSColor(red: 0.006, green: 0.009, blue: 0.009, alpha: 1)
    static let idle = NSColor(red: 0.018, green: 0.027, blue: 0.025, alpha: 1)

    static func forPalette(_ palette: BackdropPalette) -> BackdropVisualPalette {
        switch palette {
        case .forestLight:
            return .init(
                background: NSColor(red: 0.018, green: 0.036, blue: 0.032, alpha: 1),
                inks: [
                    NSColor(red: 0.08, green: 0.83, blue: 0.69, alpha: 1),
                    NSColor(red: 0.18, green: 0.62, blue: 0.95, alpha: 1),
                    NSColor(red: 0.62, green: 0.88, blue: 0.24, alpha: 1),
                    NSColor(red: 0.96, green: 0.58, blue: 0.20, alpha: 1),
                    NSColor(red: 0.92, green: 0.19, blue: 0.54, alpha: 1)
                ],
                blendMode: .add
            )
        case .deepLagoon:
            return .init(
                background: NSColor(red: 0.012, green: 0.025, blue: 0.052, alpha: 1),
                inks: [
                    NSColor(red: 0.06, green: 0.74, blue: 0.92, alpha: 1),
                    NSColor(red: 0.14, green: 0.42, blue: 0.94, alpha: 1),
                    NSColor(red: 0.18, green: 0.88, blue: 0.72, alpha: 1),
                    NSColor(red: 0.38, green: 0.30, blue: 0.94, alpha: 1)
                ],
                blendMode: .add
            )
        case .ember:
            return .init(
                background: NSColor(red: 0.052, green: 0.020, blue: 0.022, alpha: 1),
                inks: [
                    NSColor(red: 0.98, green: 0.30, blue: 0.20, alpha: 1),
                    NSColor(red: 0.98, green: 0.62, blue: 0.18, alpha: 1),
                    NSColor(red: 0.88, green: 0.16, blue: 0.48, alpha: 1),
                    NSColor(red: 0.74, green: 0.24, blue: 0.82, alpha: 1)
                ],
                blendMode: .add
            )
        case .orchid:
            return .init(
                background: NSColor(red: 0.034, green: 0.018, blue: 0.052, alpha: 1),
                inks: [
                    NSColor(red: 0.76, green: 0.26, blue: 0.94, alpha: 1),
                    NSColor(red: 0.96, green: 0.24, blue: 0.62, alpha: 1),
                    NSColor(red: 0.28, green: 0.46, blue: 0.98, alpha: 1),
                    NSColor(red: 0.36, green: 0.88, blue: 0.82, alpha: 1)
                ],
                blendMode: .add
            )
        case .paper:
            return .init(
                background: NSColor(red: 0.88, green: 0.91, blue: 0.89, alpha: 1),
                inks: [
                    NSColor(red: 0.06, green: 0.48, blue: 0.42, alpha: 1),
                    NSColor(red: 0.08, green: 0.34, blue: 0.72, alpha: 1),
                    NSColor(red: 0.78, green: 0.20, blue: 0.34, alpha: 1),
                    NSColor(red: 0.90, green: 0.48, blue: 0.08, alpha: 1),
                    NSColor(red: 0.42, green: 0.16, blue: 0.68, alpha: 1)
                ],
                blendMode: .alpha
            )
        }
    }
}

private struct BackdropWindowAccessor: NSViewRepresentable {
    let requestID: UUID
    let mode: BackdropWindowMode
    let screen: NSScreen?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView, coordinator: context.coordinator)
    }

    private func configure(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard coordinator.lastRequestID != requestID,
                  let window = view.window else { return }
            coordinator.lastRequestID = requestID
            window.backgroundColor = BackdropVisualPalette.idle
            window.isOpaque = true
            window.acceptsMouseMovedEvents = false

            switch mode {
            case .preview:
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                window.title = "Backdrop · Preview"
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.isMovable = true
                window.hasShadow = true
                window.level = .normal
                window.collectionBehavior = [.managed]
                let previewSize = CGSize(
                    width: max(720, min(960, NSScreen.main?.visibleFrame.width ?? 960)),
                    height: max(405, min(540, NSScreen.main?.visibleFrame.height ?? 540))
                )
                if let mainFrame = NSScreen.main?.visibleFrame {
                    window.setFrame(
                        CGRect(
                            x: mainFrame.midX - previewSize.width / 2,
                            y: mainFrame.midY - previewSize.height / 2,
                            width: previewSize.width,
                            height: previewSize.height
                        ),
                        display: true,
                        animate: false
                    )
                } else {
                    window.setContentSize(previewSize)
                    window.center()
                }
            case .fullscreen:
                guard let screen else { return }
                window.styleMask = [.borderless]
                window.titleVisibility = .hidden
                window.isMovable = false
                window.hasShadow = false
                window.level = .normal
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.setFrame(screen.frame, display: true, animate: false)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    final class Coordinator {
        var lastRequestID: UUID?
    }
}
