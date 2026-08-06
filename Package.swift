// swift-tools-version: 5.10
import Foundation
import PackageDescription

let developerPath = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Library/Developer/CommandLineTools"
let testingFrameworkPath = "\(developerPath)/Library/Developer/Frameworks"
let testingLibraryPath = "\(developerPath)/Library/Developer/usr/lib"
let testingSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-F", testingFrameworkPath])
]
let testingLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", testingFrameworkPath,
        "-Xlinker", "-rpath", "-Xlinker", testingFrameworkPath,
        "-Xlinker", "-rpath", "-Xlinker", testingLibraryPath
    ])
]

let package = Package(
    name: "ArrangerLab",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ArrangerLabApp", targets: ["ArrangerLabApp"]),
        .executable(name: "ArrangerLabTestHarness", targets: ["ArrangerLabTestHarness"])
    ],
    targets: [
        .target(name: "ArrangerLabCore", resources: [.process("Resources")]),
        .target(name: "ArrangerLabMIDI", dependencies: ["ArrangerLabCore"]),
        .target(name: "ArrangerLabAudio", dependencies: ["ArrangerLabCore"]),
        .executableTarget(name: "ArrangerLabApp", dependencies: ["ArrangerLabCore", "ArrangerLabMIDI", "ArrangerLabAudio"]),
        .executableTarget(name: "ArrangerLabTestHarness", dependencies: ["ArrangerLabCore", "ArrangerLabMIDI", "ArrangerLabAudio"]),
        .testTarget(
            name: "ArrangerLabCoreTests",
            dependencies: ["ArrangerLabCore"],
            swiftSettings: testingSwiftSettings,
            linkerSettings: testingLinkerSettings
        ),
        .testTarget(
            name: "ArrangerLabMIDITests",
            dependencies: ["ArrangerLabCore", "ArrangerLabMIDI"],
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "ArrangerLabAudioTests",
            dependencies: ["ArrangerLabCore", "ArrangerLabAudio"],
            swiftSettings: testingSwiftSettings
        )
    ]
)
