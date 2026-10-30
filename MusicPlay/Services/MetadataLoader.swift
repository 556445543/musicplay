import AVFoundation
import Foundation

struct LoadedMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval = 0
}

enum MetadataLoader {
    static func load(for url: URL) async -> LoadedMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = LoadedMetadata()

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                metadata.duration = seconds
            }
        }

        var rawFields: [TextField: String] = [:]
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey,
                      let field = TextField(commonKey: key),
                      let value = try? await item.load(.stringValue) else { continue }
                rawFields[field] = value
            }
        }

        let repaired = repairLegacyEncoding(rawFields)
        metadata.title = cleaned(repaired[.title])
        metadata.artist = cleaned(repaired[.artist], rejectingURLs: true)
        metadata.album = cleaned(repaired[.album], rejectingURLs: true)
        return metadata
    }

    private enum TextField: Hashable {
        case title
        case artist
        case album

        init?(commonKey key: AVMetadataKey) {
            switch key {
            case .commonKeyTitle: self = .title
            case .commonKeyArtist: self = .artist
            case .commonKeyAlbumName: self = .album
            default: return nil
            }
        }
    }

    private static func cleaned(_ rawValue: String?, rejectingURLs: Bool = false) -> String? {
        guard let rawValue else { return nil }
        let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))

        guard text.unicodeScalars.contains(where: {
            CharacterSet.alphanumerics.contains($0) || (0x4E00...0x9FFF).contains($0.value)
        }) else { return nil }

        if rejectingURLs, isURLLike(text) {
            return nil
        }
        return text
    }

    // 大量老 ID3 标签把 GBK/Big5 字节当 ISO-8859-1 声明，AVFoundation 会按 Latin-1 解出乱码。
    // 同一文件的标题/歌手/专辑通常同源，合起来投票比逐字段猜测更稳。
    private static func repairLegacyEncoding(_ fields: [TextField: String]) -> [TextField: String] {
        var decodings: [TextField: FieldDecoding] = [:]
        var gbTotal = 0
        var big5Total = 0

        for (field, raw) in fields {
            guard let mangled = mangledLatin1Bytes(raw) else { continue }
            let decoded = decodeCandidates(mangled)
            guard decoded.gb != nil || decoded.big5 != nil else { continue }
            decodings[field] = decoded
            gbTotal += decoded.gb?.score ?? 0
            big5Total += decoded.big5?.score ?? 0
        }

        guard !decodings.isEmpty else { return fields }

        // 平票时按整张文件的倾向决定：简体曲库占绝对多数，再平票按 GBK
        let preferGB = gbTotal >= big5Total
        var repaired = fields

        for (field, decoding) in decodings {
            var chosen: Candidate?
            switch (decoding.gb, decoding.big5) {
            case let (g?, b?):
                if g.score == b.score {
                    chosen = preferGB ? g : b
                } else {
                    chosen = g.score > b.score ? g : b
                }
            case let (g?, nil):
                chosen = g
            case let (nil, b?):
                chosen = b
            case (nil, nil):
                chosen = nil
            }

            // 少数老标签同一字段里混用 GBK 和 Big5，逐对解码能还原，且只在更优时才采用
            if let hybrid = hybridDecode(decoding.mangled, preferGB: preferGB) {
                let hybridScore = commonScore(hybrid, common: mergedCommonCharacters)
                let pureScore = chosen.map { commonScore($0.text, common: mergedCommonCharacters) }
                if hybridScore > (pureScore ?? Int.min) {
                    chosen = Candidate(text: hybrid, score: hybridScore)
                }
            }

            if let chosen {
                repaired[field] = chosen.text
            }
        }
        return repaired
    }

    private struct FieldDecoding {
        let mangled: Data
        let suspiciousRatio: Double
        let gb: Candidate?
        let big5: Candidate?
    }

    private struct Candidate {
        let text: String
        let score: Int
    }

    private static func mangledLatin1Bytes(_ raw: String) -> (bytes: Data, suspiciousRatio: Double)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty, !containsCJK(text) else { return nil }

        let suspicious = scalars.filter { (0x00A0...0x00FF).contains($0.value) }.count
        let ratio = Double(suspicious) / Double(scalars.count)
        guard suspicious >= 2, ratio >= 0.25 || suspicious >= 4,
              let bytes = text.data(using: .isoLatin1) else { return nil }
        return (bytes, ratio)
    }

    private static func decodeCandidates(_ mangled: (bytes: Data, suspiciousRatio: Double)) -> FieldDecoding {
        let bytes = mangled.bytes
        var gb: Candidate?
        var big5Candidate: Candidate?

        // ID3v1 的固定长度字段会把多字节字符截断，整段解码失败时从尾部逐个去掉重试
        for trim in 0...3 where bytes.count - trim >= 2 {
            var slice = bytes.prefix(bytes.count - trim)
            while let last = slice.last, last == 0x00 || last == 0x20 {
                slice = slice.dropLast()
            }
            let chunk = Data(slice)

            if gb == nil,
               let text = String(data: chunk, encoding: gb18030) {
                let score = commonScore(text, common: gbCommonCharacters)
                if isPlausible(text, score: score, ratio: mangled.suspiciousRatio) {
                    gb = Candidate(text: text, score: score)
                }
            }
            if big5Candidate == nil,
               let text = String(data: chunk, encoding: big5) {
                let score = commonScore(text, common: big5CommonCharacters)
                if isPlausible(text, score: score, ratio: mangled.suspiciousRatio) {
                    big5Candidate = Candidate(text: text, score: score)
                }
            }
            if gb != nil, big5Candidate != nil {
                break
            }
        }

        return FieldDecoding(mangled: bytes, suspiciousRatio: mangled.suspiciousRatio, gb: gb, big5: big5Candidate)
    }

    private static func hybridDecode(_ bytes: Data, preferGB: Bool) -> String? {
        var result = ""
        var pendingPairs: [Data] = []
        var index = 0
        var decodedAnything = false

        func choose(_ pair: Data, preferGB: Bool) -> String? {
            let gbText = String(data: pair, encoding: gb18030)
            let big5Text = String(data: pair, encoding: big5)
            let gbScore = gbText.map { commonScore($0, common: gbCommonCharacters) } ?? Int.min
            let big5Score = big5Text.map { commonScore($0, common: big5CommonCharacters) } ?? Int.min
            if gbScore == Int.min, big5Score == Int.min { return nil }
            let useGB = gbScore == big5Score ? preferGB : gbScore > big5Score
            return useGB ? gbText : big5Text
        }

        func flushRun() {
            guard !pendingPairs.isEmpty else { return }
            let runBytes = pendingPairs.reduce(into: Data()) { $0.append($1) }
            let gbText = String(data: runBytes, encoding: gb18030)
            let big5Text = String(data: runBytes, encoding: big5)
            let gbScore = gbText.map { commonScore($0, common: gbCommonCharacters) } ?? Int.min
            let big5Score = big5Text.map { commonScore($0, common: big5CommonCharacters) } ?? Int.min

            var text: String?
            if gbScore == Int.min, big5Score == Int.min {
                text = pendingPairs.compactMap { choose($0, preferGB: preferGB) }.joined()
            } else {
                let useGB = gbScore == big5Score ? preferGB : gbScore > big5Score
                text = useGB ? gbText : big5Text
            }
            if let text {
                result += text.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) && $0.value != 0xFFFD }
                    .map(String.init)
                    .joined()
                decodedAnything = true
            }
            pendingPairs.removeAll()
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                flushRun()
                result.append(Character(UnicodeScalar(byte)))
                index += 1
                continue
            }
            guard index + 1 < bytes.count else { break }
            pendingPairs.append(Data(bytes[index..<index + 2]))
            index += 2
        }
        flushRun()

        return decodedAnything ? result : nil
    }

    private static func isPlausible(_ text: String, score: Int, ratio: Double) -> Bool {
        let cjk = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value)
        }.count
        if cjk >= 2 { return score >= 3 }
        return cjk >= 1 && (ratio >= 0.4 || score >= 2)
    }

    // 命中各自编码的一级常用字库加分，生僻字和乱码符号减分
    private static func commonScore(_ text: String, common: Set<Unicode.Scalar>) -> Int {
        var total = 0
        for scalar in text.unicodeScalars {
            if common.contains(scalar) {
                total += 2
            } else {
                switch scalar.value {
                case 0x3040...0x30FF:
                    total += 4
                case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                    total -= 1
                case 0x00B7, 0x2000...0x206F, 0x2150...0x218F, 0x3100...0x312F,
                     0x3000...0x303F, 0xFF00...0xFFEF, 0x0...0x7F:
                    break
                default:
                    total -= 3
                }
            }
        }
        return total
    }

    private static let gbCommonCharacters: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for lead in 0xB0...0xF7 {
            for trail in 0xA1...0xFE {
                if let text = String(data: Data([UInt8(lead), UInt8(trail)]), encoding: gb18030),
                   let scalar = text.unicodeScalars.first {
                    set.insert(scalar)
                }
            }
        }
        return set
    }()

    private static let big5CommonCharacters: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for lead in 0xA4...0xC6 {
            for trail in Array(0x40...0x7E) + Array(0xA1...0xFE) {
                if let text = String(data: Data([UInt8(lead), UInt8(trail)]), encoding: big5),
                   let scalar = text.unicodeScalars.first {
                    set.insert(scalar)
                }
            }
        }
        return set
    }()

    private static let mergedCommonCharacters: Set<Unicode.Scalar> = gbCommonCharacters.union(big5CommonCharacters)

    private static var gb18030: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
    }

    private static var big5: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )
    }

    private static func isURLLike(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("http://")
            || lower.contains("https://")
            || lower.contains("www.")
            || lower.hasSuffix(".com")
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    static func artworkData(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) {
                return data
            }
        }
        return nil
    }
}
