import SwiftUI
import AppKit

/// 波形上のマウス操作をまとめて受ける透明ビュー。
/// SwiftUI のジェスチャではスクロールホイール/ピンチ/ホバーを扱えないため AppKit で実装する。
struct WaveformInteractionView: NSViewRepresentable {
    var onClick: (CGFloat) -> Void
    /// ドラッグ中の範囲 (x0 <= x1) を都度通知
    var onDragSelect: (CGFloat, CGFloat) -> Void
    /// 範囲選択ドラッグの確定(マウスアップ)
    var onDragEnd: () -> Void
    /// 横スクロール量(ピクセル)
    var onScroll: (CGFloat) -> Void
    /// ズーム倍率(表示範囲長に掛ける係数)とアンカーの x 座標
    var onZoom: (Double, CGFloat) -> Void
    /// ホバー位置(ビュー座標、離れたら nil)
    var onHover: (CGPoint?) -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: InteractionNSView) {
        view.onClick = onClick
        view.onDragSelect = onDragSelect
        view.onDragEnd = onDragEnd
        view.onScroll = onScroll
        view.onZoom = onZoom
        view.onHover = onHover
    }
}

final class InteractionNSView: NSView {
    var onClick: ((CGFloat) -> Void)?
    var onDragSelect: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onZoom: ((Double, CGFloat) -> Void)?
    var onHover: ((CGPoint?) -> Void)?

    private var downPoint: CGPoint?
    private var isDragging = false

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !isDragging && abs(p.x - downPoint.x) > 3 {
            isDragging = true
        }
        if isDragging {
            onDragSelect?(min(downPoint.x, p.x), max(downPoint.x, p.x))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnd?()
        } else if let downPoint {
            onClick?(downPoint.x)
        }
        downPoint = nil
        isDragging = false
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌥/⌘ + スクロールはズーム、それ以外はパン
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            let anchor = convert(event.locationInWindow, from: nil).x
            let factor = pow(0.99, event.scrollingDeltaY)
            onZoom?(factor, anchor)
        } else {
            var dx = event.scrollingDeltaX
            // マウスホイール(縦のみ)でも横パンできるようにする
            if dx == 0 && !event.hasPreciseScrollingDeltas {
                dx = event.scrollingDeltaY
            }
            if dx != 0 { onScroll?(dx) }
        }
    }

    override func magnify(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil).x
        // magnification > 0 = ピンチアウト = ズームイン(表示範囲を縮める)
        let factor = 1.0 / max(0.2, 1.0 + event.magnification)
        onZoom?(factor, anchor)
    }
}
