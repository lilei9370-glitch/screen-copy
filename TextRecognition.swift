import Vision

enum TextRecognition {
    static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US", "zh-Hant"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])

        // Vision measures y from the bottom. Group fragments on the same row
        // before ordering them from left to right.
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows = [[VNRecognizedTextObservation]]()
        for observation in observations {
            let box = observation.boundingBox
            if let anchor = rows.last?.first?.boundingBox,
               anchor.midY - box.midY < min(anchor.height, box.height) / 2 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }.joined(separator: "\n")
    }
}
