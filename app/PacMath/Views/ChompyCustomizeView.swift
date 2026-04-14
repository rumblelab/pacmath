import SwiftUI

struct ChompyCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: ChompyProfile
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("customize")
                    .font(Theme.mono(20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 24)

                ChompyPreview(color: profile.color)
                    .frame(width: 90, height: 90)

                VStack(spacing: 10) {
                    Text("name")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("chompy", text: $profile.name)
                        .font(Theme.mono(22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: 240)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.borderColor, lineWidth: 1)
                        )
                }

                VStack(spacing: 12) {
                    Text("color")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 16) {
                        ForEach(ChompyProfile.palette) { entry in
                            swatchButton(entry)
                        }
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("done")
                        .font(Theme.mono(20, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.correctGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func swatchButton(_ entry: ChompyProfile.PaletteEntry) -> some View {
        let isSelected = profile.colorIndex == entry.id
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                profile.colorIndex = entry.id
            }
        } label: {
            Circle()
                .fill(entry.color)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Theme.textPrimary : Color.clear,
                            lineWidth: 2
                        )
                        .padding(-5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ChompyPreview: View {
    let color: Color
    @State private var mouthOpen = false
    @State private var facingRight = true
    private let chompTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ChompShape(mouthAngle: mouthOpen ? 45 : 2, facingRight: facingRight)
            .fill(color)
            .animation(.easeInOut(duration: 0.25), value: color)
            .onReceive(chompTimer) { _ in
                mouthOpen.toggle()
            }
    }
}

#Preview {
    ChompyCustomizeView(profile: ChompyProfile.shared)
}
