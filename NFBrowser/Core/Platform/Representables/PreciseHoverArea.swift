import AppKit
import SwiftUI

struct PreciseHoverArea: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> PreciseHoverNSView {
        let view = PreciseHoverNSView()
        view.onHoverChange = { hovering in
            if self.isHovered != hovering {
                self.isHovered = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: PreciseHoverNSView, context: Context) {
        nsView.onHoverChange = { hovering in
            if self.isHovered != hovering {
                self.isHovered = hovering
            }
        }
    }
}

final class PreciseHoverNSView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var currentHover = false
    private var tabCloseObserver: NSObjectProtocol?
    private var checkWorkItems: [DispatchWorkItem] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupNotification()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNotification()
    }

    deinit {
        if let observer = tabCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cancelScheduledChecks()
    }

    private func setupNotification() {
        tabCloseObserver = NotificationCenter.default.addObserver(
            forName: .tabClosedOrChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSettlingChecks()
        }
    }

    private func cancelScheduledChecks() {
        checkWorkItems.forEach { $0.cancel() }
        checkWorkItems.removeAll()
    }

    func scheduleSettlingChecks() {
        cancelScheduledChecks()
        checkHover()

        // As tabs animate and slide into the position of closed tabs,
        // perform rapid checks across the settling window so hover is acquired instantly
        // even if the user's mouse remains completely still.
        let delays = [0.03, 0.07, 0.12, 0.18, 0.25, 0.35]
        for delay in delays {
            let item = DispatchWorkItem { [weak self] in
                self?.checkHover()
            }
            checkWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            checkHover()
        } else {
            setHover(false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        checkHover()
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
    }

    override func mouseMoved(with event: NSEvent) {
        checkHover()
    }

    func checkHover() {
        guard let window = self.window, !isHiddenOrHasHiddenAncestor else {
            setHover(false)
            return
        }
        let mouseScreen = NSEvent.mouseLocation
        guard window.frame.contains(mouseScreen) else {
            setHover(false)
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let rectInWindow = convert(bounds, to: nil)
        let inside = rectInWindow.contains(mouseInWindow)
        setHover(inside)
    }

    private func setHover(_ inside: Bool) {
        guard currentHover != inside else { return }
        currentHover = inside
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onHoverChange?(inside)
        }
    }
}
