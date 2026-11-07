//
//  EGLProtectedRegions.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// A protected region found in generated or edited text.
public struct EGLProtectedRegion: Sendable, Hashable {
    /// The identifier of the region.
    public var id: String
    /// Whether the region is enabled (`on`), so that its contents survive regeneration.
    public var isEnabled: Bool
    /// The start marker line, including its line break.
    public var startLine: String
    /// The text between the markers, including its final line break.
    public var contents: String
    /// The end marker line, including its line break if it has one.
    public var endLine: String
}

/// Creation, parsing and merging of protected regions.
///
/// A region is delimited by a start marker such as
/// `// protected region anId on begin` and an end marker such as
/// `// protected region anId end`, written in the comment style of the
/// generated language. When a file is regenerated, the contents of each region
/// that is enabled in the existing file are kept, together with its start marker;
/// all other text comes from the newly generated output.
public enum EGLProtectedRegions {
    /// A piece of text that is either ordinary text or a protected region.
    enum Segment {
        /// Ordinary text.
        case text(String)
        /// A protected region.
        case region(EGLProtectedRegion)
    }

    /// The start marker of a region.
    ///
    /// - Parameters:
    ///   - id: The region identifier.
    ///   - enabled: Whether the region is enabled.
    ///   - style: The comment delimiters.
    /// - Returns: The marker, without a line break.
    public static func startMarker(id: String, enabled: Bool, style: EGLLanguage.CommentStyle) -> String {
        typealias R = EGLLanguage.Region
        return marker(style, "\(R.phrase) \(id) \(enabled ? R.on : R.off) \(R.begin)")
    }

    /// The end marker of a region.
    ///
    /// - Parameters:
    ///   - id: The region identifier.
    ///   - style: The comment delimiters.
    /// - Returns: The marker, without a line break.
    public static func endMarker(id: String, style: EGLLanguage.CommentStyle) -> String {
        marker(style, "\(EGLLanguage.Region.phrase) \(id) \(EGLLanguage.Region.end)")
    }

    /// Wraps marker text in comment delimiters.
    private static func marker(_ style: EGLLanguage.CommentStyle, _ text: String) -> String {
        style.start + " " + text + (style.end.isEmpty ? "" : " " + style.end)
    }

    /// Finds the protected regions of a text.
    ///
    /// A start marker without a matching end marker is treated as ordinary text.
    ///
    /// - Parameter text: The text.
    /// - Returns: The regions in order of appearance.
    public static func regions(in text: String) -> [EGLProtectedRegion] {
        segments(of: text).compactMap { segment in
            if case .region(let region) = segment { return region }
            return nil
        }
    }

    /// Splits a text into ordinary text and protected regions.
    ///
    /// - Parameter text: The text.
    /// - Returns: The segments in order.
    static func segments(of text: String) -> [Segment] {
        let lines = splitLines(text)
        var segments: [Segment] = []
        var pending = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let (id, enabled) = startInfo(line),
                let endIndex = lines[(index + 1)...].firstIndex(where: { endID($0) == id })
            {
                if !pending.isEmpty { segments.append(.text(pending)) }
                pending = ""
                let contents = lines[(index + 1)..<endIndex].joined()
                segments.append(
                    .region(EGLProtectedRegion(id: id, isEnabled: enabled, startLine: line, contents: contents, endLine: lines[endIndex])))
                index = endIndex + 1
                continue
            }
            pending += line
            index += 1
        }
        if !pending.isEmpty { segments.append(.text(pending)) }
        return segments
    }

    /// Merges newly generated text with the existing text of a file.
    ///
    /// Each region of the generated text that is enabled in the existing text takes
    /// the existing start marker and contents. Enabled regions of the existing text
    /// with contents that the generated text no longer has are reported as warnings,
    /// because their contents are lost.
    ///
    /// - Parameters:
    ///   - generated: The newly generated text.
    ///   - existing: The current text of the file.
    ///   - document: The document the warnings refer to.
    /// - Returns: The merged text and the warnings.
    public static func merge(generated: String, existing: String, document: String? = nil) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var previous: [String: EGLProtectedRegion] = [:]
        for region in regions(in: existing) where previous[region.id] == nil { previous[region.id] = region }
        var used: Set<String> = []
        var text = ""
        for segment in segments(of: generated) {
            switch segment {
            case .text(let plain):
                text += plain
            case .region(let region):
                used.insert(region.id)
                if let old = previous[region.id], old.isEnabled {
                    text += old.startLine + old.contents + region.endLine
                } else {
                    text += region.startLine + region.contents + region.endLine
                }
            }
        }
        var diagnostics: [SourceDiagnostic] = []
        for region in regions(in: existing) where region.isEnabled && !used.contains(region.id) && !region.contents.isEmpty {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .warning, code: EOLDiagnosticCode.fileAccess.rawValue,
                    message: "Protected region '\(region.id)' is no longer generated; its contents were discarded",
                    document: document))
        }
        return (text, diagnostics)
    }

    /// The identifier and state of a start marker line.
    private static func startInfo(_ line: String) -> (String, Bool)? {
        let words = markerWords(line)
        guard words.count >= 3, words[2] == EGLLanguage.Region.begin,
            words[1] == EGLLanguage.Region.on || words[1] == EGLLanguage.Region.off
        else { return nil }
        return (words[0], words[1] == EGLLanguage.Region.on)
    }

    /// The identifier of an end marker line.
    private static func endID(_ line: String) -> String? {
        let words = markerWords(line)
        guard words.count >= 2, words[1] == EGLLanguage.Region.end else { return nil }
        return words[0]
    }

    /// The words after the marker phrase on a line.
    private static func markerWords(_ line: String) -> [String] {
        guard let range = line.range(of: EGLLanguage.Region.phrase + " ") else { return [] }
        return line[range.upperBound...].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
    }

    /// Splits text into lines that keep their line breaks.
    private static func splitLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "\n" || character == "\r\n" {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
