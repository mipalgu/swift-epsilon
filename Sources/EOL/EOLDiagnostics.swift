//
//  EOLDiagnostics.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The stable codes of the diagnostics that the Epsilon languages report.
///
/// Each code is a dotted identifier that tools can match on without depending on
/// the wording of a message. The dialects (EVL, ETL, EGL) report their own
/// problems with these codes as well, so that a front end needs to know only one
/// set of identifiers.
public enum EOLDiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A character cannot start any token.
    case unexpectedCharacter = "eol.unexpectedCharacter"
    /// A string literal has no closing quote.
    case unterminatedString = "eol.unterminatedString"
    /// A block comment has no closing delimiter.
    case unterminatedComment = "eol.unterminatedComment"
    /// A numeric literal cannot be read.
    case invalidNumber = "eol.invalidNumber"
    /// A token appears where the grammar does not allow it.
    case unexpectedToken = "eol.unexpectedToken"
    /// A construct of the language is recognised but not supported.
    case unsupportedConstruct = "eol.unsupportedConstruct"
    /// Java interoperability (`Native`) was requested, which is not available.
    case nativeUnsupported = "eol.nativeUnsupported"
    /// An imported module cannot be found or read.
    case importFailed = "eol.importFailed"
    /// A variable or type name cannot be resolved.
    case unresolvedName = "eol.unresolvedName"
    /// A model or model type cannot be resolved.
    case unresolvedType = "eol.unresolvedType"
    /// A property does not exist on a value.
    case unknownProperty = "eol.unknownProperty"
    /// An operation does not exist on a value.
    case unknownOperation = "eol.unknownOperation"
    /// A value has the wrong type for an operation.
    case typeMismatch = "eol.typeMismatch"
    /// A feature was called on the undefined value.
    case undefinedReceiver = "eol.undefinedReceiver"
    /// An arithmetic error such as division by zero.
    case arithmetic = "eol.arithmetic"
    /// An index is outside the bounds of a collection.
    case indexOutOfBounds = "eol.indexOutOfBounds"
    /// A `throw` statement raised a user error.
    case userError = "eol.userError"
    /// A `$pre` or `$post` annotation did not hold.
    case contractViolation = "eol.contractViolation"
    /// A model could not be modified as requested.
    case modelUpdate = "eol.modelUpdate"
    /// A template or rule references a file that cannot be read or written.
    case fileAccess = "eol.fileAccess"
    /// A rule, constraint or other named declaration is referenced but not declared.
    case unknownDeclaration = "eol.unknownDeclaration"
    /// A declaration is malformed or inconsistent.
    case invalidDeclaration = "eol.invalidDeclaration"
    /// The task running the program was cancelled.
    case cancelled = "eol.cancelled"
}

/// An error raised while parsing or running an Epsilon program.
///
/// The error carries a `SourceDiagnostic` with a stable code, a message and,
/// when known, the source range of the construct that failed, so that a caller
/// can report it in the same form as a parse diagnostic.
public struct EOLError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    /// The diagnostic that describes the error.
    public var diagnostic: SourceDiagnostic

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The source text that failed, if known.
    ///   - document: The document the range refers to, if known.
    public init(
        _ code: EOLDiagnosticCode, _ message: String, range: SourceRange? = nil, document: String? = nil
    ) {
        diagnostic = SourceDiagnostic(
            severity: .error, code: code.rawValue, message: message, range: range, document: document)
    }

    /// Creates an error from an existing diagnostic.
    ///
    /// - Parameter diagnostic: The diagnostic to wrap.
    public init(diagnostic: SourceDiagnostic) {
        self.diagnostic = diagnostic
    }

    /// The code of the problem.
    public var code: String { diagnostic.code }

    /// The human-readable description of the problem.
    public var message: String { diagnostic.message }

    /// The source range of the problem, if known.
    public var range: SourceRange? { diagnostic.range }

    /// A description that includes the line and column, when known.
    public var description: String {
        guard let range = diagnostic.range else { return diagnostic.message }
        let place = "\(range.start.line):\(range.start.column)"
        if let document = diagnostic.document { return "\(document):\(place): \(diagnostic.message)" }
        return "\(place): \(diagnostic.message)"
    }

    /// The description, for `LocalizedError`.
    public var errorDescription: String? { description }

    /// Returns a copy of the error that is located at a range if it has no range yet.
    ///
    /// - Parameters:
    ///   - range: The range to attach.
    ///   - document: The document to attach if none is set.
    /// - Returns: The located error.
    func located(at range: SourceRange?, document: String?) -> EOLError {
        var copy = self
        if copy.diagnostic.range == nil { copy.diagnostic.range = range }
        if copy.diagnostic.document == nil { copy.diagnostic.document = document }
        return copy
    }
}

/// The kinds of outline node that the Epsilon parsers produce.
public enum EOLOutlineKind {
    /// An EOL operation.
    public static let operation = "operation"
    /// An import declaration.
    public static let `import` = "import"
    /// A `pre` block.
    public static let pre = "pre"
    /// A `post` block.
    public static let post = "post"
    /// An EVL context.
    public static let context = "context"
    /// An EVL constraint.
    public static let constraint = "constraint"
    /// An EVL critique.
    public static let critique = "critique"
    /// An ETL or EGX rule.
    public static let rule = "rule"
}
