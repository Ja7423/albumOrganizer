import SwiftUI

@main
struct ScreenshotOrganizerApp: App {
    @State private var store = LibraryStore()
    @State private var ui = UIState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(ui)
                .preferredColorScheme(.light)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.saveNow()
                store.backUp()
            case .active:
                store.resumeProcessing()
                if store.phase == .app { store.syncWithPhotos() }
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            if store.phase == .app {
                AppShell()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
            ToastView()
                .zIndex(50)
        }
        .foregroundStyle(Palette.text)
        .font(Typeface.body(15))
        .animation(.easeInOut(duration: 0.25), value: store.phase)
    }
}
