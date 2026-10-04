import SwiftUI

/// A cast or crew member: a round photo with their name and role beneath, for a detail screen's cast row.
///
/// Without a photo, the circle shows the person's initials. The card fills the width it is given.
public struct PersonCard: View {
    private let name: String
    private let role: String?
    private let photo: Image?

    /// Creates a person card.
    ///
    /// - Parameters:
    ///   - name: The person's name.
    ///   - role: The character they play or their job, such as "Director".
    ///   - photo: Their photo, or nil while it loads or when there is none.
    public init(name: String, role: String?, photo: Image?) {
        self.name = name
        self.role = role
        self.photo = photo
    }

    public var body: some View {
        VStack(spacing: Spacing.xSmall) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photo {
                        photo
                            .resizable()
                            .scaledToFill()
                    } else {
                        Initials(name: name)
                    }
                }
                .clipShape(.circle)
            VStack(spacing: 2) {
                Text(name)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                if let role, !role.isEmpty {
                    Text(role)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let role, !role.isEmpty else { return name }
        return String(
            localized: "\(name), \(role)",
            bundle: .module,
            comment: "VoiceOver label for a cast member: their name, then their role."
        )
    }
}

/// A person's initials on the surface colour, for when there is no photo.
private struct Initials: View {
    let name: String

    var body: some View {
        Rectangle()
            .fill(.surface)
            .overlay {
                Text(initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.textSecondary)
                    .minimumScaleFactor(0.5)
                    .padding(Spacing.xSmall)
            }
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }
}

#if DEBUG
    private struct PersonCardSample: View {
        private let people: [(name: String, role: String, seed: Int?)] = [
            ("Buster Keaton", "Johnnie Gray", 3),
            ("Marion Mack", "Annabelle Lee", nil),
            ("Clyde Bruckman", "Director", 11),
            ("Glen Cavender", "Captain Anderson", nil),
        ]

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.small) {
                ForEach(people, id: \.name) { person in
                    PersonCard(
                        name: person.name,
                        role: person.role,
                        photo: person.seed.flatMap { PlaceholderArt.poster(seed: $0) }.map {
                            Image(decorative: $0, scale: 1)
                        }
                    )
                }
            }
            .padding(Spacing.medium)
            .background(Color.background)
        }
    }

    #Preview("Light") {
        PersonCardSample()
    }

    #Preview("Dark") {
        PersonCardSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        PersonCardSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
