import SwiftUI
import UIKit

struct ComposePostView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: CapturedPhoto?
    @State private var showCamera = false
    @FocusState private var editing: Bool

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil
    }

    var body: some View {
        ArcadeScreen(title: "NEW POST", onClose: { dismiss() }) {
            ScrollView {
                VStack(spacing: 18) {
                    photoSection
                    textSection
                    Text("ONLY YOUR \(model.friends.count) FRIENDS CAN DECRYPT THIS.")
                        .font(Arcade.font(7))
                        .foregroundStyle(Arcade.dim)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 5)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            Button("POST") {
                model.post(text: text, photo: photo)
                Haptics.success()
                dismiss()
            }
            .buttonStyle(.arcade(Arcade.green, size: 14))
            .disabled(!canPost)
            .padding(.bottom, 6)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { photo = $0 }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if let photo, let image = UIImage(data: photo.jpeg) {
            VStack(spacing: 10) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(PixelRect())
                    .padding(6)
                    .pixelPanel(Arcade.magenta, fill: .black)
                HStack(spacing: 12) {
                    Button("RETAKE") { showCamera = true }
                        .buttonStyle(.arcade(Arcade.cyan, filled: false, size: 9))
                    Button("REMOVE") { self.photo = nil }
                        .buttonStyle(.arcade(Arcade.red, filled: false, size: 9))
                }
            }
        } else {
            Button { showCamera = true } label: {
                VStack(spacing: 14) {
                    Text("SNAP A PHOTO")
                        .font(Arcade.font(14))
                        .foregroundStyle(Arcade.magenta)
                        .neon(Arcade.magenta, radius: 4)
                    Text("LIVE CAMERA ONLY")
                        .font(Arcade.font(8))
                        .foregroundStyle(Arcade.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .overlay(
                    PixelRect()
                        .strokeBorder(Arcade.magenta, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take a photo with the camera")
        }
    }

    private var textSection: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $text)
                .font(Arcade.body(16))
                .foregroundStyle(Arcade.ink)
                .scrollContentBackground(.hidden)
                .focused($editing)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What's going on?")
                            .font(Arcade.body(16))
                            .foregroundStyle(Arcade.dim)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(10)
                .pixelPanel(Arcade.cyan)
                .onChange(of: text) {
                    if text.count > AppModel.maxPostLength {
                        text = String(text.prefix(AppModel.maxPostLength))
                    }
                }
            Text("\(text.count)/\(AppModel.maxPostLength)")
                .font(Arcade.font(7))
                .foregroundStyle(Arcade.dim)
        }
    }
}
