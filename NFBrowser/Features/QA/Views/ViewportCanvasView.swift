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

                // Web content container
                if isSimulated, let dims = qaState.effectiveDimensions {
                    let availableHeight = max(geometry.size.height - 110, 200)
                    let availableWidth = max(geometry.size.width - 60, 200)
                    let scaleH = dims.height > availableHeight ? availableHeight / dims.height : 1.0
                    let scaleW = dims.width > availableWidth ? availableWidth / dims.width : 1.0
                    let effectiveScale = min(scaleH, scaleW, 1.0) * qaState.zoomScale

                    VStack(spacing: 8) {
                        Spacer(minLength: 58)

                        // Device Bezel Frame
                        VStack(spacing: 0) {
                            // Header Bar
                            HStack(spacing: 8) {
                                Circle().fill(Color.white.opacity(0.2)).frame(width: 8, height: 8)
                                Circle().fill(Color.white.opacity(0.12)).frame(width: 8, height: 8)
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)

                                Spacer()

                                Text(qaState.activePreset.shortName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))

                                Text("\(Int(dims.width)) × \(Int(dims.height))")
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
                            .frame(width: dims.width, height: 24)
                            .background(Color(red: 0.14, green: 0.14, blue: 0.16))

                            // Actual web content
                            content()
                                .frame(width: dims.width, height: dims.height)
                        }
                        .frame(width: dims.width)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .overlay(alignment: .trailing) {
                            // Right Drag Handle (Width resize)
                            rightDragHandle(dims: dims, maxW: geometry.size.width)
                                .offset(x: 14)
                        }
                        .overlay(alignment: .bottom) {
                            // Bottom Drag Handle (Height resize)
                            bottomDragHandle(dims: dims, maxH: geometry.size.height)
                                .offset(y: 14)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // Corner Drag Handle (Both resize)
                            cornerDragHandle(dims: dims, maxW: geometry.size.width, maxH: geometry.size.height)
                                .offset(x: 12, y: 12)
                        }
                        .scaleEffect(effectiveScale)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dims)

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Full Window live browsing
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

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

    private func rightDragHandle(dims: CGSize, maxW: CGFloat) -> some View {
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
                    let newW = max(280, min(maxW - 40, (dragStartWidth ?? dims.width) + val.translation.width))
                    qaState.customWidth = round(newW)
                    qaState.customHeight = dims.height
                    qaState.activePreset = .custom
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }

    private func bottomDragHandle(dims: CGSize, maxH: CGFloat) -> some View {
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
                    let newH = max(200, min(maxH - 120, (dragStartHeight ?? dims.height) + val.translation.height))
                    qaState.customWidth = dims.width
                    qaState.customHeight = round(newH)
                    qaState.activePreset = .custom
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
    }

    private func cornerDragHandle(dims: CGSize, maxW: CGFloat, maxH: CGFloat) -> some View {
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
                    let newW = max(280, min(maxW - 40, (dragStartWidth ?? dims.width) + val.translation.width))
                    let newH = max(200, min(maxH - 120, (dragStartHeight ?? dims.height) + val.translation.height))
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
