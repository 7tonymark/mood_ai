import SwiftUI
import UIKit

/// An end-to-end encrypted photo: fetched, decrypted and cached the first time it's shown.
struct PhotoView: View {
    var ref: AttachmentRef

    @Environment(AppModel.self) private var model
    @State private var image: UIImage?
    @State private var failed = false

    private var aspectRatio: CGFloat {
        min(max(CGFloat(ref.width) / CGFloat(max(ref.height, 1)), 0.5), 2)
    }

    var body: some View {
        Color.black
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Text("PHOTO LOST")
                        .font(Arcade.font(9))
                        .foregroundStyle(Arcade.red)
                } else {
                    Text("DECRYPTING...")
                        .font(Arcade.font(8))
                        .foregroundStyle(Arcade.cyan)
                        .blinking()
                }
            }
            .clipShape(PixelRect())
            .accessibilityLabel("Photo")
            .task(id: ref.recordName) {
                if let data = await model.photo(ref), let decoded = UIImage(data: data) {
                    image = decoded
                } else {
                    failed = true
                }
            }
    }
}

/// Full screen, tap anywhere to close.
struct PhotoViewer: View {
    var ref: AttachmentRef
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PhotoView(ref: ref)
                .padding(8)
        }
        .overlay(Scanlines())
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes the photo")
    }
}
