//
//  EGXSyntax.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// How a property of an EGX rule computes its value.
public enum EGXValue: Sendable, Hashable {
    /// A single expression, written `name : expression`.
    case expression(EOLExpression)
    /// A statement block that returns the value, written `name { … return value; }`.
    case block(EOLBlock)
}

/// A named `pre` or `post` block.
public struct EGXBlock: Sendable, Hashable {
    /// The optional name of the block.
    public var name: String?
    /// The statements.
    public var statements: EOLBlock
    /// The source range.
    public var range: SourceRange
}

/// A generation rule of an EGX module.
public struct EGXRule: Sendable, Hashable {
    /// The rule name.
    public var name: String
    /// The variable bound to each transformed element, if the rule transforms elements.
    public var parameter: EOLParameter?
    /// The explicit domain written `in : expression`, if any.
    public var domain: EOLExpression?
    /// Whether the rule also applies to instances of subtypes (`@greedy`).
    public var isGreedy: Bool
    /// The guard, which defaults to true.
    public var guardValue: EGXValue?
    /// The statements run before the other properties are evaluated.
    public var pre: EOLBlock
    /// The variables passed to the template, as a map from names to values.
    public var parameters: EGXValue?
    /// The template path.
    public var template: EGXValue?
    /// The target file path; without one, the text is generated but not written.
    public var target: EGXValue?
    /// Whether an existing target file is replaced (default true).
    public var overwrite: EGXValue?
    /// Whether protected regions of an existing target are kept (default true).
    public var merge: EGXValue?
    /// The statements run after the file was generated.
    public var post: EOLBlock
    /// The source range of the rule.
    public var range: SourceRange
}

/// A parsed EGX module.
public struct EGXModule: Sendable, Hashable {
    /// The document the module was read from, if known.
    public var document: String?
    /// The imports.
    public var imports: [EOLImport] = []
    /// The operations.
    public var operations: [EOLOperation] = []
    /// The `pre` blocks, in source order.
    public var pre: [EGXBlock] = []
    /// The rules, in source order.
    public var rules: [EGXRule] = []
    /// The `post` blocks, in source order.
    public var post: [EGXBlock] = []

    /// Creates an empty module.
    ///
    /// - Parameter document: The source document.
    public init(document: String? = nil) { self.document = document }
}

/// Parsing of EGX modules.
public enum EGXSyntax {
    /// The words reserved in EGX in addition to the EOL keywords, for highlighting.
    static let keywords: Set<String> = EOLLanguage.Keyword.all.union([
        EGLLanguage.EGXKeyword.rule, EGLLanguage.EGXKeyword.transform, EGLLanguage.EGXKeyword.pre,
        EGLLanguage.EGXKeyword.post,
    ]).union(EGLLanguage.EGXKeyword.properties)

    /// Parses an EGX module.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document identifier, used in diagnostics and to resolve templates.
    /// - Returns: The module, diagnostics, outline and tokens.
    public static func parse(_ text: String, document: String? = nil) -> EOLParseResult<EGXModule> {
        let scan = EOLLexer.scan(text, document: document)
        var parser = EOLParser(scan: scan, document: document)
        let module = parser.parseEGXModule()
        return EOLParseResult(
            module: module, diagnostics: parser.diagnostics, outline: parser.outline,
            tokens: EOLSyntax.sourceTokens(of: scan, keywords: keywords))
    }
}

extension EOLParser {
    /// Parses an EGX module up to the end of the input.
    ///
    /// - Returns: The module, holding every declaration that parsed correctly.
    mutating func parseEGXModule() -> EGXModule {
        typealias K = EGLLanguage.EGXKeyword
        var module = EGXModule(document: document)
        while !isAtEnd {
            let start = position
            do {
                if current.isWord(EOLLanguage.Keyword.import) {
                    module.imports.append(try parseImport())
                    continue
                }
                let annotations = try parseAnnotations()
                if current.isWord(EOLLanguage.Keyword.operation) || current.isWord(EOLLanguage.Keyword.function) {
                    module.operations.append(try parseOperation(annotations: annotations))
                } else if current.isWord(K.pre) || current.isWord(K.post) {
                    let isPre = current.isWord(K.pre)
                    let block = try parseNamedBlock()
                    if isPre { module.pre.append(block) } else { module.post.append(block) }
                    outline.append(
                        OutlineNode(
                            id: "\(isPre ? K.pre : K.post):\(outline.count)", kind: isPre ? EOLOutlineKind.pre : EOLOutlineKind.post,
                            name: block.name ?? (isPre ? K.pre : K.post), range: block.range, selectionRange: block.range))
                } else if current.isWord(K.rule) {
                    let isGreedy = annotations.contains { $0.name == K.greedy }
                    module.rules.append(try parseEGXRule(isGreedy: isGreedy, start: annotations.first?.range ?? current.range))
                } else {
                    throw unexpected("'rule', 'pre', 'post', 'operation' or 'import'")
                }
            } catch let failure as EOLError {
                record(failure)
                skipDeclaration(from: start)
            } catch {
                skipDeclaration(from: start)
            }
        }
        return module
    }

    /// Parses `pre name? { … }` or `post name? { … }`.
    private mutating func parseNamedBlock() throws -> EGXBlock {
        let start = advance().range
        var name: String?
        if case .identifier(let word, _) = current.kind { name = word; advance() }
        let statements = try parseBlock()
        return EGXBlock(name: name, statements: statements, range: range(from: start))
    }

    /// Parses a rule after its annotations.
    private mutating func parseEGXRule(isGreedy: Bool, start: SourceRange) throws -> EGXRule {
        typealias K = EGLLanguage.EGXKeyword
        try expectWord(K.rule)
        let (name, nameRange) = try expectName()
        var rule = EGXRule(
            name: name, parameter: nil, domain: nil, isGreedy: isGreedy, guardValue: nil, pre: [], parameters: nil,
            template: nil, target: nil, overwrite: nil, merge: nil, post: [], range: start)
        if acceptWord(K.transform) {
            rule.parameter = try parseParameter()
            if acceptWord(K.in) {
                try expect(EOLLanguage.Symbol.colon)
                rule.domain = try parseExpression()
            }
        }
        try expect(EOLLanguage.Symbol.openBrace)
        while !current.isSymbol(EOLLanguage.Symbol.closeBrace) {
            guard let word = current.bareName else { throw unexpected("a rule property") }
            let propertyRange = current.range
            switch word {
            case K.pre:
                advance()
                rule.pre = try parseBlock()
            case K.post:
                advance()
                rule.post = try parseBlock()
            case K.guard, K.parameters, K.template, K.target, K.overwrite, K.merge:
                advance()
                let value = try parseEGXValue()
                switch word {
                case K.guard: rule.guardValue = value
                case K.parameters: rule.parameters = value
                case K.template: rule.template = value
                case K.target: rule.target = value
                case K.overwrite: rule.overwrite = value
                default: rule.merge = value
                }
            default:
                throw error(.unexpectedToken, "Unknown rule property '\(word)'", at: propertyRange)
            }
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        rule.range = range(from: start)
        outline.append(
            OutlineNode(
                id: "rule:\(name)", kind: EOLOutlineKind.rule, name: name, detail: rule.parameter?.type?.description,
                range: rule.range, selectionRange: nameRange))
        return rule
    }

    /// Parses `: expression` (with an optional `;`) or a block.
    private mutating func parseEGXValue() throws -> EGXValue {
        if current.isSymbol(EOLLanguage.Symbol.openBrace) { return .block(try parseBlock()) }
        try expect(EOLLanguage.Symbol.colon)
        let value = try parseExpression()
        accept(EOLLanguage.Symbol.semicolon)
        return .expression(value)
    }
}
