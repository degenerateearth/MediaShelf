import MediaShelfCore
import SwiftUI

struct ArtworkMatchView: View {
    @ObservedObject var appState: AppState

    private var review: ArtworkMatchReview? { appState.artworkReviews.first }

    var body: some View {
        ZStack {
            ShelfTheme.canvas.ignoresSafeArea()
            if let review {
                VStack(alignment: .leading, spacing: 28) {
                    header(review)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 22) {
                            ForEach(review.candidates, id: \.providerID) { candidate in
                                candidateCard(candidate, review: review)
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.bottom, 20)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Button("Skip for now") {
                            appState.skipArtworkReview(review)
                        }
                        .buttonStyle(PremiumSecondaryButtonStyle())
                        Spacer()
                        Text("\(appState.artworkReviews.count) title\(appState.artworkReviews.count == 1 ? "" : "s") to review")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ShelfTheme.textTertiary)
                    }
                }
                .padding(36)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 760, minHeight: 570)
    }

    private func header(_ review: ArtworkMatchReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOOSE THE RIGHT MATCH")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(ShelfTheme.accent)
            Text(review.title)
                .font(.system(size: 36, weight: .semibold))
            Text("MediaShelf found more than one exact title. Your choice applies to the entire \(review.kind == .movie ? "movie" : "series").")
                .foregroundStyle(ShelfTheme.textSecondary)
        }
    }

    private func candidateCard(
        _ candidate: MetadataMatch,
        review: ArtworkMatchReview
    ) -> some View {
        Button {
            Task { await appState.selectArtworkMatch(candidate, for: review) }
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                AsyncImage(url: candidate.posterURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ArtworkView(path: nil, title: candidate.title)
                    }
                }
                .frame(width: 205, height: 307)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(candidate.year.map(String.init) ?? "Year unavailable")
                    .font(.subheadline)
                    .foregroundStyle(ShelfTheme.textSecondary)
            }
            .frame(width: 205, alignment: .leading)
            .padding(12)
            .background(ShelfTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
