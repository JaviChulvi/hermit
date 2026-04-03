import Testing
@testable import Hermit

@Suite("MemoryMonitor Tests")
struct MemoryMonitorTests {

    @Test("update() reports available memory greater than zero")
    func updateReportsPositiveMemory() {
        let monitor = MemoryMonitor()
        monitor.update()
        #expect(monitor.availableMemoryMB > 0)
    }

    @Test("hasEnoughMemory returns true for 100 MB")
    func hasEnoughMemoryForSmallAmount() {
        let monitor = MemoryMonitor()
        #expect(monitor.hasEnoughMemory(requiredMB: 100))
    }

    @Test("hasEnoughMemory returns false for 999999 MB")
    func hasNotEnoughMemoryForHugeAmount() {
        let monitor = MemoryMonitor()
        #expect(!monitor.hasEnoughMemory(requiredMB: 999_999))
    }
}
