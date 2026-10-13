import ScreenshotKit
import SwiftUI
import UIKit

/// 首次匯入: welcome → photo permission → (restore from iCloud) → import with text recognition and classification.
struct OnboardingView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .permission: PermissionStep()
            case .restoreOffer: RestoreOfferStep()
            case .importing: ImportStep()
            default: WelcomeStep()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: store.phase)
    }
}

private struct StepKicker: View {
    let text: String
    var body: some View {
        Kicker(text, color: Palette.accent700, tracking: 0.1)
    }
}

private struct ContinueButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
            Spacer()
            Image(systemName: "arrow.right").font(.system(size: 17, weight: .medium))
        }
        .buttonStyle(ClassicalButtonStyle(kind: .primary, fullWidth: true, fontSize: 16, minHeight: 50))
    }
}

private struct WelcomeStep: View {
    @Environment(LibraryStore.self) private var store

    private struct Feature: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    private let features = [
        Feature(id: "01", title: "資料夾與標籤", detail: "每張截圖放進一個資料夾，再加上多個標籤。"),
        Feature(id: "02", title: "複製圖中文字", detail: "一鍵複製全部，或在圖上點選需要的段落。"),
        Feature(id: "03", title: "自動分類", detail: "依截圖內容自動放進資料夾，隨時可以改。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepKicker(text: "截圖整理")
            Text("把相簿裡的截圖，整理成找得到的資料。")
                .font(Typeface.head(40))
                .lineSpacing(2)
                .padding(.top, 16)
            Hairline().padding(.top, 28)
            ForEach(features) { feature in
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(feature.id)
                            .font(Typeface.head(20))
                            .monospacedDigit()
                            .foregroundStyle(Palette.accent)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(Typeface.body(16, .semibold))
                            Text(feature.detail).font(Typeface.body(14)).foregroundStyle(Palette.neutral700)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 16)
                    Hairline()
                }
            }
            Spacer(minLength: 24)
            ContinueButton(title: "開始整理") { store.goToPermission() }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").font(.system(size: 12))
                Text("截圖與文字辨識都在裝置上處理，不會上傳。")
            }
            .font(Typeface.body(12))
            .foregroundStyle(Palette.neutral700)
            .padding(.top, 10)
        }
    }
}

private struct PermissionStep: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepKicker(text: "步驟 1 / 2")
            Text("需要讀取你的照片")
                .font(Typeface.head(32))
                .padding(.top, 12)
            Text("只會讀取「螢幕截圖」相簿。原始照片不會被移動或修改，資料夾與標籤只存在這個 App 裡。")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.neutral700)
                .lineSpacing(3)
                .padding(.top, 12)

            if store.permissionDenied {
                Text("沒有照片權限就無法匯入截圖。請到「設定」允許「截圖整理」取用照片。")
                    .font(Typeface.body(14))
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.accent, lineWidth: 1))
                    .padding(.top, 24)
            }

            Spacer()

            if store.permissionDenied {
                ContinueButton(title: "前往設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                ContinueButton(title: "允許取用照片") { ask() }
                    .disabled(asking)
            }
        }
        // The system prompt appears as soon as this step opens, as in the design.
        .task { ask() }
    }

    private func ask() {
        guard !asking else { return }
        asking = true
        Task {
            await store.requestAccess()
            asking = false
        }
    }
}

/// Shown only when iCloud holds a backup; answering it starts the import.
private struct RestoreOfferStep: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let isRestoring = store.backup.activity == .restoring
        VStack(alignment: .leading, spacing: 0) {
            StepKicker(text: "步驟 1 / 2")
            Text("找到 iCloud 備份")
                .font(Typeface.head(32))
                .padding(.top, 12)
            if let offer = store.restoreOffer {
                Text("\(offer.createdAt.formatted(date: .long, time: .shortened)) 備份，共 \(offer.shotCount) 張已整理的截圖。")
                    .font(Typeface.body(15))
                    .padding(.top, 12)
            }
            Text("還原後，資料夾、標籤與分類會回到備份時的樣子；之後新增的截圖會照常自動分類。")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.neutral700)
                .lineSpacing(3)
                .padding(.top, 8)

            Spacer()

            Button("從頭開始，不還原") { store.declineRestoreOffer() }
                .buttonStyle(.ghost)
                .disabled(isRestoring)
                .padding(.bottom, 6)
            ContinueButton(title: isRestoring ? "還原中…" : "還原備份") {
                Task { await store.acceptRestoreOffer() }
            }
            .disabled(isRestoring)
        }
    }
}

private struct ImportStep: View {
    @Environment(LibraryStore.self) private var store

    private let steps = ["掃描「螢幕截圖」相簿", "辨識圖中文字", "自動分類"]

    var body: some View {
        let p = store.importProgress
        let done = p.step >= 3
        VStack(alignment: .leading, spacing: 0) {
            StepKicker(text: "步驟 2 / 2")
            Text(done ? "匯入完成" : "正在匯入截圖")
                .font(Typeface.head(32))
                .padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(p.found)")
                    .font(Typeface.head(72))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("張截圖").font(Typeface.body(16))
            }
            .padding(.top, 28)

            if done {
                let summary = store.library.classificationSummary
                Text("已分類 \(summary.classified) 張，未分類 \(summary.unsorted) 張")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.neutral700)
                    .padding(.top, 4)
            }

            GeometryReader { geo in
                Rectangle().fill(Palette.neutral300)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.accent).frame(width: geo.size.width * p.fraction)
                    }
            }
            .frame(height: 4)
            .padding(.top, 20)
            .animation(.linear(duration: 0.2), value: p.fraction)

            VStack(spacing: 0) {
                Hairline()
                ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                    StepRow(label: index == 1 && p.step == 1 && p.total > 0 ? "\(label)（\(p.recognized) / \(p.total)）" : label,
                            done: p.step > index, active: p.step == index)
                }
            }
            .padding(.top, 24)

            Spacer()

            if !done && p.step == 1 && p.total > 20 {
                Button("先進入相簿，在背景繼續辨識") { store.finishImport() }
                    .buttonStyle(.ghost)
                    .padding(.bottom, 6)
            }
            ContinueButton(title: "進入相簿") { store.finishImport() }
                .disabled(!done)
        }
        .animation(.easeOut(duration: 0.2), value: p)
    }
}

private struct StepRow: View {
    let label: String
    let done: Bool
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if active && !done {
                        ProgressView().controlSize(.small).tint(Palette.text)
                    } else {
                        Image(systemName: done ? "checkmark.circle" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(done ? Palette.accent : Palette.neutral400)
                    }
                }
                .frame(width: 20)
                Text(label)
                    .font(Typeface.body(15, active ? .semibold : .regular))
                    .foregroundStyle(done || active ? Palette.text : Palette.neutral500)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            Hairline()
        }
    }
}
