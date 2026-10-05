import AppKit
import SwiftUI

struct ViewportCanvasView<Content: View>: View {
    @ObservedObject var tab: Tab
    @ObservedObject var qaState: QAModeState
    let onScreenshot: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragStartWidth: CGFloat?
    @State private var dragStartHeight: CGFloat?

    private var isSimulated: Bool {
        (qaState.isQAActive || qaState.activePreset != .default) && qaState.effectiveDimensions != nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if isSimulated {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                        .ignoresSafeArea()
                }

                let dims = qaState.effectiveDimensions
                let availableHeight = max(geometry.size.height - 110, 200)
                let availableWidth = max(geometry.size.width - 60, 200)
                let targetH = dims?.height ?? geometry.size.height
                let targetW = dims?.width ?? geometry.size.width
                let scaleH = targetH > availableHeight ? availableHeight / targetH : 1.0
                let scaleW = targetW > availableWidth ? availableWidth / targetW : 1.0
                let effectiveScale = isSimulated ? min(scaleH, scaleW, 1.0) * qaState.zoomScale : 1.0

                VStack(spacing: 0) {
                    if isSimulated {
                        Spacer(minLength: 58)
                    }

                    // Device Bezel Frame
                    VStack(spacing: 0) {
                        if isSimulated, let currentDims = dims {
                            // Header Bar
                            HStack(spacing: 8) {
                                Circle().fill(Color.white.opacity(0.2)).frame(width: 8, height: 8)
                                Circle().fill(Color.white.opacity(0.12)).frame(width: 8, height: 8)
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)

                                Spacer()

                                Text(qaState.activePreset.shortName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))

                                Text("\(Int(currentDims.width)) × \(Int(currentDims.height))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))

                                Spacer()

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        qaState.toggleOrientation()
                                    }
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(qaState.isLandscape ? Color.accentColor : .white.opacity(0.6))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Rotate device orientation")
                            }
                            .padding(.horizontal, 12)
                            .frame(width: currentDims.width, height: 24)
                            .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                        }

                        // Persistent Web View
                        content()
                            .frame(
                                width: isSimulated ? dims?.width : nil,
                                height: isSimulated ? dims?.height : nil
                            )
                            .frame(
                                maxWidth: isSimulated ? dims?.width : .infinity,
                                maxHeight: isSimulated ? dims?.height : .infinity
                            )
                    }
                    .frame(width: isSimulated ? dims?.width : nil)
                    .clipShape(RoundedRectangle(cornerRadius: isSimulated ? 14 : 0, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isSimulated ? 14 : 0, style: .continuous)
                            .stroke(isSimulated ? Color.white.opacity(0.18) : Color.clear, lineWidth: isSimulated ? 1.5 : 0)
                    )
                    .shadow(color: isSimulated ? .black.opacity(0.45) : .clear, radius: isSimulated ? 24 : 0, y: isSimulated ? 12 : 0)
                    .overlay(alignment: .trailing) {
                        if isSimulated, let currentDims = dims {
                            rightDragHandle(dims: currentDims, maxW: geometry.size.width, scale: effectiveScale)
                                .offset(x: 14)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if isSimulated, let currentDims = dims {
                            bottomDragHandle(dims: currentDims, maxH: geometry.size.height, scale: effectiveScale)
                                .offset(y: 14)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSimulated, let currentDims = dims {
                            cornerDragHandle(dims: currentDims, maxW: geometry.size.width, maxH: geometry.size.height, scale: effectiveScale)
                                .offset(x: 12, y: 12)
                        }
                    }
                    .scaleEffect(isSimulated ? effectiveScale : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dims)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSimulated)

                    if isSimulated {
                        Spacer(minLength: 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Control Strip docked at top (when QA is active)
                if qaState.isQAActive || qaState.activePreset != .default {
                    QAControlStrip(qaState: qaState, tab: tab, onScreenshot: onScreenshot)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
        }
    }

    private func rightDragHandle(dims: CGSize, maxW: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 5, height: 48)
        }
        .frame(width: 20, height: 60)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { val in
                    if dragStartWidth == nil { dragStartWidth = dims.width }
                    let deltaW = val.translation.width / max(scale, 0.2)
                    let newW = max(280, min(maxW - 40, (dragStartWidth ?? dims.width) + deltaW))
                    qaState.customWidth = round(newW)
                    qaState.customHeight = dims.height
                    qaState.activePreset = .custom
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }

    private func bottomDragHandle(dims: CGSize, maxH: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 48, height: 5)
        }
        .frame(width: 60, height: 20)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { val in
                    if dragStartHeight == nil { dragStartHeight = dims.height }
                    let deltaH = val.translation.height / max(scale, 0.2)
                    let newH = max(200, min(maxH - 120, (dragStartHeight ?? dims.height) + deltaH))
                    qaState.customWidth = dims.width
                    qaState.customHeight = round(newH)
                    qaState.activePreset = .custom
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
    }

    private func cornerDragHandle(dims: CGSize, maxW: CGFloat, maxH: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 10, height: 10)
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { val in
                    if dragStartWidth == nil {
                        dragStartWidth = dims.width
                        dragStartHeight = dims.height
                    }
                    let deltaW = val.translation.width / max(scale, 0.2)
                    let deltaH = val.translation.height / max(scale, 0.2)
                    let newW = max(280, min(maxW - 40, (dragStartWidth ?? dims.width) + deltaW))
                    let newH = max(200, min(maxH - 120, (dragStartHeight ?? dims.height) + deltaH))
                    qaState.customWidth = round(newW)
                    qaState.customHeight = round(newH)
                    qaState.activePreset = .custom
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    dragStartHeight = nil
                }
        )
    }
}
