import SwiftUI
import os

struct LibraryPagerView: View {
    @Binding var tabSelection: AppTab
    @State private var page: Page = .library
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var dragStartLocked = false
    @State private var isDragging = false
    @State private var didLogSize = false
    private let layoutLogger = Logger(subsystem: "NoteLab", category: "Layout")

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let showWhiteboard = page == .whiteboard || isDragging

            ZStack {
                LibraryView(tabSelection: $tabSelection)
                    .frame(width: width, height: proxy.size.height)
                    .offset(x: -page.rawValue * width + dragOffset)
                    .allowsHitTesting(!isDragging)

                if showWhiteboard {
                    WhiteboardView(onClose: { page = .library })
                        .frame(width: width, height: proxy.size.height)
                        .offset(x: width - page.rawValue * width + dragOffset)
                        .allowsHitTesting(!isDragging)
                }
            }
            .clipped()
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: page)
            .gesture(dragGesture(width: width))
            .onAppear {
                #if DEBUG
                if !didLogSize, proxy.size.width > 0, proxy.size.height > 0 {
                    layoutLogger.info("LibraryPager size: \(proxy.size.width, privacy: .public)x\(proxy.size.height, privacy: .public)")
                    didLogSize = true
                }
                #endif
            }
            .onChange(of: proxy.size) { _, newSize in
                #if DEBUG
                if !didLogSize, newSize.width > 0, newSize.height > 0 {
                    layoutLogger.info("LibraryPager size: \(newSize.width, privacy: .public)x\(newSize.height, privacy: .public)")
                    didLogSize = true
                }
                #endif
            }
            .onChange(of: page) { _, newValue in
                #if DEBUG
                layoutLogger.info("LibraryPager page: \(String(describing: newValue))")
                #endif
            }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !dragStartLocked {
                    if abs(dx) > 36 && abs(dx) > abs(dy) * 1.2 {
                        isHorizontalDrag = true
                        dragStartLocked = true
                        isDragging = true
                    } else if abs(dy) > 20 && abs(dy) > abs(dx) * 1.2 {
                        isHorizontalDrag = false
                        dragStartLocked = true
                    }
                }

                guard isHorizontalDrag else { return }

                let target = dx
                if page == .library {
                    dragOffset = max(min(0, target), -width)
                } else {
                    dragOffset = max(min(width, target), 0)
                }
            }
            .onEnded { value in
                defer {
                    dragOffset = 0
                    dragStartLocked = false
                    isDragging = false
                }

                guard isHorizontalDrag else {
                    isHorizontalDrag = false
                    return
                }

                let dx = value.translation.width
                let threshold = width * 0.25

                if page == .library {
                    if dx < -threshold {
                        page = .whiteboard
                    }
                } else {
                    if dx > threshold {
                        page = .library
                    }
                }

                isHorizontalDrag = false
            }
    }
}

private enum Page: CGFloat {
    case library = 0
    case whiteboard = 1
}
