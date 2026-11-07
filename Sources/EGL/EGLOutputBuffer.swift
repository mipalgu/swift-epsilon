//
//  EGLOutputBuffer.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EOL

/// The output buffer of a running template, available to it as `out`.
///
/// Static text and output sections are appended to the buffer, and the template
/// can append further text with `out.print(…)` and `out.println(…)`, remove text
/// with `out.chop(n)`, and produce protected region markers with
/// `out.preserve(…)`, `out.startPreserve(…)` and `out.stopPreserve()`.
///
/// The buffer keeps a stack of captures, so that a `@template` operation can
/// collect the text it produces and return it instead of appending it.
public final class EGLOutputBuffer: EOLHostObject, EOLOutputStream {
    /// The text of the outermost capture and of each nested capture.
    private var captures: [String] = [""]

    /// The comment style that protected regions use, set with `setContentType`.
    public private(set) var commentStyle: EGLLanguage.CommentStyle?

    /// The regions started with `startPreserve` and not yet stopped.
    private var openRegions: [(id: String, style: EGLLanguage.CommentStyle)] = []

    /// Creates an empty buffer.
    public init() {}

    /// The text written so far to the current capture.
    public var text: String { captures[captures.count - 1] }

    /// The type name shown for the buffer.
    public var typeName: String { "OutputBuffer" }

    /// Appends text to the current capture.
    ///
    /// - Parameter text: The text.
    public func write(_ text: String) { captures[captures.count - 1] += text }

    /// Starts collecting text separately from the enclosing output.
    public func beginCapture() { captures.append("") }

    /// Stops collecting text and returns what was collected.
    ///
    /// - Returns: The collected text.
    public func endCapture() -> String {
        guard captures.count > 1 else { return text }
        return captures.removeLast()
    }

    /// The buffer has no readable properties.
    ///
    /// - Parameter name: The property name.
    /// - Returns: `nil`.
    public func property(_ name: String) -> EOLValue? { nil }

    /// Calls an operation of the buffer.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - arguments: The evaluated arguments.
    ///   - interpreter: The interpreter, used to render values as text.
    /// - Returns: The result, or `nil` if the buffer has no such operation.
    /// - Throws: `EOLError` if the arguments are invalid.
    public func call(_ name: String, arguments: [EOLValue], interpreter: EOLInterpreter) async throws -> EOLValue? {
        typealias O = EGLLanguage.Operation
        switch (name, arguments.count) {
        case (O.print, 1):
            write(await interpreter.string(of: arguments[0]))
            return .undefined
        case (O.println, 0):
            write("\n")
            return .undefined
        case (O.println, 1):
            write(await interpreter.string(of: arguments[0]) + "\n")
            return .undefined
        case (O.chop, 1):
            guard let count = arguments[0].integerValue, count >= 0 else {
                throw EOLError(.typeMismatch, "'chop' expects a non-negative integer")
            }
            captures[captures.count - 1] = String(text.dropLast(count))
            return .undefined
        case (O.setContentType, 1):
            guard let type = arguments[0].stringValue, let style = EGLLanguage.contentTypes[type.lowercased()] else {
                throw EOLError(.unknownDeclaration, "Unknown content type '\(arguments[0])'")
            }
            commentStyle = style
            return .undefined
        case (O.preserve, 5):
            let style = EGLLanguage.CommentStyle(start: try string(arguments[0], name), end: try string(arguments[1], name))
            return .string(try region(style, id: arguments[2], enabled: arguments[3], contents: arguments[4], name: name))
        case (O.preserve, 3):
            return .string(try region(try currentStyle(name), id: arguments[0], enabled: arguments[1], contents: arguments[2], name: name))
        case (O.startPreserve, 4):
            let style = EGLLanguage.CommentStyle(start: try string(arguments[0], name), end: try string(arguments[1], name))
            return .string(try startRegion(style, id: arguments[2], enabled: arguments[3], name: name))
        case (O.startPreserve, 2):
            return .string(try startRegion(try currentStyle(name), id: arguments[0], enabled: arguments[1], name: name))
        case (O.stopPreserve, 0):
            guard let open = openRegions.popLast() else {
                throw EOLError(.invalidDeclaration, "'stopPreserve' without a matching 'startPreserve'")
            }
            return .string(EGLProtectedRegions.endMarker(id: open.id, style: open.style))
        default:
            return nil
        }
    }

    /// The comment style set with `setContentType`.
    private func currentStyle(_ name: String) throws -> EGLLanguage.CommentStyle {
        guard let commentStyle else {
            throw EOLError(.invalidDeclaration, "'\(name)' without comment delimiters needs 'setContentType' first")
        }
        return commentStyle
    }

    /// Extracts a string argument.
    private func string(_ value: EOLValue, _ name: String) throws -> String {
        guard let text = value.stringValue else { throw EOLError(.typeMismatch, "'\(name)' expects string arguments") }
        return text
    }

    /// Extracts the identifier and state of a region.
    private func regionHeader(_ id: EOLValue, _ enabled: EOLValue, _ name: String) throws -> (String, Bool) {
        guard let flag = enabled.booleanValue else { throw EOLError(.typeMismatch, "'\(name)' expects a Boolean state") }
        let text: String
        switch id {
        case .string(let value): text = value
        case .integer(let value): text = String(value)
        default: throw EOLError(.typeMismatch, "'\(name)' expects a string identifier")
        }
        return (text, flag)
    }

    /// Produces a complete region.
    private func region(_ style: EGLLanguage.CommentStyle, id: EOLValue, enabled: EOLValue, contents: EOLValue, name: String) throws -> String {
        let (identifier, flag) = try regionHeader(id, enabled, name)
        var body = contents.stringValue ?? ""
        if !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        return EGLProtectedRegions.startMarker(id: identifier, enabled: flag, style: style) + "\n" + body
            + EGLProtectedRegions.endMarker(id: identifier, style: style)
    }

    /// Produces a start marker and remembers the open region.
    private func startRegion(_ style: EGLLanguage.CommentStyle, id: EOLValue, enabled: EOLValue, name: String) throws -> String {
        let (identifier, flag) = try regionHeader(id, enabled, name)
        openRegions.append((identifier, style))
        return EGLProtectedRegions.startMarker(id: identifier, enabled: flag, style: style)
    }
}
