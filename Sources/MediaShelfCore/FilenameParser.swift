import Foundation

public struct FilenameParser: Sendable {
    private let releaseTokens: Set<String> = [
        "480p", "720p", "1080p", "1080i", "2160p", "4k", "uhd",
        "bluray", "brrip", "bdrip", "web-dl", "webdl", "webrip", "hdtv",
        "remux", "x264", "x265", "h264", "h265", "hevc", "av1",
        "hdr", "hdr10", "dv", "dolbyvision", "aac", "ac3", "eac3",
        "dts", "truehd", "atmos", "10bit", "proper", "repack", "extended"
    ]

    private let episodePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"(?i)^(.*?)[\s._-]+S(\d{1,2})E(\d{1,3})(?:[\s._-]+(.*))?$"#
        ),
        try! NSRegularExpression(
            pattern: #"(?i)^(.*?)[\s._-]+(\d{1,2})x(\d{1,3})(?:[\s._-]+(.*))?$"#
        )
    ]

    private let yearPattern = try! NSRegularExpression(
        pattern: #"(?<!\d)(19\d{2}|20\d{2})(?!\d)"#
    )

    private let seasonOnlyPattern = try! NSRegularExpression(
        pattern: #"(?i)^(.*?)[\s._-]+(?:(19\d{2}|20\d{2})[\s._-]+)?S(\d{1,2})(?:[\s._-]+(.*))?$"#
    )

    public init() {}

    public func parse(url: URL) -> ParsedFilename {
        parse(filename: url.deletingPathExtension().lastPathComponent)
    }

    public func parse(filename: String) -> ParsedFilename {
        let base = stripBracketedContent(from: filename)

        for expression in episodePatterns {
            let range = NSRange(base.startIndex..<base.endIndex, in: base)
            guard let match = expression.firstMatch(in: base, range: range),
                  let seriesRange = Range(match.range(at: 1), in: base),
                  let seasonRange = Range(match.range(at: 2), in: base),
                  let episodeRange = Range(match.range(at: 3), in: base)
            else { continue }

            let series = cleanTitle(String(base[seriesRange]))
            let season = Int(base[seasonRange])
            let episode = Int(base[episodeRange])
            var episodeTitle: String?

            if match.range(at: 4).location != NSNotFound,
               let titleRange = Range(match.range(at: 4), in: base) {
                episodeTitle = cleanTitle(String(base[titleRange])).nonEmpty
            }

            return ParsedFilename(
                kind: .episode,
                title: series,
                seasonNumber: season,
                episodeNumber: episode,
                episodeTitle: episodeTitle
            )
        }

        let seasonRange = NSRange(base.startIndex..<base.endIndex, in: base)
        if let match = seasonOnlyPattern.firstMatch(in: base, range: seasonRange),
           let seriesRange = Range(match.range(at: 1), in: base),
           let numberRange = Range(match.range(at: 3), in: base) {
            let series = cleanTitle(String(base[seriesRange]))
            let year: Int?
            if match.range(at: 2).location != NSNotFound,
               let yearRange = Range(match.range(at: 2), in: base) {
                year = Int(base[yearRange])
            } else {
                year = nil
            }
            var title: String?
            if match.range(at: 4).location != NSNotFound,
               let titleRange = Range(match.range(at: 4), in: base) {
                title = cleanTitle(String(base[titleRange])).nonEmpty
            }
            return ParsedFilename(
                kind: .episode,
                title: series,
                year: year,
                seasonNumber: Int(base[numberRange]),
                episodeTitle: title
            )
        }

        let range = NSRange(base.startIndex..<base.endIndex, in: base)
        let yearMatch = yearPattern.firstMatch(in: base, range: range)
        var titlePortion = base
        var year: Int?

        if let yearMatch,
           let matchRange = Range(yearMatch.range(at: 1), in: base) {
            year = Int(base[matchRange])
            titlePortion = String(base[..<matchRange.lowerBound])
        }

        return ParsedFilename(
            kind: .movie,
            title: cleanTitle(titlePortion),
            year: year
        )
    }

    private func stripBracketedContent(from value: String) -> String {
        value.replacingOccurrences(
            of: #"\[[^\]]*\]|\{[^}]*\}"#,
            with: " ",
            options: .regularExpression
        )
    }

    private func cleanTitle(_ value: String) -> String {
        let words = value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[\(\)\[\]\{\}]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)

        let kept = words.prefix { word in
            let normalized = word.lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            return !releaseTokens.contains(normalized)
        }

        return kept
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
