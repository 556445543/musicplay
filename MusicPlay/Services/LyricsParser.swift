import Compression
import Foundation

enum LyricsParser {
    static func parseFile(at url: URL) -> Lyrics? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data, pathExtension: url.pathExtension)
    }

    static func parse(data: Data, pathExtension: String) -> Lyrics? {
        if isKRC(data) {
            if let text = decryptKRC(data), let lyrics = parse(text: text, source: "KRC") {
                return lyrics
            }
        }

        guard let text = decodeText(data) else { return nil }
        return parse(text: text, source: pathExtension.uppercased())
    }

    static func parse(text rawText: String, source: String) -> Lyrics? {
        let text = rawText.hasPrefix("\u{FEFF}") ? String(rawText.dropFirst()) : rawText
        if let timed = parseTimed(text: text, source: source) {
            return timed
        }
        return parsePlain(text: text, source: source)
    }

    // MARK: - KRC

    private static let krcKey: [UInt8] = [
        0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
        0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
    ]

    private static func isKRC(_ data: Data) -> Bool {
        let prefix = [UInt8](data.prefix(4))
        return prefix == Array("krc1".utf8) || prefix == Array("$krc".utf8)
    }

    private static func decryptKRC(_ data: Data) -> String? {
        guard data.count > 10 else { return nil }
        var body = [UInt8](data.dropFirst(4))

        for index in body.indices {
            body[index] ^= krcKey[index % krcKey.count]
        }

        // zlib 头 2 字节 + Adler-32 校验 4 字节，剩下的是裸 deflate 流
        let deflate = Data(body[2..<(body.count - 4)])
        if let inflated = inflate(deflate), let text = decodeText(inflated) {
            return text
        }
        return decodeText(Data(body))
    }

    private static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var capacity = 32 * 1024
        let input = [UInt8](data)

        while capacity <= 16 * 1024 * 1024 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = output.withUnsafeMutableBufferPointer { destination in
                input.withUnsafeBufferPointer { source in
                    compression_decode_buffer(
                        destination.baseAddress!,
                        capacity,
                        source.baseAddress!,
                        input.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                return Data(output.prefix(written))
            }
            capacity *= 2
        }

        return nil
    }

    // MARK: - Timed lines

    private static let krcLineRegex = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    private static let lrcTimeRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let lrcOffsetRegex = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\s*\]$"#)
    private static let inlineTagRegex = try! NSRegularExpression(pattern: #"<[^>]*>"#)

    private static func parseTimed(text: String, source: String) -> Lyrics? {
        let rawLines = text.components(separatedBy: .newlines)
        var krcEntries: [(TimeInterval, String)] = []
        var lrcEntries: [(TimeInterval, String)] = []
        var offset: TimeInterval = 0

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let match = lrcOffsetRegex.firstMatch(in: line, range: range),
               let valueRange = Range(match.range(at: 1), in: line),
               let milliseconds = Double(line[valueRange]) {
                offset = milliseconds / 1000
                continue
            }

            if let match = krcLineRegex.firstMatch(in: line, range: range),
               let startRange = Range(match.range(at: 1), in: line),
               let contentRange = Range(match.range(at: 3), in: line),
               let start = Double(line[startRange]) {
                let content = stripTags(String(line[contentRange]), regex: inlineTagRegex)
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    krcEntries.append((start / 1000, content))
                }
                continue
            }

            let matches = lrcTimeRegex.matches(in: line, range: range)
            guard let last = matches.last,
                  let contentRange = Range(last.range, in: line) else { continue }

            let content = stripTags(String(line[contentRange.upperBound...]), regex: inlineTagRegex)
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange]) else { continue }

                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let digits = line[fractionRange]
                    if let value = Double(digits) {
                        fraction = value / pow(10, Double(digits.count))
                    }
                }
                lrcEntries.append((minutes * 60 + seconds + fraction - offset, content))
            }
        }

        let entries = krcEntries.isEmpty ? lrcEntries : krcEntries
        guard !entries.isEmpty else { return nil }

        let sorted = entries
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.0 == rhs.element.0
                    ? lhs.offset < rhs.offset
                    : lhs.element.0 < rhs.element.0
            }
            .map(\.element)

        let lines = sorted.enumerated().map { index, entry in
            LyricLine(id: index, time: max(entry.0, 0), text: entry.1)
        }

        return Lyrics(lines: lines, plainText: nil, source: source)
    }

    // MARK: - Plain text

    private static let metadataRegex = try! NSRegularExpression(pattern: #"^\[[^\]]*\]$"#)

    private static func parsePlain(text: String, source: String) -> Lyrics? {
        guard !text.localizedCaseInsensitiveContains("<html"),
              !text.localizedCaseInsensitiveContains("<script"),
              !text.localizedCaseInsensitiveContains("<!doctype") else { return nil }

        let lines = text.components(separatedBy: .newlines).compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if metadataRegex.firstMatch(in: line, range: range) != nil { return nil }
            return line
        }

        guard lines.count >= 2 else { return nil }
        return Lyrics(lines: [], plainText: lines.joined(separator: "\n"), source: source)
    }

    // MARK: - Helpers

    private static func stripTags(_ text: String, regex: NSRegularExpression) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return String(data: data, encoding: gb18030)
    }
}
