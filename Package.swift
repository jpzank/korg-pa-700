// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArrangerLab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArrangerLabCore", targets: ["ArrangerLabCore"]),
        .library(name: "ArrangerLabMIDI", targets: ["ArrangerLabMIDI"]),
        .library(name: "ArrangerLabAudio", targets: ["ArrangerLabAudio"]),
        .executable(name: "ArrangerLabApp", targets: ["ArrangerLabApp"]),
        .executable(name: "ArrangerLabMIDICommand", targets: ["ArrangerLabMIDICommand"]),
        .executable(name: "ArrangerLabTestHarness", targets: ["ArrangerLabTestHarness"])
    ],
    targets: [
        .target(name: "ArrangerLabCore", resources: [.process("Resources")]),
        .target(name: "ArrangerLabMIDI", dependencies: ["ArrangerLabCore"]),
        .target(name: "ArrangerLabAudio", dependencies: ["ArrangerLabCore"]),
        .executableTarget(name: "ArrangerLabApp", dependencies: ["ArrangerLabCore", "ArrangerLabMIDI", "ArrangerLabAudio"]),
        .executableTarget(name: "ArrangerLabMIDICommand", dependencies: ["ArrangerLabCore", "ArrangerLabMIDI"]),
        .executableTarget(name: "ArrangerLabTestHarness", dependencies: ["ArrangerLabCore", "ArrangerLabMIDI", "ArrangerLabAudio"])
    ]
)
