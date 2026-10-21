import SwiftUI

/// First-launch "NEW PLAYER" screen, also used to edit your player later.
struct ProfileSetupView: View {
    enum Mode {
        case create, edit
    }

    let mode: Mode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: PlayerColor = .cyan
    @State private var avatar = PixelAvatar.random()
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ArcadeScreen(
            title: mode == .create ? nil : "EDIT PLAYER",
            onClose: mode == .edit ? { dismiss() } : nil
        ) {
            ScrollView {
                VStack(spacing: 26) {
                    if mode == .create {
                        ArcadeLogo()
                    }
                    nameSection
                    colorSection
                    avatarSection
                }
                .padding(.vertical, 8)
                .padding(.trailing, 5)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            Button(mode == .create ? "PRESS START" : "SAVE", action: save)
                .buttonStyle(.arcade(Arcade.green, size: 14))
                .disabled(trimmedName.isEmpty)
                .padding(.bottom, 6)
        }
        .onAppear {
            if let profile = model.profile {
                name = profile.name
                color = profile.color
                avatar = profile.avatar
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1. ENTER NAME")
            HStack {
                TextField("", text: $name, prompt: Text("AAA").foregroundStyle(Arcade.dim))
                    .font(Arcade.font(18))
                    .foregroundStyle(color.color)
                    .tint(color.color)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onChange(of: name) { _, newValue in
                        let clean = Profile.sanitize(newValue)
                        if clean != newValue { name = clean }
                    }
                Text("\(name.count)/\(Profile.maxNameLength)")
                    .font(Arcade.font(8))
                    .foregroundStyle(Arcade.dim)
            }
            .padding(14)
            .pixelPanel(color.color)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("2. PICK COLOR")
            HStack(spacing: 10) {
                ForEach(PlayerColor.allCases) { option in
                    Button {
                        color = option
                        Haptics.tick()
                    } label: {
                        PixelRect(step: 4)
                            .fill(option.color)
                            .frame(height: 40)
                            .overlay(
                                PixelRect(step: 4)
                                    .strokeBorder(Arcade.ink, lineWidth: option == color ? 3 : 0)
                            )
                            .neon(option.color, radius: option == color ? 6 : 0)
                    }
                    .accessibilityLabel("\(String(describing: option)) color")
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                }
            }
        }
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("3. DRAW AVATAR")
            AvatarEditor(avatar: $avatar, color: color.color)
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button("RANDOM") { avatar = .random() }
                    .buttonStyle(.arcade(Arcade.magenta, filled: false, size: 10))
                Button("CLEAR") { avatar = PixelAvatar() }
                    .buttonStyle(.arcade(Arcade.red, filled: false, size: 10))
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Arcade.font(10))
            .foregroundStyle(Arcade.yellow)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        nameFocused = false
        let profile = Profile(
            name: trimmedName,
            color: color,
            avatar: avatar.isEmpty ? .invader : avatar
        )
        model.saveProfile(profile)
        Haptics.success()
        if mode == .edit { dismiss() }
    }
}

/// An 8×8 grid you paint by tapping or dragging. A drag paints or erases,
/// depending on whether the first cell it touched was off or on.
struct AvatarEditor: View {
    @Binding var avatar: PixelAvatar
    var color: Color

    @State private var paintValue: Bool?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cell = side / CGFloat(PixelAvatar.size)
            Canvas { context, _ in
                for y in 0..<PixelAvatar.size {
                    for x in 0..<PixelAvatar.size {
                        let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                        if avatar[x, y] {
                            context.fill(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(color))
                        } else {
                            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Arcade.dim.opacity(0.25)), lineWidth: 1)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = Int(value.location.x / cell)
                        let y = Int(value.location.y / cell)
                        guard (0..<PixelAvatar.size).contains(x), (0..<PixelAvatar.size).contains(y) else { return }
                        let paint = paintValue ?? !avatar[x, y]
                        paintValue = paint
                        if avatar[x, y] != paint {
                            avatar[x, y] = paint
                            Haptics.tick()
                        }
                    }
                    .onEnded { _ in paintValue = nil }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(10)
        .pixelPanel(color)
        .accessibilityLabel("Avatar editor, 8 by 8 pixels")
    }
}
