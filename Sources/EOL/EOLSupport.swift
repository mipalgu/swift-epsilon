//
//  EOLSupport.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// A destination for the text that a program prints.
public protocol EOLOutputStream: AnyObject {
    /// Appends text.
    ///
    /// - Parameter text: The text to append.
    func write(_ text: String)
}

/// An output stream that collects text in memory.
public final class EOLStringOutput: EOLOutputStream {
    /// The text written so far.
    public private(set) var text = ""

    /// Creates an empty output stream.
    public init() {}

    /// Appends text.
    ///
    /// - Parameter text: The text to append.
    public func write(_ text: String) { self.text += text }
}

/// An output stream that writes to the process's standard output or standard error.
public final class EOLStandardOutput: EOLOutputStream {
    /// The file handle written to.
    private let handle: FileHandle

    /// Creates a stream for standard output or standard error.
    ///
    /// - Parameter error: Whether to write to standard error instead of standard output.
    public init(error: Bool = false) {
        handle = error ? FileHandle.standardError : FileHandle.standardOutput
    }

    /// Appends text.
    ///
    /// - Parameter text: The text to append.
    public func write(_ text: String) { handle.write(Data(text.utf8)) }
}

/// Reads the source text of imported modules.
public protocol EOLModuleLoading {
    /// Reads an imported module.
    ///
    /// - Parameters:
    ///   - path: The path as written in the `import` declaration.
    ///   - document: The document that contains the declaration, if known.
    /// - Returns: The source text and the identifier of the imported document.
    /// - Throws: An error if the module cannot be read.
    func load(_ path: String, relativeTo document: String?) throws -> (text: String, document: String)
}

/// Reads imported modules from the file system.
///
/// A relative path is resolved against the directory of the importing document
/// when that document is a file URL or path, and against the current directory
/// otherwise.
public struct EOLFileModuleLoader: EOLModuleLoading {
    /// Creates a file module loader.
    public init() {}

    /// Reads an imported module from a file.
    ///
    /// - Parameters:
    ///   - path: The path as written in the `import` declaration.
    ///   - document: The document that contains the declaration, if known.
    /// - Returns: The source text and the file URL of the imported document.
    /// - Throws: An error if the file cannot be read.
    public func load(_ path: String, relativeTo document: String?) throws -> (text: String, document: String) {
        let url = Self.resolve(path, relativeTo: document)
        let text = try String(contentsOf: url, encoding: .utf8)
        return (text, url.absoluteString)
    }

    /// Resolves an import path to a file URL.
    ///
    /// - Parameters:
    ///   - path: The path as written.
    ///   - document: The importing document.
    /// - Returns: The file URL.
    static func resolve(_ path: String, relativeTo document: String?) -> URL {
        if let url = URL(string: path), url.scheme == "file" { return url }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if let document {
            let base: URL
            if let url = URL(string: document), url.scheme == "file" {
                base = url
            } else {
                base = URL(fileURLWithPath: document)
            }
            return base.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
        }
        return URL(fileURLWithPath: path)
    }
}

/// Reads imported modules from an in-memory table, for tests and embedded use.
public struct EOLInMemoryModuleLoader: EOLModuleLoading {
    /// The source text of each module, by path.
    public var modules: [String: String]

    /// Creates a loader.
    ///
    /// - Parameter modules: The source text of each module, by path.
    public init(_ modules: [String: String]) { self.modules = modules }

    /// Reads a module from the table.
    ///
    /// - Parameters:
    ///   - path: The path as written.
    ///   - document: The importing document (ignored).
    /// - Returns: The source text and the path as the document identifier.
    /// - Throws: ``EOLError`` if the table has no such module.
    public func load(_ path: String, relativeTo document: String?) throws -> (text: String, document: String) {
        guard let text = modules[path] else {
            throw EOLError(.importFailed, "Module '\(path)' not found", document: document)
        }
        return (text, path)
    }
}

/// Behaviour that a dialect such as EVL or ETL adds to the interpreter.
///
/// Extensions are consulted before the built-in operations, so that a dialect
/// can provide operations such as `satisfies` or `equivalent`.
public protocol EOLExtension: AnyObject {
    /// Calls an operation that the dialect provides.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver, or `nil` for a call without a receiver.
    ///   - arguments: The evaluated arguments.
    ///   - interpreter: The interpreter making the call.
    /// - Returns: The result, or `nil` if the dialect does not provide the operation.
    /// - Throws: ``EOLError`` if the operation fails.
    func call(_ name: String, on receiver: EOLValue?, arguments: [EOLValue], interpreter: EOLInterpreter) async throws
        -> EOLValue?

    /// Converts the value of a special assignment (`::=`).
    ///
    /// - Parameters:
    ///   - value: The value of the right-hand side.
    ///   - interpreter: The interpreter.
    /// - Returns: The value to assign, or `nil` to assign the value unchanged.
    /// - Throws: ``EOLError`` if the conversion fails.
    func specialAssignment(_ value: EOLValue, interpreter: EOLInterpreter) async throws -> EOLValue?
}

extension EOLExtension {
    /// Provides no operations.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver.
    ///   - arguments: The arguments.
    ///   - interpreter: The interpreter.
    /// - Returns: `nil`.
    public func call(_ name: String, on receiver: EOLValue?, arguments: [EOLValue], interpreter: EOLInterpreter)
        async throws -> EOLValue?
    { nil }

    /// Leaves special assignments unchanged.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - interpreter: The interpreter.
    /// - Returns: `nil`.
    public func specialAssignment(_ value: EOLValue, interpreter: EOLInterpreter) async throws -> EOLValue? { nil }
}

/// The control flow outcome of executing a statement.
package enum EOLFlow {
    /// Execution continues with the next statement.
    case normal
    /// A `break` leaves the innermost loop.
    case breakLoop
    /// A `breakAll` leaves all enclosing loops.
    case breakAll
    /// A `continue` starts the next iteration.
    case continueLoop
    /// A `return` leaves the operation or block with a value.
    case returned(EOLValue)
}

/// A scope of variables.
package final class EOLFrame {
    /// The variables declared in the scope.
    package var variables: [String: EOLValue]

    /// Whether the scope hides the scopes below it (except the global scope).
    package let isProtected: Bool

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - variables: The initial variables.
    ///   - isProtected: Whether the frame hides the frames below it.
    package init(variables: [String: EOLValue] = [:], isProtected: Bool) {
        self.variables = variables
        self.isProtected = isProtected
    }
}
