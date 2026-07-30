import AppKit
import Foundation
import GameController

enum ControllerAction {
    case up
    case down
    case left
    case right
    case select
    case back
    case menu
    case playPause
}

@MainActor
final class ControllerManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastAction: ControllerAction?
    private var observers: [NSObjectProtocol] = []
    private var lastDirectionalAction = Date.distantPast

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
                }
            }
        )
        GCController.controllers().forEach(configure)
        GCController.startWirelessControllerDiscovery()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func consume() {
        lastAction = nil
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
                Task { @MainActor in
                    self?.lastAction = .select
                    self?.dispatch(#selector(NSResponder.insertNewline(_:)))
                }
            }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                Task { @MainActor in
                    self?.lastAction = .back
                    self?.dispatch(#selector(NSResponder.cancelOperation(_:)))
                }
            }
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.lastAction = .menu } }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.lastAction = .playPause } }
        }
    }

    private func handleDirection(x: Float, y: Float) {
        guard Date().timeIntervalSince(lastDirectionalAction) > 0.18 else { return }
        let threshold: Float = 0.55
        if x > threshold {
            lastAction = .right
            dispatch(#selector(NSResponder.moveRight(_:)))
        } else if x < -threshold {
            lastAction = .left
            dispatch(#selector(NSResponder.moveLeft(_:)))
        } else if y > threshold {
            lastAction = .up
            dispatch(#selector(NSResponder.moveUp(_:)))
        } else if y < -threshold {
            lastAction = .down
            dispatch(#selector(NSResponder.moveDown(_:)))
        } else {
            return
        }
        lastDirectionalAction = .now
    }

    private func dispatch(_ selector: Selector) {
        NSApp.keyWindow?.firstResponder?.tryToPerform(selector, with: nil)
    }
}
