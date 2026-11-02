// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TalkFloat", platforms: [.macOS("14.2")], products: [
    .executable(name: "TalkFloat", targets: ["TalkFloat"]),
    .executable(name: "SayloriCheck", targets: ["SayloriCheck"])
], targets: [
    .target(name: "AudioRing", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
    .target(name: "SpeexDSP", exclude:["COPYING","ORIGIN.md"], publicHeadersPath:"include", cSettings:[.define("FLOATING_POINT"),.define("USE_KISS_FFT"),.define("EXPORT",to:""),.define("VAR_ARRAYS")]),
    .target(name: "SayloriCore", dependencies: ["AudioRing","SpeexDSP"]),
    .executableTarget(name: "TalkFloat", dependencies: ["SayloriCore"], path: "Sources/Saylori"),
    .executableTarget(name: "SayloriCheck", dependencies: ["SayloriCore"]),
    .testTarget(name: "SayloriCoreTests", dependencies: ["SayloriCore", "AudioRing"])
], swiftLanguageModes: [.v5])
