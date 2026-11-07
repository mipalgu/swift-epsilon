//
//  EGLTemplate.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// A parsed EGL template.
///
/// A template is an EOL module whose statements interleave static text and
/// output sections with ordinary EOL statements. Operations annotated with
/// `@template` return the text they produce instead of appending it to the output.
public struct EGLTemplate: Sendable, Hashable {
    /// The document the template was read from, if known.
    public var document: String?

    /// The imported modules, in source order.
    public var imports: [EOLImport]

    /// The operations declared in the template, including `@template` operations.
    public var operations: [EOLOperation]

    /// The statements of the template body, in source order.
    public var statements: EOLBlock

    /// Creates a template.
    ///
    /// - Parameters:
    ///   - document: The source document.
    ///   - imports: The imports.
    ///   - operations: The operations.
    ///   - statements: The template body.
    public init(document: String? = nil, imports: [EOLImport] = [], operations: [EOLOperation] = [], statements: EOLBlock = []) {
        self.document = document
        self.imports = imports
        self.operations = operations
        self.statements = statements
    }

    /// The operations that return their text because they carry `@template`.
    public var templateOperations: [EOLOperation] {
        operations.filter { $0.hasAnnotation(EGLLanguage.templateAnnotation) }
    }

    /// The ordinary operations, which run like EOL operations.
    public var ordinaryOperations: [EOLOperation] {
        operations.filter { !$0.hasAnnotation(EGLLanguage.templateAnnotation) }
    }
}

/// Parsing of EGL templates.
public enum EGLSyntax {
    /// Parses a template.
    ///
    /// Static text, `[% … %]` code sections, `[%= … %]` output sections and
    /// `[* … *]` comments are recognised. A code section or comment that stands
    /// alone on its line takes the line's indentation and line break with it, so
    /// that control statements do not leave blank lines in the output. The
    /// outdenting close `-%]` is accepted and treated like `%]`.
    ///
    /// - Parameters:
    ///   - text: The template text.
    ///   - document: The document identifier used in diagnostics.
    /// - Returns: The template, diagnostics with positions, outline and tokens.
    public static func parse(_ text: String, document: String? = nil) -> EOLParseResult<EGLTemplate> {
        let scan = EOLLexer.scanTemplate(text, document: document)
        var parser = EOLParser(scan: scan, document: document)
        let module = parser.parseModule()
        let template = EGLTemplate(
            document: document, imports: module.imports, operations: module.operations, statements: module.statements)
        return EOLParseResult(
            module: template, diagnostics: parser.diagnostics, outline: parser.outline,
            tokens: EOLSyntax.sourceTokens(of: scan, keywords: EOLLanguage.Keyword.all))
    }

    /// Classifies the tokens of a template for syntax highlighting.
    ///
    /// - Parameter text: The template text.
    /// - Returns: The tokens, including static text, section delimiters and comments.
    public static func tokens(in text: String) -> [SourceToken] {
        EOLSyntax.sourceTokens(of: EOLLexer.scanTemplate(text), keywords: EOLLanguage.Keyword.all)
    }
}
