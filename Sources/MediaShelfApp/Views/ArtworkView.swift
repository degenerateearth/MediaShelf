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
                    ShelfTheme.surfaceRaised,
                    ShelfTheme.surface,
                    ShelfTheme.canvas
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
                    .font(.system(size: isBackdrop ? 28 : 15, weight: .semibold))
                    .tracking(isBackdrop ? 1.2 : 0.5)
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
    var markFinished: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    private var isHighlighted: Bool {
        isFocused || focusedCard == focusID
    }

    var body: some View {
        Button(action: action) {
                VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(path: item.posterPath ?? item.thumbnailPath, title: item.displayTitle)
                        .frame(width: 178, height: 267)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isHighlighted ? Color.white.opacity(0.92) : Color.white.opacity(0.07),
                            lineWidth: isHighlighted ? 2 : 1
                        )
                }
                .shadow(
                    color: .black.opacity(isHighlighted ? 0.62 : 0.32),
                    radius: isHighlighted ? 24 : 12,
                    y: isHighlighted ? 12 : 7
                )

                Text(item.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ShelfTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 178, alignment: .leading)
            .brightness(isHighlighted ? 0.035 : 0)
            .scaleEffect(isHighlighted ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.84), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .focusable()
        .id(focusID)
        .contextMenu {
            Button("Open Details", action: action)
            if let markFinished {
                Divider()
                Button("Finished", systemImage: "checkmark.circle", action: markFinished)
            }
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
