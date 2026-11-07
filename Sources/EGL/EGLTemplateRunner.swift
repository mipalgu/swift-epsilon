//
//  EGLTemplateRunner.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// Renders EGL templates with an EOL interpreter.
///
/// The runner binds a fresh ``EGLOutputBuffer`` as `out` for each rendering,
/// registers the template's operations with the interpreter, and runs the
/// template body with the given variables in a scope of its own, so that the
/// template sees global variables but not the caller's local ones.
///
/// ```swift
/// let interpreter = EOLInterpreter(models: [library])
/// let runner = EGLTemplateRunner(interpreter: interpreter)
/// let text = try await runner.render(try EGLSyntax.parse(source).get(), variables: ["title": .string("Books")])
/// ```
public final class EGLTemplateRunner {
    /// The interpreter that runs the templates.
    public let interpreter: EOLInterpreter

    /// The `@template` operations of the rendered templates.
    private let templateOperations = EGLTemplateOperations()

    /// Creates a runner and installs the `@template` operations extension.
    ///
    /// - Parameter interpreter: The interpreter that runs the templates.
    public init(interpreter: EOLInterpreter) {
        self.interpreter = interpreter
        interpreter.extensions.append(templateOperations)
    }

    /// Parses and renders template text.
    ///
    /// - Parameters:
    ///   - text: The template text.
    ///   - document: The document identifier used in diagnostics and for imports.
    ///   - variables: The variables the template can read.
    /// - Returns: The generated text.
    /// - Throws: `EOLError` for the first parse error or for a run-time error.
    public func render(_ text: String, document: String? = nil, variables: [String: EOLValue] = [:]) async throws -> String {
        try await render(EGLSyntax.parse(text, document: document).get(), variables: variables)
    }

    /// Renders a parsed template.
    ///
    /// - Parameters:
    ///   - template: The template.
    ///   - variables: The variables the template can read.
    /// - Returns: The generated text.
    /// - Throws: `EOLError` if an import fails or the template raises an error.
    public func render(_ template: EGLTemplate, variables: [String: EOLValue] = [:]) async throws -> String {
        try interpreter.register(operations: template.ordinaryOperations, imports: template.imports, document: template.document)
        templateOperations.add(template.templateOperations, document: template.document)
        let buffer = EGLOutputBuffer()
        let savedOutput = interpreter.templateOutput
        let savedOut = interpreter.variable(EGLLanguage.Variable.out)
        let savedDocument = interpreter.document
        interpreter.templateOutput = buffer
        interpreter.setGlobal(EGLLanguage.Variable.out, .object(EOLHostObjectReference(buffer)))
        interpreter.document = template.document
        defer {
            interpreter.templateOutput = savedOutput
            interpreter.setGlobal(EGLLanguage.Variable.out, savedOut ?? .undefined)
            interpreter.document = savedDocument
        }
        try await interpreter.withScope(variables, isProtected: true) {
            try await interpreter.execute(template.statements)
        }
        return buffer.text
    }
}

/// The extension that runs output buffer operations, and `@template` operations returning the text they produce.
final class EGLTemplateOperations: EOLExtension {
    /// The `@template` operations in declaration order.
    private var operations: [EOLOperation] = []

    /// The documents whose operations have been added.
    private var documents: Set<String> = []

    /// Adds the `@template` operations of a template, once per document.
    ///
    /// - Parameters:
    ///   - newOperations: The operations.
    ///   - document: The declaring document, if known.
    func add(_ newOperations: [EOLOperation], document: String?) {
        if let document {
            guard documents.insert(document).inserted else { return }
        }
        operations.append(contentsOf: newOperations)
    }

    /// Runs an operation of the output buffer, or a matching `@template` operation.
    ///
    /// Operations of the output buffer are handled here, before the built-in
    /// operations that every value has, so that `out.print(…)` appends to the
    /// buffer instead of printing the buffer. For `@template` operations, the first operation in declaration order whose name, number of parameters
    /// and context type fit the call is chosen.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver, or `nil` for a call without one.
    ///   - arguments: The evaluated arguments.
    ///   - interpreter: The interpreter.
    /// - Returns: The buffer operation's result or the produced text, or `nil` if neither fits.
    /// - Throws: `EOLError` if the operation fails.
    func call(_ name: String, on receiver: EOLValue?, arguments: [EOLValue], interpreter: EOLInterpreter) async throws -> EOLValue? {
        if case .object(let reference)? = receiver, let buffer = reference.object as? EGLOutputBuffer,
            let value = try await buffer.call(name, arguments: arguments, interpreter: interpreter)
        {
            return value
        }
        for operation in operations where operation.name == name && operation.parameters.count == arguments.count {
            if let contextType = operation.contextType {
                guard let receiver, try await interpreter.isKind(receiver, of: try interpreter.resolveType(contextType)) else {
                    continue
                }
            }
            guard case .object(let reference)? = interpreter.variable(EGLLanguage.Variable.out),
                let buffer = reference.object as? EGLOutputBuffer
            else {
                throw EOLError(.unsupportedConstruct, "'@template' operations can only be called while a template runs")
            }
            buffer.beginCapture()
            do {
                _ = try await interpreter.invoke(operation, receiver: receiver ?? .undefined, arguments: arguments)
            } catch {
                _ = buffer.endCapture()
                throw error
            }
            return .string(buffer.endCapture())
        }
        return nil
    }
}
