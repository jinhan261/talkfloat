#!/usr/bin/env swift
import Foundation
import Vision

// Run TalkFloat --render-design <directory> first. Check the visible pixels
// because layout truncation leaves the underlying accessibility string intact.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/check-caption-wrap.swift <render-directory>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let expected = "when the timer goes off write down what you learned so you can pick up where you left off tomorrow morning"
let cases = ["long-720x340-30", "long-400x300-30", "long-400x300-38", "long-400x520-38"]
var failures = 0
for name in cases {
    do {
        let image = directory.appendingPathComponent(name).appendingPathExtension("png")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(url: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let recognized = lines.joined(separator: " ").lowercased()
            .split { !$0.isLetter }.joined(separator: " ")
        if recognized.contains(expected) {
            print("PASS \(name)")
        } else {
            print("FAIL \(name): the rendered English sentence is incomplete")
            failures += 1
        }
    } catch {
        print("ERROR \(name): \(error.localizedDescription)")
        failures += 1
    }
}
exit(failures == 0 ? 0 : 1)
