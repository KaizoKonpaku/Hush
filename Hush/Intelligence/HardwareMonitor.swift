import Foundation
import Metal
import MLX
import Observation

@MainActor @Observable
final class HardwareMonitor {
    let chipName: String
    let physicalMemory: UInt64
    let processorCount: Int
    let recommendedWorkingSet: UInt64
    var activeModelMemory = 0
    var cachedModelMemory = 0
    var thermalState = "Nominal"
    var isLowPowerMode = false
    private let device: (any MTLDevice)?

    init() {
        device = MTLCreateSystemDefaultDevice()
        chipName = device?.name ?? "No Metal GPU"
        physicalMemory = ProcessInfo.processInfo.physicalMemory
        processorCount = ProcessInfo.processInfo.activeProcessorCount
        recommendedWorkingSet = device?.recommendedMaxWorkingSetSize ?? physicalMemory / 2
        refresh()
    }

    func budget(for policy: ComputePolicy) -> Int {
        let reserve = min(physicalMemory / 4, 3 * 1024 * 1024 * 1024)
        let limit = min(recommendedWorkingSet, physicalMemory - reserve)
        let fraction = isLowPowerMode ? min(0.7, policy.budgetFraction) : policy.budgetFraction
        return Int(Double(limit) * fraction)
    }

    func refresh() {
        activeModelMemory = Memory.activeMemory
        cachedModelMemory = Memory.cacheMemory
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "Nominal"
        case .fair: thermalState = "Warm"
        case .serious: thermalState = "Elevated"
        case .critical: thermalState = "Cooling down"
        @unknown default: thermalState = "Unknown"
        }
    }

    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }
}
