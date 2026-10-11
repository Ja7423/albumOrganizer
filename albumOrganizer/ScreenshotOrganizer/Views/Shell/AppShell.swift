import ScreenshotKit
import SwiftUI
import UIKit

/// Tabs, the batch-selection bar, the sliding detail page, sheets and dialogs.
struct AppShell: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch ui.tab {
                    case .all:
                        ShotGridScreen(route: nil)
                    case .folders:
                        NavigationStack(path: $ui.folderPath) {
                            FoldersScreen()
                                .navigationDestination(for: UIState.Route.self) { ShotGridScreen(route: $0) }
                        }
                    case .tags:
                        NavigationStack(path: $ui.tagPath) {
                            TagsScreen()
                                .navigationDestination(for: UIState.Route.self) { ShotGridScreen(route: $0) }
                        }
                    case .search:
                        SearchScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if ui.selecting {
                    BatchBar()
                } else {
                    TabBar()
                }
            }
            .background(Palette.bg)

            if ui.detail != nil {
                ShotDetailScreen()
                    .transition(.move(edge: .trailing))
                    .zIndex(20)
            }

            SheetHost()
                .zIndex(30)

            if let dialog = ui.dialog {
                NameDialog(kind: dialog)
                    .transition(.opacity)
                    .zIndex(45)
            }
        }
        .animation(.easeOut(duration: 0.2), value: ui.dialog)
    }
}

// MARK: - Tab bar

/// A floating capsule of centered icon-over-label tabs; a soft pill slides under the active one.
struct TabBar: View {
    @Environment(UIState.self) private var ui
    @Namespace private var pill

    private let items: [(UIState.Tab, String, String)] = [
        (.all, "截圖", "photo.on.rectangle"),
        (.folders, "資料夾", "folder"),
        (.tags, "標籤", "tag"),
        (.search, "搜尋", "magnifyingglass"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                let on = ui.tab == item.0
                Button { ui.selectTab(item.0) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.2).font(.system(size: 18, weight: on ? .semibold : .regular)).frame(height: 22)
                        Text(item.1).font(Typeface.body(11, on ? .semibold : .regular)).tracking(0.22)
                    }
                    .foregroundStyle(on ? Palette.accent700 : Palette.neutral500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            Capsule().fill(Palette.neutral200.opacity(0.6)).matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(height: 60)
        .background(Capsule().fill(Palette.neutral100).shadowMD())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: ui.tab)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Palette.bg.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Batch bar

struct BatchBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let none = ui.selection.isEmpty
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 4) {
                Button { ui.present(.move, for: .batch) } label: {
                    Image(systemName: "folder").font(.system(size: 15))
                    Text("移到資料夾")
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary, fullWidth: true, alignment: .leading))

                Button { ui.present(.tags, for: .batch) } label: {
                    Image(systemName: "tag").font(.system(size: 15))
                    Text("標籤")
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary, fullWidth: true, alignment: .leading))

                Button {
                    let ids = Array(ui.selection)
                    store.mutate { $0.hide(ids) }
                    ui.endSelecting()
                    ui.showToast("已從 App 移除 \(ids.count) 張（相簿原檔保留）")
                } label: {
                    Image(systemName: "trash").font(.system(size: 15))
                }
                .buttonStyle(IconButtonStyle(kind: .secondary, size: 36, tint: Palette.text))
                .accessibilityLabel("移除")
            }
            .disabled(none)
            .padding(8)
        }
        .background(Palette.bg.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack {
            Spacer()
            if let toast = ui.toast {
                Text(toast)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.bg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.text).shadowLG())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Swipe back with a hidden navigation bar

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
