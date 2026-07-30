import AVKit
import MediaShelfCore
import SwiftUI

@MainActor
final class PlayerSession: ObservableObject {
    let item: MediaItem
    let player: AVPlayer
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var didReachEnd = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(item: MediaItem) {
        self.item = item
        self.player = AVPlayer(url: item.mediaURL)
        player.preventsDisplaySleepDuringVideoPlayback = true
        let interval = CMTime(seconds: 2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                let itemDuration = self.player.currentItem?.duration.seconds ?? 0
                self.duration = itemDuration.isFinite ? itemDuration : 0
                self.isPlaying = self.player.rate != 0
                if let error = self.player.currentItem?.error {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.didReachEnd = true
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func start() {
        if item.playbackPosition > 0 && !item.isWatched {
            player.seek(
                to: CMTime(seconds: item.playbackPosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        if player.rate == 0 {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func jump(by seconds: Double) {
        let target = max(currentTime + seconds, 0)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
}

struct PlayerView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: PlayerSession
    @State private var showsControls = true
    @State private var lastSavedAt: Double = 0

    init(appState: AppState, controller: ControllerManager, item: MediaItem) {
        self.appState = appState
        self.controller = controller
        self.item = item
        _session = StateObject(wrappedValue: PlayerSession(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: session.player)
                .ignoresSafeArea()
            if showsControls || session.errorMessage != nil {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            session.start()
        }
        .onDisappear {
            session.player.pause()
            saveProgress()
        }
        .onChange(of: session.currentTime) { time in
            if time - lastSavedAt >= 10 {
                lastSavedAt = time
                saveProgress()
            }
        }
        .onChange(of: session.didReachEnd) { didReachEnd in
            guard didReachEnd else { return }
            let completedDuration = session.duration > 0 ? session.duration : session.currentTime
            Task {
                await appState.saveProgress(
                    item,
                    position: completedDuration,
                    duration: completedDuration > 0 ? completedDuration : nil
                )
            }
            if appState.nextEpisode(after: item) != nil {
                dismiss()
                appState.playNextEpisode(after: item)
            }
        }
        .onChange(of: controller.lastAction) { action in
            guard let action else { return }
            switch action {
            case .playPause, .select:
                session.togglePlayback()
            case .left:
                session.jump(by: -10)
            case .right:
                session.jump(by: 10)
            case .back:
                dismiss()
            case .menu:
                withAnimation { showsControls.toggle() }
            case .up, .down:
                showsControls = true
            }
            controller.consume()
        }
        .onTapGesture {
            withAnimation { showsControls.toggle() }
        }
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle)
                        .font(.title2.bold())
                    if item.kind == .episode {
                        Text("\(item.episodeCode) • \(item.effectiveEpisodeTitle)")
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("Exit Player", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(28)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.78), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Spacer()
            if let error = session.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("This file could not be played.")
                        .font(.title2.bold())
                    Text(error)
                        .foregroundStyle(Color.white.opacity(0.72))
                    HStack {
                        Button("Show in Finder") {
                            appState.showMediaInFinder(item)
                        }
                        Button("Back") {
                            dismiss()
                        }
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            VStack(spacing: 14) {
                ProgressView(
                    value: session.duration > 0 ? session.currentTime / session.duration : 0
                )
                .tint(ShelfTheme.accent)
                HStack {
                    Text(timestamp(session.currentTime))
                        .monospacedDigit()
                    Spacer()
                    Button {
                        session.jump(by: -10)
                    } label: {
                        Label("Back 10", systemImage: "gobackward.10")
                    }
                    Button {
                        session.togglePlayback()
                    } label: {
                        Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    Button {
                        session.jump(by: 10)
                    } label: {
                        Label("Forward 10", systemImage: "goforward.10")
                    }
                    Spacer()
                    Text("-\(timestamp(max(session.duration - session.currentTime, 0)))")
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .foregroundStyle(.white)
    }

    private func saveProgress() {
        let position = session.currentTime
        let duration = session.duration > 0 ? session.duration : nil
        Task {
            await appState.saveProgress(item, position: position, duration: duration)
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}
