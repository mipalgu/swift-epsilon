//
//  EGXGenerator.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL
import Foundation

/// Where an EGX generator reads and writes target files.
public protocol EGXFileSystem: AnyObject {
    /// Reads a file.
    ///
    /// - Parameter path: The target path.
    /// - Returns: The text, or `nil` if the file does not exist.
    /// - Throws: An error if the file exists but cannot be read.
    func read(_ path: String) throws -> String?

    /// Writes a file, creating directories as needed.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - path: The target path.
    /// - Throws: An error if the file cannot be written.
    func write(_ text: String, to path: String) throws
}

/// A file system held in memory, for tests and previews.
public final class EGXInMemoryFileSystem: EGXFileSystem {
    /// The files by path.
    public var files: [String: String]

    /// Creates a file system.
    ///
    /// - Parameter files: The initial files by path.
    public init(files: [String: String] = [:]) { self.files = files }

    /// Reads a file.
    ///
    /// - Parameter path: The path.
    /// - Returns: The text, or `nil`.
    public func read(_ path: String) throws -> String? { files[path] }

    /// Writes a file.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - path: The path.
    public func write(_ text: String, to path: String) throws { files[path] = text }
}

/// A file system rooted at a directory; relative target paths are resolved against it.
///
/// By default the file system is confined to its directory: absolute paths and
/// relative paths that lead outside the directory (for example through `..`) are
/// rejected, so that a generator cannot write anywhere else. Confinement can be
/// lifted explicitly for trusted generators.
public final class EGXDirectoryFileSystem: EGXFileSystem {
    /// The directory that relative paths are resolved against.
    public let base: URL

    /// Whether paths may lead outside ``base``.
    public let allowsPathsOutsideBase: Bool

    /// The character encoding in which files are read and written (UTF-8 by default).
    public let encoding: TextEncoding

    /// Creates a file system rooted at a directory.
    ///
    /// - Parameters:
    ///   - base: The directory.
    ///   - allowsPathsOutsideBase: Whether absolute paths and paths leading outside the
    ///     directory are allowed (default `false`).
    public init(base: URL, allowsPathsOutsideBase: Bool = false) {
        self.base = base.standardizedFileURL
        self.allowsPathsOutsideBase = allowsPathsOutsideBase
        self.encoding = .utf8
    }

    /// Creates a file system rooted at a directory that reads and writes files in an encoding.
    ///
    /// Existing files are read in the encoding too, so that protected regions can be merged
    /// into the files of an earlier run. A character that the encoding cannot hold makes
    /// ``write(_:to:)`` fail without leaving a file behind.
    ///
    /// - Parameters:
    ///   - base: The directory.
    ///   - allowsPathsOutsideBase: Whether absolute paths and paths leading outside the
    ///     directory are allowed.
    ///   - encoding: The character encoding of the files.
    public init(base: URL, allowsPathsOutsideBase: Bool, encoding: TextEncoding) {
        self.base = base.standardizedFileURL
        self.allowsPathsOutsideBase = allowsPathsOutsideBase
        self.encoding = encoding
    }

    /// The URL of a target path.
    ///
    /// - Parameter path: The path.
    /// - Returns: The path itself if absolute, otherwise the path below ``base``.
    /// - Throws: `EOLError` with code `EOLDiagnosticCode.fileAccess` if the file
    ///   system is confined and the path leads outside ``base``.
    public func url(for path: String) throws -> URL {
        let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)).standardizedFileURL
        guard allowsPathsOutsideBase || url.path.hasPrefix(base.path.hasSuffix("/") ? base.path : base.path + "/") else {
            throw EOLError(.fileAccess, "Path '\(path)' leads outside the output directory")
        }
        return url
    }

    /// Reads a file.
    ///
    /// - Parameter path: The path.
    /// - Returns: The text, or `nil` if there is no such file.
    /// - Throws: An error if the path is not allowed or the file cannot be decoded.
    public func read(_ path: String) throws -> String? {
        let url = try url(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if encoding == .utf8 { return try String(contentsOf: url, encoding: .utf8) }
        let data = try Data(contentsOf: url)
        guard let text = encoding.decode(data) else {
            throw EOLError(.fileAccess, "Cannot read \(url.path): it is not valid \(encoding.name) text")
        }
        return text
    }

    /// Writes a file, creating its directory as needed.
    ///
    /// The file is replaced atomically where the runtime supports it; on WASI, which has no
    /// atomic replacement, it is written directly.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - path: The path.
    /// - Throws: An error if the path is not allowed, if the encoding cannot hold a character of
    ///   the text (the error names the character, its line and column, and no file is written;
    ///   an ``EGXGenerator`` adds the target path), or if the file cannot be written.
    public func write(_ text: String, to path: String) throws {
        let url = try url(for: path)
        let data: Data?
        if encoding == .utf8 {
            data = nil
        } else {
            do {
                data = try encoding.encode(text)
            } catch {
                throw EOLError(.fileAccess, "\(error)")
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data {
            #if os(WASI)
            try data.write(to: url)
            #else
            try data.write(to: url, options: .atomic)
            #endif
        } else {
            try text.write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
        }
    }
}

/// What happened to a target file.
public enum EGXFileStatus: String, Sendable, Hashable {
    /// The file did not exist and was written.
    case created
    /// The file existed and was rewritten with different text.
    case updated
    /// The file existed with the same text and was left alone.
    case unchanged
    /// The file existed and was left alone because `overwrite` is false.
    case skipped
    /// The rule has no target, so the text was generated but not written.
    case notWritten
}

/// The outcome of one rule application.
public struct EGXGeneratedFile: Sendable, Hashable {
    /// The rule that generated the text.
    public var rule: String
    /// The target path, or `nil` for a rule without a target.
    public var path: String?
    /// The text of the file after generation (the existing text when skipped).
    public var content: String
    /// What happened to the file.
    public var status: EGXFileStatus
}

/// The outcome of running an EGX module.
public struct EGXResult: Sendable {
    /// The rule applications, in order.
    public var files: [EGXGeneratedFile] = []
    /// Warnings, such as protected regions whose contents were discarded.
    public var diagnostics: [SourceDiagnostic] = []
}

/// Runs EGX modules: applies each rule to its elements and generates files from templates.
///
/// Rules apply to direct instances of their type, or to instances of subtypes as
/// well when annotated `@greedy`, or to the elements of an explicit `in` domain.
/// For each element the guard, `pre`, parameters, template, target, `overwrite`
/// and `merge` properties are evaluated in that order, the template is rendered
/// with the parameters as variables, and the text is merged with the protected
/// regions of an existing target before it is written. In a rule's `post` block
/// the variable `generated` holds the target path, or the text when there is no
/// target.
public final class EGXGenerator {
    /// The interpreter that runs the module and its templates.
    public let interpreter: EOLInterpreter

    /// How templates are read; paths are resolved relative to the EGX document.
    public var templateLoader: any EOLModuleLoading

    /// Where target files are read and written.
    public var fileSystem: any EGXFileSystem

    /// The renderer of the templates.
    private let runner: EGLTemplateRunner

    /// The parsed templates by document.
    private var templates: [String: EGLTemplate] = [:]

    /// Creates a generator.
    ///
    /// - Parameters:
    ///   - interpreter: The interpreter with the models.
    ///   - templateLoader: How templates are read (from files by default).
    ///   - fileSystem: Where target files go.
    public init(interpreter: EOLInterpreter, templateLoader: any EOLModuleLoading = EOLFileModuleLoader(), fileSystem: any EGXFileSystem) {
        self.interpreter = interpreter
        self.templateLoader = templateLoader
        self.fileSystem = fileSystem
        runner = EGLTemplateRunner(interpreter: interpreter)
    }

    /// Runs a module.
    ///
    /// - Parameter module: The module.
    /// - Returns: The rule applications and warnings.
    /// - Throws: `EOLError` if a template cannot be read or parsed, a property has
    ///   the wrong type, or the program raises an error.
    public func generate(_ module: EGXModule) async throws -> EGXResult {
        try interpreter.register(operations: module.operations, imports: module.imports, document: module.document)
        interpreter.document = module.document
        var result = EGXResult()
        for block in module.pre { try await interpreter.executeInGlobalScope(block.statements) }
        for rule in module.rules {
            for element in try await domain(of: rule) {
                var variables: [String: EOLValue] = [:]
                if let parameter = rule.parameter, let element { variables[parameter.name] = element }
                try await interpreter.withScope(variables) {
                    try await apply(rule, module: module, into: &result)
                }
            }
        }
        for block in module.post { try await interpreter.execute(block.statements) }
        return result
    }

    /// The elements a rule applies to, or a single `nil` for a rule without `transform`.
    private func domain(of rule: EGXRule) async throws -> [EOLValue?] {
        guard let parameter = rule.parameter else { return [nil] }
        let type = try parameter.type.map { try interpreter.resolveType($0) }
        if let domain = rule.domain {
            var elements: [EOLValue?] = []
            for item in try await interpreter.evaluate(domain).asElements {
                if let type, !(try await interpreter.isKind(item, of: type)) { continue }
                elements.append(item)
            }
            return elements
        }
        guard let type else {
            throw EOLError(.invalidDeclaration, "Rule '\(rule.name)' needs a type or an 'in' domain", range: rule.range, document: interpreter.document)
        }
        return try await interpreter.allInstances(of: type, exact: !rule.isGreedy).asElements.map { $0 }
    }

    /// Applies a rule in the scope that binds its element.
    private func apply(_ rule: EGXRule, module: EGXModule, into result: inout EGXResult) async throws {
        if let guardValue = rule.guardValue {
            guard let flag = try await value(guardValue).booleanValue else {
                throw EOLError(.typeMismatch, "The guard of rule '\(rule.name)' must be Boolean", range: rule.range, document: module.document)
            }
            if !flag { return }
        }
        _ = try await interpreter.executeStatements(rule.pre)
        var parameters: [String: EOLValue] = [:]
        if let source = rule.parameters {
            guard case .map(let map) = try await value(source) else {
                throw EOLError(.typeMismatch, "The parameters of rule '\(rule.name)' must be a Map", range: rule.range, document: module.document)
            }
            for key in map.keys {
                guard let name = key.stringValue else { throw EOLError(.typeMismatch, "Parameter names must be strings") }
                parameters[name] = map[key] ?? .undefined
            }
        }
        guard let templateSource = rule.template, let templatePath = try await value(templateSource).stringValue else {
            throw EOLError(.invalidDeclaration, "Rule '\(rule.name)' has no template path", range: rule.range, document: module.document)
        }
        let target = try await rule.target.asyncMap { try await self.value($0).stringValue }
        let overwrite = try await flag(rule.overwrite, default: true, rule: rule)
        let merge = try await flag(rule.merge, default: true, rule: rule)
        let template = try loadTemplate(templatePath, relativeTo: module.document, rule: rule)
        var text = try await runner.render(template, variables: parameters)
        let file: EGXGeneratedFile
        if let target {
            let existing: String?
            do {
                existing = try fileSystem.read(target)
            } catch {
                throw EOLError(.fileAccess, "Cannot read '\(target)': \(error.localizedDescription)", range: rule.range, document: module.document)
            }
            if let existing, !overwrite {
                file = EGXGeneratedFile(rule: rule.name, path: target, content: existing, status: .skipped)
            } else {
                if let existing, merge {
                    let merged = EGLProtectedRegions.merge(generated: text, existing: existing, document: target)
                    text = merged.text
                    result.diagnostics += merged.diagnostics
                }
                let status: EGXFileStatus = existing == nil ? .created : existing == text ? .unchanged : .updated
                if status != .unchanged {
                    do {
                        try fileSystem.write(text, to: target)
                    } catch {
                        throw EOLError(.fileAccess, "Cannot write '\(target)': \(error.localizedDescription)", range: rule.range, document: module.document)
                    }
                }
                file = EGXGeneratedFile(rule: rule.name, path: target, content: text, status: status)
            }
        } else {
            file = EGXGeneratedFile(rule: rule.name, path: nil, content: text, status: .notWritten)
        }
        result.files.append(file)
        if !rule.post.isEmpty {
            let generated: EOLValue = .string(target ?? text)
            try await interpreter.execute(rule.post, variables: [EGLLanguage.Variable.generated: generated])
        }
    }

    /// Evaluates a Boolean property with a default.
    private func flag(_ source: EGXValue?, default fallback: Bool, rule: EGXRule) async throws -> Bool {
        guard let source else { return fallback }
        guard let flag = try await value(source).booleanValue else {
            throw EOLError(.typeMismatch, "A Boolean property of rule '\(rule.name)' has a non-Boolean value", range: rule.range, document: interpreter.document)
        }
        return flag
    }

    /// Evaluates a rule property.
    private func value(_ source: EGXValue) async throws -> EOLValue {
        switch source {
        case .expression(let expression): return try await interpreter.evaluate(expression)
        case .block(let statements): return try await interpreter.evaluateBlock(statements)
        }
    }

    /// Reads and parses a template once.
    private func loadTemplate(_ path: String, relativeTo document: String?, rule: EGXRule) throws -> EGLTemplate {
        let loaded: (text: String, document: String)
        do {
            loaded = try templateLoader.load(path, relativeTo: document)
        } catch {
            throw EOLError(.fileAccess, "Cannot read template '\(path)': \(error.localizedDescription)", range: rule.range, document: document)
        }
        if let template = templates[loaded.document] { return template }
        let parsed = EGLSyntax.parse(loaded.text, document: loaded.document)
        if let failure = parsed.diagnostics.first(where: { $0.severity == .error }) { throw EOLError(diagnostic: failure) }
        templates[loaded.document] = parsed.module
        return parsed.module
    }
}

extension Optional {
    /// Transforms the wrapped value with an asynchronous function.
    ///
    /// - Parameter transform: The transformation.
    /// - Returns: The transformed value, or `nil`.
    /// - Throws: Whatever the transformation throws.
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T?) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
