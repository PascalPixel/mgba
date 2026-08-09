import Foundation
import GameController

final class ControllerInputService {
    private let onKeyMask: (UInt32) -> Void
    private let onControllersChanged: ([String]) -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        onKeyMask: @escaping (UInt32) -> Void,
        onControllersChanged: @escaping ([String]) -> Void
    ) {
        self.onKeyMask = onKeyMask
        self.onControllersChanged = onControllersChanged
    }

    func start() {
        guard observers.isEmpty else { return }
        GCController.shouldMonitorBackgroundEvents = false

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.configure(controller)
                self?.publishControllers()
            },
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.publishInput()
                self?.publishControllers()
            },
        ]

        GCController.controllers().forEach(configure)
        publishControllers()
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.stopWirelessControllerDiscovery()
        onKeyMask(0)
    }

    private func configure(_ controller: GCController) {
        controller.handlerQueue = .main
        controller.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in
            self?.publishInput()
        }
        controller.microGamepad?.valueChangedHandler = { [weak self] _, _ in
            self?.publishInput()
        }
    }

    private func publishInput() {
        let mask = GCController.controllers().reduce(UInt32(0)) { partial, controller in
            partial | keyMask(for: controller)
        }
        onKeyMask(mask)
    }

    private func keyMask(for controller: GCController) -> UInt32 {
        if let pad = controller.extendedGamepad {
            var mask: UInt32 = 0
            set(&mask, bit: 0, when: pad.buttonA.isPressed)
            set(&mask, bit: 1, when: pad.buttonB.isPressed)
            set(&mask, bit: 2, when: pad.buttonOptions?.isPressed == true)
            set(&mask, bit: 3, when: pad.buttonMenu.isPressed)
            set(&mask, bit: 4, when: pad.dpad.right.isPressed || pad.leftThumbstick.right.isPressed)
            set(&mask, bit: 5, when: pad.dpad.left.isPressed || pad.leftThumbstick.left.isPressed)
            set(&mask, bit: 6, when: pad.dpad.up.isPressed || pad.leftThumbstick.up.isPressed)
            set(&mask, bit: 7, when: pad.dpad.down.isPressed || pad.leftThumbstick.down.isPressed)
            set(&mask, bit: 8, when: pad.rightShoulder.isPressed || pad.rightTrigger.isPressed)
            set(&mask, bit: 9, when: pad.leftShoulder.isPressed || pad.leftTrigger.isPressed)
            return mask
        }

        if let pad = controller.microGamepad {
            var mask: UInt32 = 0
            set(&mask, bit: 0, when: pad.buttonA.isPressed)
            set(&mask, bit: 1, when: pad.buttonX.isPressed)
            set(&mask, bit: 3, when: pad.buttonMenu.isPressed)
            set(&mask, bit: 4, when: pad.dpad.right.isPressed)
            set(&mask, bit: 5, when: pad.dpad.left.isPressed)
            set(&mask, bit: 6, when: pad.dpad.up.isPressed)
            set(&mask, bit: 7, when: pad.dpad.down.isPressed)
            return mask
        }

        return 0
    }

    private func set(_ mask: inout UInt32, bit: UInt32, when pressed: Bool) {
        if pressed { mask |= 1 << bit }
    }

    private func publishControllers() {
        let names = GCController.controllers().map { controller in
            controller.vendorName ?? controller.productCategory
        }
        onControllersChanged(names)
    }
}
