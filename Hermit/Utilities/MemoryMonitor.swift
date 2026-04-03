import Foundation
import Observation
import UIKit

@Observable
final class MemoryMonitor {
    private(set) var availableMemoryMB: Int = 0
    private var timer: Timer?
    private var notificationObserver: Any?

    init() {
        update()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func update() {
        let bytes = os_proc_available_memory()
        if bytes > 0 {
            availableMemoryMB = Int(bytes) / (1024 * 1024)
            return
        }
        // Fallback for simulator where os_proc_available_memory() returns 0
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = info.resident_size
            availableMemoryMB = Int(totalMemory - usedMemory) / (1024 * 1024)
        }
    }

    func hasEnoughMemory(requiredMB: Int) -> Bool {
        update()
        return availableMemoryMB >= requiredMB
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.update()
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[MemoryMonitor] Memory warning received – updating available memory")
            self?.update()
        }
    }
}
