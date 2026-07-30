import Foundation
import GameController

enum ControllerAction: Hashable {
    case up
    case down
    case left
    case right
    case select
    case back
    case menu
    case playPause
    case seekBackward
    case seekForward
}

@MainActor
final class ControllerManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastAction: ControllerAction?
    @Published private(set) var actionRevision = 0
    private var observers: [NSObjectProtocol] = []
    private var seekTimers: [ControllerAction: Timer] = [:]
    private var directionalTimer: Timer?
    private var heldDirection: ControllerAction?

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in self?.configure(controller) }
            }
        )
        observers.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isConnected = !GCController.controllers().isEmpty
                    if self?.isConnected == false {
                        self?.stopAllRepeatingInputs()
                    }
                }
            }
        )
        GCController.controllers().forEach(configure)
        GCController.startWirelessControllerDiscovery()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        seekTimers.values.forEach { $0.invalidate() }
        directionalTimer?.invalidate()
    }

    private func configure(_ controller: GCController) {
        isConnected = true
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.handleDirection(x: x, y: y) }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.handleDirection(x: x, y: y) }
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in self?.emit(.select) }
            }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in self?.emit(.back) }
            }
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.menu) } }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.playPause) } }
        }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                if pressed {
                    self?.beginRepeating(.seekBackward)
                } else {
                    self?.stopRepeating(.seekBackward)
                }
            }
        }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                if pressed {
                    self?.beginRepeating(.seekForward)
                } else {
                    self?.stopRepeating(.seekForward)
                }
            }
        }
    }

    private func handleDirection(x: Float, y: Float) {
        let threshold: Float = 0.55
        let direction: ControllerAction?
        if x > threshold {
            direction = .right
        } else if x < -threshold {
            direction = .left
        } else if y > threshold {
            direction = .up
        } else if y < -threshold {
            direction = .down
        } else {
            stopDirectionalRepeat()
            return
        }
        guard direction != heldDirection, let direction else { return }
        beginDirectionalRepeat(direction)
    }

    private func emit(_ action: ControllerAction) {
        lastAction = action
        actionRevision &+= 1
    }

    private func beginRepeating(_ action: ControllerAction) {
        stopRepeating(action)
        emit(action)
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit(action) }
        }
        seekTimers[action] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRepeating(_ action: ControllerAction) {
        seekTimers.removeValue(forKey: action)?.invalidate()
    }

    private func beginDirectionalRepeat(_ action: ControllerAction) {
        stopDirectionalRepeat()
        heldDirection = action
        emit(action)
        let timer = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit(action) }
        }
        timer.fireDate = Date().addingTimeInterval(0.42)
        directionalTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDirectionalRepeat() {
        directionalTimer?.invalidate()
        directionalTimer = nil
        heldDirection = nil
    }

    private func stopAllRepeatingInputs() {
        seekTimers.values.forEach { $0.invalidate() }
        seekTimers.removeAll()
        stopDirectionalRepeat()
    }
}
