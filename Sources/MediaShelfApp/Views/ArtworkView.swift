import AppKit
import MediaShelfCore
import SwiftUI

struct ArtworkView: View {
    let path: String?
    let title: String
    var isBackdrop = false

    var body: some View {
        Group {
            if let path, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ShelfTheme.secondaryAccent.opacity(0.72),
                    ShelfTheme.accent.opacity(0.38),
                    ShelfTheme.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: isBackdrop ? 420 : 180)
                .offset(x: isBackdrop ? 180 : 55, y: isBackdrop ? -60 : -85)
            VStack(spacing: 8) {
                Image(systemName: isBackdrop ? "sparkles.tv" : "play.rectangle.fill")
                    .font(.system(size: isBackdrop ? 42 : 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text(title.uppercased())
                    .font(.system(size: isBackdrop ? 30 : 17, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct PosterCard: View {
    let item: MediaItem
    var treatEpisodeAsSeries = false
    let focusID: String
    @Binding var focusedCard: String?
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    private var isHighlighted: Bool {
        isFocused || focusedCard == focusID
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(path: item.posterPath ?? item.thumbnailPath, title: item.displayTitle)
                        .frame(width: 178, height: 267)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if item.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, ShelfTheme.accent)
                            .padding(10)
                    }

                    if item.progressFraction > 0 && !item.isWatched {
                        GeometryReader { proxy in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.black.opacity(0.65))
                                    Capsule().fill(ShelfTheme.accent)
                                        .frame(width: proxy.size.width * item.progressFraction)
                                }
                                .frame(height: 4)
                                .padding(8)
                            }
                        }
                    }
                }
                .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isHighlighted ? ShelfTheme.accent : Color.white.opacity(0.08),
                            lineWidth: isHighlighted ? 4 : 1
                        )
                }
                .shadow(
                    color: isHighlighted ? ShelfTheme.accent.opacity(0.28) : .black.opacity(0.28),
                    radius: isHighlighted ? 18 : 10,
                    y: 6
                )

                Text(item.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ShelfTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 178, alignment: .leading)
            .scaleEffect(isHighlighted ? 1.045 : 1)
            .animation(.easeOut(duration: 0.16), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .focusable()
        .id(focusID)
        .contextMenu {
            Button("Open Details", action: action)
        }
        .accessibilityLabel("\(item.displayTitle), \(subtitle)")
    }

    private var subtitle: String {
        if item.kind == .episode && treatEpisodeAsSeries {
            return "TV Series"
        }
        if item.kind == .episode {
            return item.episodeCode
        }
        return item.year.map(String.init) ?? "Movie"
    }
}
