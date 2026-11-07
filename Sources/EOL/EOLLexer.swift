//
//  EOLLexer.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The kind of a lexical token and its decoded value.
package enum EOLTokenKind: Equatable, Sendable {
    /// A name; `quoted` is `true` for a back-quoted name, which is never a keyword.
    case identifier(String, quoted: Bool)
    /// A string literal with its escapes decoded.
    case string(String)
    /// An integer literal.
    case integer(Int)
    /// A real literal.
    case real(Double)
    /// An operator or punctuation symbol.
    case symbol(String)
    /// Static text of a template.
    case templateText(String)
    /// The start of a template output section, `[%=`.
    case templateOutput
    /// The end of a template code or output section, `%]`.
    case templateClose
    /// The end of the input.
    case endOfInput
}

/// A lexical token with its source range.
package struct EOLToken: Sendable, Equatable {
    /// The kind of token and its decoded value.
    package var kind: EOLTokenKind

    /// The source range the token covers.
    package var range: SourceRange

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: The kind of token.
    ///   - range: The source range the token covers.
    package init(kind: EOLTokenKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }

    /// The name of an unquoted identifier token, or `nil`.
    package var bareName: String? {
        if case .identifier(let name, false) = kind { return name }
        return nil
    }

    /// The name of any identifier token, quoted or not, or `nil`.
    package var name: String? {
        if case .identifier(let name, _) = kind { return name }
        return nil
    }

    /// The symbol text of a symbol token, or `nil`.
    package var symbol: String? {
        if case .symbol(let symbol) = kind { return symbol }
        return nil
    }

    /// Whether the token is the given unquoted keyword or contextual word.
    ///
    /// - Parameter word: The word to compare with.
    /// - Returns: `true` if the token is an unquoted identifier spelt `word`.
    package func isWord(_ word: String) -> Bool { bareName == word }

    /// Whether the token is the given symbol.
    ///
    /// - Parameter text: The symbol to compare with.
    /// - Returns: `true` if the token is the symbol `text`.
    package func isSymbol(_ text: String) -> Bool { symbol == text }
}

/// The result of scanning source text.
package struct EOLScan: Sendable {
    /// The tokens that the parser reads, ending with an end-of-input token.
    package var tokens: [EOLToken] = []

    /// The ranges of comments, in source order.
    package var comments: [SourceRange] = []

    /// The lexical problems, in source order.
    package var diagnostics: [SourceDiagnostic] = []
}

/// A hand-written lexer for EOL and its template dialect.
///
/// The lexer reads UTF-8 bytes and reports one-based lines and columns through a
/// `LineTable`. In template mode it splits the text into static text, code
/// sections `[% … %]`, output sections `[%= … %]` and comments `[* … *]`, and
/// removes the indentation and line break around a code section or comment that
/// stands alone on its line.
package struct EOLLexer {
    /// The bytes of the source text.
    private let bytes: [UInt8]

    /// The line table of the source text.
    private let lines: LineTable

    /// The document the diagnostics refer to.
    private let document: String?

    /// The scan being built.
    private var scan = EOLScan()

    /// Creates a lexer.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document the diagnostics refer to.
    package init(_ text: String, document: String? = nil) {
        bytes = Array(text.utf8)
        lines = LineTable(text)
        self.document = document
    }

    /// Scans EOL source text.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document the diagnostics refer to.
    /// - Returns: The tokens, comments and lexical problems.
    package static func scan(_ text: String, document: String? = nil) -> EOLScan {
        var lexer = EOLLexer(text, document: document)
        _ = lexer.scanCode(from: 0, inTemplate: false)
        lexer.appendEnd()
        return lexer.scan
    }

    /// Scans template source text (EGL).
    ///
    /// - Parameters:
    ///   - text: The template text.
    ///   - document: The document the diagnostics refer to.
    /// - Returns: The tokens, comments and lexical problems.
    package static func scanTemplate(_ text: String, document: String? = nil) -> EOLScan {
        var lexer = EOLLexer(text, document: document)
        lexer.scanTemplateSegments()
        lexer.appendEnd()
        return lexer.scan
    }

    // MARK: - Templates

    /// A section of a template.
    private enum Segment {
        /// Static text between two offsets.
        case text(Int, Int)
        /// A code section; the offsets cover the text after `[%`.
        case code(Int)
        /// An output section; the offsets cover the text after `[%=`.
        case output(Int, Int)
        /// A comment between two offsets (including its delimiters).
        case comment(Int, Int)
    }

    /// Splits the template into segments and scans each one.
    private mutating func scanTemplateSegments() {
        var segments: [(segment: Segment, end: Int)] = []
        var index = 0
        var textStart = 0
        while index < bytes.count {
            if byte(index) == UInt8(ascii: "["), byte(index + 1) == UInt8(ascii: "%") {
                if textStart < index { segments.append((.text(textStart, index), index)) }
                let isOutput = byte(index + 2) == UInt8(ascii: "=")
                let codeStart = index + (isOutput ? 3 : 2)
                if isOutput {
                    segments.append((.output(index, codeStart), codeStart))
                } else {
                    segments.append((.code(codeStart), codeStart))
                }
                index = skipCode(from: codeStart)
                segments[segments.count - 1].end = index
                textStart = index
            } else if byte(index) == UInt8(ascii: "["), byte(index + 1) == UInt8(ascii: "*") {
                if textStart < index { segments.append((.text(textStart, index), index)) }
                var end = index + 2
                while end < bytes.count, !(byte(end) == UInt8(ascii: "*") && byte(end + 1) == UInt8(ascii: "]")) {
                    end += 1
                }
                end = min(bytes.count, end + 2)
                segments.append((.comment(index, end), end))
                index = end
                textStart = index
            } else {
                index += 1
            }
        }
        if textStart < bytes.count { segments.append((.text(textStart, bytes.count), bytes.count)) }

        var trims = segments.map { segment -> (start: Int, end: Int) in
            if case .text(let start, let end) = segment.segment { return (start, end) }
            return (0, 0)
        }
        for (position, entry) in segments.enumerated() {
            switch entry.segment {
            case .code, .comment: break
            default: continue
            }
            let previous = position > 0 ? segments[position - 1].segment : nil
            let next = position + 1 < segments.count ? segments[position + 1].segment : nil
            var leading: Int?
            switch previous {
            case nil: leading = nil
            case .text(let start, let end)?:
                guard let lineStart = lineStartIfBlank(from: start, to: end, isFirst: position == 1) else { continue }
                leading = lineStart
            default: continue
            }
            var trailing: Int?
            switch next {
            case nil: trailing = nil
            case .text(let start, let end)?:
                guard let lineEnd = lineEndIfBlank(from: start, to: end, isLast: position + 2 == segments.count) else {
                    continue
                }
                trailing = lineEnd
            default: continue
            }
            if let leading { trims[position - 1].end = leading }
            if let trailing { trims[position + 1].start = trailing }
        }

        for (position, entry) in segments.enumerated() {
            switch entry.segment {
            case .text:
                let (start, end) = trims[position]
                if start < end {
                    let text = String(decoding: bytes[start..<end], as: UTF8.self)
                    scan.tokens.append(EOLToken(kind: .templateText(text), range: lines.range(fromUTF8Offset: start, to: end)))
                }
            case .code(let start):
                _ = scanCode(from: start, inTemplate: true)
            case .output(let start, let codeStart):
                scan.tokens.append(EOLToken(kind: .templateOutput, range: lines.range(fromUTF8Offset: start, to: codeStart)))
                _ = scanCode(from: codeStart, inTemplate: true)
            case .comment(let start, let end):
                scan.comments.append(lines.range(fromUTF8Offset: start, to: end))
            }
        }
    }

    /// Finds where the indentation before a standalone section starts.
    ///
    /// - Parameters:
    ///   - start: The start of the preceding text.
    ///   - end: The end of the preceding text.
    ///   - isFirst: Whether the text starts the template.
    /// - Returns: The offset after the last line break, or `nil` if the text before the
    ///   section on its line is not blank.
    private func lineStartIfBlank(from start: Int, to end: Int, isFirst: Bool) -> Int? {
        var index = end
        while index > start {
            let value = bytes[index - 1]
            if value == UInt8(ascii: "\n") { return index }
            guard value == UInt8(ascii: " ") || value == UInt8(ascii: "\t") else { return nil }
            index -= 1
        }
        return isFirst ? start : nil
    }

    /// Finds where the blank remainder of the line after a standalone section ends.
    ///
    /// - Parameters:
    ///   - start: The start of the following text.
    ///   - end: The end of the following text.
    ///   - isLast: Whether the text ends the template.
    /// - Returns: The offset after the first line break, or `nil` if the remainder of
    ///   the line is not blank.
    private func lineEndIfBlank(from start: Int, to end: Int, isLast: Bool) -> Int? {
        var index = start
        while index < end {
            let value = bytes[index]
            if value == UInt8(ascii: "\n") { return index + 1 }
            if value == UInt8(ascii: "\r"), index + 1 < end, bytes[index + 1] == UInt8(ascii: "\n") {
                return index + 2
            }
            guard value == UInt8(ascii: " ") || value == UInt8(ascii: "\t") else { return nil }
            index += 1
        }
        return isLast ? end : nil
    }

    /// Skips the code of a template section up to and including its closing `%]`.
    ///
    /// - Parameter start: The offset after the opening delimiter.
    /// - Returns: The offset after the closing delimiter, or the end of the text.
    private func skipCode(from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            let value = bytes[index]
            if value == UInt8(ascii: "%"), byte(index + 1) == UInt8(ascii: "]") { return index + 2 }
            if EOLLanguage.Lexical.quotes.contains(Character(UnicodeScalar(value))) {
                index = skipString(from: index)
                continue
            }
            if value == UInt8(ascii: "/"), byte(index + 1) == UInt8(ascii: "/") {
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n") {
                    if bytes[index] == UInt8(ascii: "%"), byte(index + 1) == UInt8(ascii: "]") { return index + 2 }
                    index += 1
                }
                continue
            }
            if value == UInt8(ascii: "/"), byte(index + 1) == UInt8(ascii: "*") {
                index += 2
                while index < bytes.count, !(bytes[index] == UInt8(ascii: "*") && byte(index + 1) == UInt8(ascii: "/")) {
                    index += 1
                }
                index += 2
                continue
            }
            index += 1
        }
        return bytes.count
    }

    /// Skips a string literal.
    ///
    /// - Parameter start: The offset of the opening quote.
    /// - Returns: The offset after the closing quote, or the end of the line.
    private func skipString(from start: Int) -> Int {
        let quote = bytes[start]
        var index = start + 1
        while index < bytes.count {
            let value = bytes[index]
            if value == UInt8(ascii: "\\") {
                index += 2
                continue
            }
            if value == quote { return index + 1 }
            if value == UInt8(ascii: "\n") { return index }
            index += 1
        }
        return index
    }

    // MARK: - Code

    /// Scans code from an offset.
    ///
    /// - Parameters:
    ///   - start: The offset to start at.
    ///   - inTemplate: Whether `%]` ends the code.
    /// - Returns: The offset after the scanned code.
    private mutating func scanCode(from start: Int, inTemplate: Bool) -> Int {
        var index = start
        while index < bytes.count {
            let value = bytes[index]
            if value == UInt8(ascii: " ") || value == UInt8(ascii: "\t") || value == UInt8(ascii: "\n")
                || value == UInt8(ascii: "\r")
            {
                index += 1
                continue
            }
            if inTemplate, value == UInt8(ascii: "%"), byte(index + 1) == UInt8(ascii: "]") {
                scan.tokens.append(EOLToken(kind: .templateClose, range: range(index, index + 2)))
                return index + 2
            }
            if inTemplate, value == UInt8(ascii: "-"), byte(index + 1) == UInt8(ascii: "%"),
                byte(index + 2) == UInt8(ascii: "]")
            {
                scan.tokens.append(EOLToken(kind: .templateClose, range: range(index, index + 3)))
                return index + 3
            }
            if value == UInt8(ascii: "/"), byte(index + 1) == UInt8(ascii: "/") {
                let end = lineCommentEnd(from: index, inTemplate: inTemplate)
                scan.comments.append(range(index, end))
                index = end
                continue
            }
            if value == UInt8(ascii: "/"), byte(index + 1) == UInt8(ascii: "*") {
                var end = index + 2
                while end < bytes.count, !(bytes[end] == UInt8(ascii: "*") && byte(end + 1) == UInt8(ascii: "/")) {
                    end += 1
                }
                if end >= bytes.count {
                    report(.unterminatedComment, "Block comment is not terminated", index, bytes.count)
                    scan.comments.append(range(index, bytes.count))
                    return bytes.count
                }
                scan.comments.append(range(index, end + 2))
                index = end + 2
                continue
            }
            if isIdentifierStart(value) {
                index = scanIdentifier(from: index)
                continue
            }
            if value == UInt8(ascii: "`") {
                index = scanQuotedIdentifier(from: index)
                continue
            }
            if isDigit(value) {
                index = scanNumber(from: index)
                continue
            }
            if value == UInt8(ascii: "\"") || value == UInt8(ascii: "'") {
                index = scanString(from: index)
                continue
            }
            if let (symbol, length) = matchSymbol(at: index) {
                scan.tokens.append(EOLToken(kind: .symbol(symbol), range: range(index, index + length)))
                index += length
                continue
            }
            let end = scalarEnd(from: index)
            let text = String(decoding: bytes[index..<end], as: UTF8.self)
            report(.unexpectedCharacter, "Unexpected character '\(text)'", index, end)
            index = end
        }
        return index
    }

    /// Finds the end of a line comment.
    private func lineCommentEnd(from start: Int, inTemplate: Bool) -> Int {
        var end = start
        while end < bytes.count, bytes[end] != UInt8(ascii: "\n") {
            if inTemplate, bytes[end] == UInt8(ascii: "%"), byte(end + 1) == UInt8(ascii: "]") { break }
            end += 1
        }
        return end
    }

    /// Appends the end-of-input token.
    private mutating func appendEnd() {
        scan.tokens.append(EOLToken(kind: .endOfInput, range: range(bytes.count, bytes.count)))
    }

    /// Scans an identifier.
    private mutating func scanIdentifier(from start: Int) -> Int {
        var index = start
        while index < bytes.count, isIdentifierPart(bytes[index]) { index += 1 }
        let name = String(decoding: bytes[start..<index], as: UTF8.self)
        scan.tokens.append(EOLToken(kind: .identifier(name, quoted: false), range: range(start, index)))
        return index
    }

    /// Scans a back-quoted identifier.
    private mutating func scanQuotedIdentifier(from start: Int) -> Int {
        var index = start + 1
        while index < bytes.count, bytes[index] != UInt8(ascii: "`"), bytes[index] != UInt8(ascii: "\n") {
            index += 1
        }
        let name = String(decoding: bytes[(start + 1)..<index], as: UTF8.self)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "`") else {
            report(.unexpectedCharacter, "Quoted name is not terminated", start, index)
            return index
        }
        scan.tokens.append(EOLToken(kind: .identifier(name, quoted: true), range: range(start, index + 1)))
        return index + 1
    }

    /// Scans a numeric literal.
    private mutating func scanNumber(from start: Int) -> Int {
        var index = start
        while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        var isReal = false
        if byte(index) == UInt8(ascii: "."), let next = optionalByte(index + 1), isDigit(next) {
            isReal = true
            index += 1
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if let marker = optionalByte(index), marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            var exponent = index + 1
            if let sign = optionalByte(exponent), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                exponent += 1
            }
            if let digit = optionalByte(exponent), isDigit(digit) {
                isReal = true
                index = exponent
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
        }
        let digits = String(decoding: bytes[start..<index], as: UTF8.self)
        if let suffix = optionalByte(index).map({ Character(UnicodeScalar($0)) }) {
            if EOLLanguage.Lexical.realSuffixes.contains(suffix) {
                isReal = true
                index += 1
            } else if EOLLanguage.Lexical.longSuffixes.contains(suffix) {
                index += 1
            }
        }
        if isReal {
            guard let value = Double(digits) else {
                report(.invalidNumber, "Invalid real literal '\(digits)'", start, index)
                return index
            }
            scan.tokens.append(EOLToken(kind: .real(value), range: range(start, index)))
        } else {
            guard let value = Int(digits) else {
                report(.invalidNumber, "Integer literal '\(digits)' is out of range", start, index)
                return index
            }
            scan.tokens.append(EOLToken(kind: .integer(value), range: range(start, index)))
        }
        return index
    }

    /// Scans a string literal, decoding its escapes.
    private mutating func scanString(from start: Int) -> Int {
        let quote = bytes[start]
        var index = start + 1
        var raw: [UInt8] = []
        while index < bytes.count {
            let value = bytes[index]
            if value == quote {
                let text = Self.decodeEscapes(String(decoding: raw, as: UTF8.self))
                scan.tokens.append(EOLToken(kind: .string(text), range: range(start, index + 1)))
                return index + 1
            }
            if value == UInt8(ascii: "\\"), index + 1 < bytes.count {
                raw.append(value)
                raw.append(bytes[index + 1])
                index += 2
                continue
            }
            raw.append(value)
            index += 1
        }
        report(.unterminatedString, "String literal is not terminated", start, index)
        let text = Self.decodeEscapes(String(decoding: raw, as: UTF8.self))
        scan.tokens.append(EOLToken(kind: .string(text), range: range(start, index)))
        return index
    }

    /// Decodes the escape sequences of a string literal.
    ///
    /// Recognised sequences are the single-character escapes, and `\uXXXX` with four
    /// hexadecimal digits. Any other escaped character is kept with its backslash, so
    /// that regular expressions such as `\s+` survive unchanged.
    ///
    /// - Parameter raw: The text between the quotes.
    /// - Returns: The decoded text.
    package static func decodeEscapes(_ raw: String) -> String {
        guard raw.contains(EOLLanguage.Lexical.escape) else { return raw }
        var result = ""
        let characters = Array(raw)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == EOLLanguage.Lexical.escape, index + 1 < characters.count else {
                result.append(character)
                index += 1
                continue
            }
            let escaped = characters[index + 1]
            if let simple = EOLLanguage.Lexical.simpleEscapes[escaped] {
                result.append(simple)
                index += 2
            } else if escaped == "u", index + 5 < characters.count,
                let value = UInt32(String(characters[(index + 2)...(index + 5)]), radix: 16),
                let scalar = Unicode.Scalar(value)
            {
                result.unicodeScalars.append(scalar)
                index += 6
            } else {
                result.append(character)
                result.append(escaped)
                index += 2
            }
        }
        return result
    }

    /// Matches the longest operator or punctuation symbol at an offset.
    private func matchSymbol(at index: Int) -> (String, Int)? {
        for symbol in EOLLanguage.Symbol.multiCharacter {
            let utf8 = Array(symbol.utf8)
            if index + utf8.count <= bytes.count, Array(bytes[index..<(index + utf8.count)]) == utf8 {
                return (symbol, utf8.count)
            }
        }
        let character = Character(UnicodeScalar(bytes[index]))
        if EOLLanguage.Symbol.singleCharacter.contains(character) { return (String(character), 1) }
        return nil
    }

    // MARK: - Helpers

    /// The byte at an offset, or zero past the end.
    ///
    /// - Parameter index: The offset.
    /// - Returns: The byte.
    private func byte(_ index: Int) -> UInt8 { index < bytes.count ? bytes[index] : 0 }

    /// The byte at an offset, or `nil` past the end.
    ///
    /// - Parameter index: The offset.
    /// - Returns: The byte, if any.
    private func optionalByte(_ index: Int) -> UInt8? { index < bytes.count ? bytes[index] : nil }

    /// Whether a byte is an ASCII digit.
    ///
    /// - Parameter value: The byte.
    /// - Returns: `true` for `0` to `9`.
    private func isDigit(_ value: UInt8) -> Bool { value >= UInt8(ascii: "0") && value <= UInt8(ascii: "9") }

    /// Whether a byte can start a name.
    ///
    /// Letters, the underscore and the bytes of non-ASCII characters start names.
    ///
    /// - Parameter value: The byte.
    /// - Returns: `true` if the byte can start a name.
    private func isIdentifierStart(_ value: UInt8) -> Bool {
        (value >= UInt8(ascii: "a") && value <= UInt8(ascii: "z"))
            || (value >= UInt8(ascii: "A") && value <= UInt8(ascii: "Z")) || value == UInt8(ascii: "_")
            || value >= 0x80
    }

    /// Whether a byte can continue a name.
    ///
    /// - Parameter value: The byte.
    /// - Returns: `true` if the byte can continue a name.
    private func isIdentifierPart(_ value: UInt8) -> Bool { isIdentifierStart(value) || isDigit(value) }

    /// The offset after the Unicode scalar that starts at an offset.
    ///
    /// - Parameter index: The offset of the scalar's first byte.
    /// - Returns: The offset after its last byte.
    private func scalarEnd(from index: Int) -> Int {
        var end = index + 1
        while end < bytes.count, bytes[end] & 0xC0 == 0x80 { end += 1 }
        return end
    }

    /// The source range between two offsets.
    ///
    /// - Parameters:
    ///   - start: The start offset.
    ///   - end: The end offset.
    /// - Returns: The range with lines and columns.
    private func range(_ start: Int, _ end: Int) -> SourceRange { lines.range(fromUTF8Offset: start, to: end) }

    /// Records a lexical problem.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: The message.
    ///   - start: The start offset.
    ///   - end: The end offset.
    private mutating func report(_ code: EOLDiagnosticCode, _ message: String, _ start: Int, _ end: Int) {
        scan.diagnostics.append(
            SourceDiagnostic(
                severity: .error, code: code.rawValue, message: message, range: range(start, end), document: document))
    }
}
