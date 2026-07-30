import KSPlayer
import MediaShelfCore
import SwiftUI

@MainActor
final class PlayerSession: ObservableObject {
    let item: MediaItem
    let coordinator: KSVideoPlayer.Coordinator
    let options: KSOptions
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var didReachEnd = false

    init(item: MediaItem) {
        self.item = item
        self.coordinator = KSVideoPlayer.Coordinator()
        self.options = KSOptions()
        options.startPlayTime = item.isWatched ? 0 : item.playbackPosition
        options.autoSelectEmbedSubtitle = true
        options.hardwareDecode = true

        // FFmpeg is the primary engine so MKV, EAC3, DTS, and embedded
        // subtitles work immediately instead of waiting for AVPlayer to fail.
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self

        coordinator.onPlay = { [weak self] currentTime, duration in
            guard let self else { return }
            self.currentTime = currentTime.isFinite ? currentTime : 0
            self.duration = duration.isFinite ? duration : 0
        }
        coordinator.onStateChanged = { [weak self] _, state in
            guard let self else { return }
            self.isPlaying = state.isPlaying
            if state == .error, self.errorMessage == nil {
                self.errorMessage = "The codec engine could not open this file."
            }
        }
        coordinator.onFinish = { [weak self] _, error in
            guard let self else { return }
            self.isPlaying = false
            if let error {
                self.errorMessage = error.localizedDescription
            } else {
                self.didReachEnd = true
            }
        }
    }

    func start() {
        coordinator.playerLayer?.play()
        isPlaying = true
    }

    func stop() {
        coordinator.playerLayer?.pause()
        coordinator.resetPlayer()
        isPlaying = false
    }

    func togglePlayback() {
        guard let playerLayer = coordinator.playerLayer else { return }
        if playerLayer.state.isPlaying {
            playerLayer.pause()
            isPlaying = false
        } else {
            playerLayer.play()
            isPlaying = true
        }
    }

    func jump(by seconds: Double) {
        let target = max(currentTime + seconds, 0)
        coordinator.seek(time: target)
    }

    func seek(to time: Double) {
        coordinator.seek(time: min(max(time, 0), duration > 0 ? duration : time))
        currentTime = time
    }
}

struct PlayerView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    let item: MediaItem
    @StateObject private var session: PlayerSession
    @State private var showsControls = true
    @State private var lastSavedAt: Double = 0
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    init(appState: AppState, controller: ControllerManager, item: MediaItem) {
        self.appState = appState
        self.controller = controller
        self.item = item
        _session = StateObject(wrappedValue: PlayerSession(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            KSVideoPlayer(
                coordinator: session.coordinator,
                url: item.mediaURL,
                options: session.options
            )
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
            saveProgress()
            session.stop()
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
                appState.playNextEpisode(after: item)
            } else {
                appState.playingItem = nil
            }
        }
        .onChange(of: controller.actionRevision) { _ in
            guard let action = controller.lastAction else { return }
            switch action {
            case .playPause, .select:
                session.togglePlayback()
            case .left:
                session.jump(by: -10)
            case .right:
                session.jump(by: 10)
            case .seekBackward:
                session.jump(by: -5)
                showsControls = true
            case .seekForward:
                session.jump(by: 5)
                showsControls = true
            case .back:
                appState.playingItem = nil
            case .menu:
                withAnimation { showsControls.toggle() }
            case .up, .down:
                showsControls = true
            }
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
                    appState.playingItem = nil
                } label: {
                    Label("Back to Details", systemImage: "chevron.left.circle.fill")
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
                            appState.playingItem = nil
                        }
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            VStack(spacing: 14) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : session.currentTime },
                        set: {
                            scrubPosition = $0
                            isScrubbing = true
                        }
                    ),
                    in: 0...max(session.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubPosition = session.currentTime
                            isScrubbing = true
                        } else {
                            session.seek(to: scrubPosition)
                            isScrubbing = false
                        }
                    }
                )
                .tint(ShelfTheme.accent)
                HStack {
                    Text(timestamp(isScrubbing ? scrubPosition : session.currentTime))
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
                    Text("-\(timestamp(max(session.duration - (isScrubbing ? scrubPosition : session.currentTime), 0)))")
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
