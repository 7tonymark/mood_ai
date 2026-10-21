import SwiftUI
import UIKit

/// Full-screen live camera. No library button, by design: photos are taken on the spot.
struct CameraView: View {
    var onUse: (CapturedPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraController()
    @State private var captured: CapturedPhoto?
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let captured, let image = UIImage(data: captured.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let error = camera.error {
                VStack(spacing: 18) {
                    Text(error)
                        .font(Arcade.font(14))
                        .foregroundStyle(Arcade.red)
                    if error == "CAMERA ACCESS DENIED" {
                        Button("OPEN SETTINGS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.arcade(Arcade.cyan))
                        .padding(.horizontal, 40)
                    }
                }
            } else {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            }
            if flash {
                Color.white.ignoresSafeArea()
            }
            controls
        }
        .overlay(Scanlines())
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Text("X")
                        .font(Arcade.font(18))
                        .foregroundStyle(Arcade.red)
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close camera")
                Spacer()
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Arcade.red)
                        .frame(width: 10, height: 10)
                        .blinking(captured == nil)
                    Text(captured == nil ? "LIVE" : "SNAPPED")
                        .font(Arcade.font(10))
                        .foregroundStyle(Arcade.ink)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
            }
            .padding(.horizontal, 12)

            Spacer()

            Text("NO CAMERA ROLL. ONLY WHAT'S IN FRONT OF YOU.")
                .font(Arcade.font(7))
                .foregroundStyle(Arcade.cyan)
                .padding(6)
                .background(Color.black.opacity(0.6))

            if captured == nil {
                HStack(alignment: .center) {
                    Spacer()
                        .frame(maxWidth: .infinity)
                    shutter
                    Button("FLIP") { camera.flip() }
                        .buttonStyle(.arcade(Arcade.cyan, filled: false, size: 9))
                        .frame(width: 80)
                        .frame(maxWidth: .infinity)
                        .disabled(!camera.isReady)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            } else {
                HStack(spacing: 12) {
                    Button("RETAKE") { captured = nil }
                        .buttonStyle(.arcade(Arcade.red, filled: false, size: 11))
                    Button("USE PHOTO") {
                        if let captured { onUse(captured) }
                        dismiss()
                    }
                    .buttonStyle(.arcade(Arcade.green, size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var shutter: some View {
        Button {
            Task {
                flash = true
                Haptics.tick()
                let photo = await camera.capture()
                withAnimation(.easeOut(duration: 0.2)) { flash = false }
                captured = photo
            }
        } label: {
            ZStack {
                PixelRect(step: 8)
                    .strokeBorder(Arcade.ink, lineWidth: 5)
                    .frame(width: 84, height: 84)
                PixelRect(step: 6)
                    .fill(camera.isCapturing ? Arcade.dim : Arcade.magenta)
                    .frame(width: 62, height: 62)
                    .neon(Arcade.magenta, radius: 6)
            }
        }
        .disabled(!camera.isReady || camera.isCapturing)
        .accessibilityLabel("Take photo")
    }
}
