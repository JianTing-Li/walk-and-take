//
//  LaunchOptions.swift
//  WalkAndTake
//
//  DEBUG launch arguments for UI tests and demos:
//    -UITestInMemoryStore            fresh in-memory data every launch
//    -UITestNow 2026-09-24T08:00:00-04:00   freeze the clock at an ISO 8601 instant
//    -UITestFixedLocation            use the LIC center as a device fix (no permission prompt)
//    -UITestSeedReward               start with 1.2 walked miles and one banked 50% reward
//    -UITestSeedMiles 4.7            like -UITestSeedReward, but with this many walked miles already
//    -UITestSeedHistory              start with three finished walks at real restaurants (0.4, 0.9, 0.6 mi)
//    -UITestSimulateWalk             walks are Developer mode's simulated walks (auto-walk to the door)
//    -UITestSkipSplash               start on the tabs (UI tests can't reliably wait out the animation)
//

#if DEBUG
    import Domain
    import Foundation
    import Platform

    struct LaunchOptions {
        var inMemoryStore = false
        var fixedNow: Date?
        var fixedLocation = false
        var skipSplash = false
        var seedReward = false
        var seedMiles: Double?
        var seedHistory = false
        var simulateWalk = false

        static var current: LaunchOptions {
            LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        }

        init(arguments: [String]) {
            inMemoryStore = arguments.contains("-UITestInMemoryStore")
            fixedLocation = arguments.contains("-UITestFixedLocation")
            skipSplash = arguments.contains("-UITestSkipSplash")
            seedReward = arguments.contains("-UITestSeedReward")
            if let index = arguments.firstIndex(of: "-UITestSeedMiles"), arguments.indices.contains(index + 1) {
                seedMiles = Double(arguments[index + 1])
            }
            simulateWalk = arguments.contains("-UITestSimulateWalk")
            seedHistory = arguments.contains("-UITestSeedHistory")
            if let index = arguments.firstIndex(of: "-UITestNow"), arguments.indices.contains(index + 1) {
                fixedNow = try? Date(arguments[index + 1], strategy: .iso8601)
            }
        }
    }
#endif
