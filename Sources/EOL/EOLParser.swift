//
//  EOLParser.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The result of parsing source text while collecting diagnostics.
///
/// Parsing recovers from errors, so the module holds every declaration and
/// statement that was read correctly, and the diagnostics describe each one that
/// was not.
public struct EOLParseResult<Module: Sendable>: Sendable {
    /// The parsed module.
    public var module: Module

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The outline of the source text.
    public var outline: [OutlineNode]

    /// The lexical tokens of the source text, including comments, for highlighting.
    public var tokens: [SourceToken]

    /// Whether any diagnostic is an error.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - module: The parsed module.
    ///   - diagnostics: The problems found.
    ///   - outline: The outline of the source text.
    ///   - tokens: The lexical tokens.
    public init(module: Module, diagnostics: [SourceDiagnostic], outline: [OutlineNode], tokens: [SourceToken]) {
        self.module = module
        self.diagnostics = diagnostics
        self.outline = outline
        self.tokens = tokens
    }

    /// Returns the module, or throws the first error diagnostic.
    ///
    /// - Returns: The parsed module.
    /// - Throws: ``EOLError`` wrapping the first error diagnostic.
    public func get() throws -> Module {
        if let first = diagnostics.first(where: { $0.severity == .error }) { throw EOLError(diagnostic: first) }
        return module
    }
}

/// Parsing of EOL source text.
public enum EOLSyntax {
    /// Parses an EOL module.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document identifier (for example a URI) used in diagnostics.
    /// - Returns: The module, diagnostics, outline and tokens.
    public static func parse(_ text: String, document: String? = nil) -> EOLParseResult<EOLModule> {
        let scan = EOLLexer.scan(text, document: document)
        var parser = EOLParser(scan: scan, document: document)
        let module = parser.parseModule()
        return EOLParseResult(
            module: module, diagnostics: parser.diagnostics, outline: parser.outline,
            tokens: sourceTokens(of: scan, keywords: EOLLanguage.Keyword.all))
    }

    /// Parses a single EOL expression.
    ///
    /// - Parameters:
    ///   - text: The expression text.
    ///   - document: The document identifier used in diagnostics.
    /// - Returns: The expression.
    /// - Throws: ``EOLError`` if the text is not a single valid expression.
    public static func parseExpression(_ text: String, document: String? = nil) throws -> EOLExpression {
        let scan = EOLLexer.scan(text, document: document)
        if let first = scan.diagnostics.first { throw EOLError(diagnostic: first) }
        var parser = EOLParser(scan: scan, document: document)
        let expression = try parser.parseExpression()
        guard parser.current.kind == .endOfInput else { throw parser.unexpected("end of expression") }
        return expression
    }

    /// Classifies the tokens of EOL source text for syntax highlighting.
    ///
    /// - Parameter text: The source text.
    /// - Returns: The tokens, including comments, in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        sourceTokens(of: EOLLexer.scan(text), keywords: EOLLanguage.Keyword.all)
    }

    /// Converts a scan into highlighting tokens.
    ///
    /// - Parameters:
    ///   - scan: The scan.
    ///   - keywords: The words to classify as keywords.
    /// - Returns: The tokens in source order.
    package static func sourceTokens(of scan: EOLScan, keywords: Set<String>) -> [SourceToken] {
        var result: [SourceToken] = scan.comments.map { SourceToken(kind: .comment, range: $0) }
        var previous: EOLToken?
        for token in scan.tokens {
            let kind: SourceTokenKind?
            switch token.kind {
            case .identifier(let name, let quoted):
                if !quoted, name == EOLLanguage.Keyword.true || name == EOLLanguage.Keyword.false {
                    kind = .boolean
                } else if !quoted, keywords.contains(name) {
                    kind = .keyword
                } else if previous?.isSymbol(EOLLanguage.Symbol.bang) == true || previous?.isSymbol(EOLLanguage.Symbol.colon) == true {
                    kind = .typeName
                } else if previous?.isSymbol(EOLLanguage.Symbol.hash) == true {
                    kind = .enumLiteral
                } else {
                    kind = .identifier
                }
            case .string: kind = .string
            case .integer, .real: kind = .number
            case .symbol(let symbol):
                kind = symbol.count == 1 && "(){}[],;".contains(symbol) ? .punctuation : .operator
            case .templateText: kind = .text
            case .templateOutput, .templateClose: kind = .directive
            case .endOfInput: kind = nil
            }
            if let kind { result.append(SourceToken(kind: kind, range: token.range)) }
            previous = token
        }
        return result.sorted { $0.range.start.utf8Offset < $1.range.start.utf8Offset }
    }
}

/// A recursive-descent parser for EOL that the dialect parsers extend.
///
/// The parser works on the tokens of an ``EOLScan``. Each `parse…` method
/// either returns a syntax tree node or throws an ``EOLError``; block-level
/// methods catch statement errors, record them in ``diagnostics`` and resume
/// after the next statement, so that one mistake does not hide the rest of the
/// module.
package struct EOLParser {
    /// The tokens being parsed, ending with an end-of-input token.
    package var tokens: [EOLToken]

    /// The index of the current token.
    package var position = 0

    /// The problems found so far, starting with the lexical problems.
    package var diagnostics: [SourceDiagnostic]

    /// The outline entries collected so far.
    package var outline: [OutlineNode] = []

    /// The document the diagnostics refer to.
    package let document: String?

    /// Words that end a statement-level expression list, such as the dialect keywords
    /// `guard` or `check` that follow an EVL block member.
    package var dialectWords: Set<String> = []

    /// Creates a parser.
    ///
    /// - Parameters:
    ///   - scan: The scanned tokens.
    ///   - document: The document the diagnostics refer to.
    package init(scan: EOLScan, document: String?) {
        tokens = scan.tokens
        diagnostics = scan.diagnostics
        self.document = document
    }

    // MARK: - Token Access

    /// The current token.
    package var current: EOLToken { tokens[position] }

    /// The token at an offset from the current one, or the end-of-input token.
    ///
    /// - Parameter offset: The number of tokens to look ahead.
    /// - Returns: The token.
    package func peek(_ offset: Int) -> EOLToken {
        let index = position + offset
        return index < tokens.count ? tokens[index] : tokens[tokens.count - 1]
    }

    /// Whether all tokens have been consumed.
    package var isAtEnd: Bool { current.kind == .endOfInput }

    /// Consumes the current token.
    ///
    /// - Returns: The consumed token.
    @discardableResult
    package mutating func advance() -> EOLToken {
        let token = current
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    /// The range of the token before the current one, used to end a node's range.
    package var previousRange: SourceRange { tokens[max(0, position - 1)].range }

    /// The range from a start position to the end of the previous token.
    ///
    /// - Parameter start: The start range.
    /// - Returns: The union range.
    package func range(from start: SourceRange) -> SourceRange {
        let end = previousRange
        guard end.end.utf8Offset >= start.start.utf8Offset else { return start }
        return SourceRange(start: start.start, end: end.end)
    }

    /// Consumes the current token if it is the symbol.
    ///
    /// - Parameter symbol: The expected symbol.
    /// - Returns: `true` if the symbol was consumed.
    @discardableResult
    package mutating func accept(_ symbol: String) -> Bool {
        guard current.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    /// Consumes the current token if it is the unquoted word.
    ///
    /// - Parameter word: The expected word.
    /// - Returns: `true` if the word was consumed.
    @discardableResult
    package mutating func acceptWord(_ word: String) -> Bool {
        guard current.isWord(word) else { return false }
        advance()
        return true
    }

    /// Consumes a symbol or throws.
    ///
    /// - Parameter symbol: The expected symbol.
    /// - Returns: The consumed token.
    /// - Throws: ``EOLError`` if the current token is not the symbol.
    @discardableResult
    package mutating func expect(_ symbol: String) throws -> EOLToken {
        guard current.isSymbol(symbol) else { throw unexpected("'\(symbol)'") }
        return advance()
    }

    /// Consumes an unquoted word or throws.
    ///
    /// - Parameter word: The expected word.
    /// - Returns: The consumed token.
    /// - Throws: ``EOLError`` if the current token is not the word.
    @discardableResult
    package mutating func expectWord(_ word: String) throws -> EOLToken {
        guard current.isWord(word) else { throw unexpected("'\(word)'") }
        return advance()
    }

    /// Consumes a name that is not a reserved word, or throws.
    ///
    /// - Returns: The name and its range.
    /// - Throws: ``EOLError`` if the current token is not a name.
    package mutating func expectName() throws -> (String, SourceRange) {
        guard case .identifier(let name, let quoted) = current.kind,
            quoted || !EOLLanguage.Keyword.all.contains(name)
        else { throw unexpected("a name") }
        let token = advance()
        return (name, token.range)
    }

    /// Consumes a string literal or throws.
    ///
    /// - Returns: The string and its range.
    /// - Throws: ``EOLError`` if the current token is not a string.
    package mutating func expectString() throws -> (String, SourceRange) {
        guard case .string(let text) = current.kind else { throw unexpected("a string") }
        let token = advance()
        return (text, token.range)
    }

    /// Creates an error for an unexpected current token.
    ///
    /// - Parameter expected: What was expected instead.
    /// - Returns: The error.
    package func unexpected(_ expected: String) -> EOLError {
        EOLError(
            .unexpectedToken, "Expected \(expected) but found \(describe(current))", range: current.range,
            document: document)
    }

    /// Creates an error at a range.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: The message.
    ///   - range: The range.
    /// - Returns: The error.
    package func error(_ code: EOLDiagnosticCode, _ message: String, at range: SourceRange) -> EOLError {
        EOLError(code, message, range: range, document: document)
    }

    /// Describes a token for an error message.
    ///
    /// - Parameter token: The token.
    /// - Returns: A short description.
    package func describe(_ token: EOLToken) -> String {
        switch token.kind {
        case .identifier(let name, _): return "'\(name)'"
        case .string(let text): return "string \"\(text)\""
        case .integer(let value): return "\(value)"
        case .real(let value): return "\(value)"
        case .symbol(let symbol): return "'\(symbol)'"
        case .templateText: return "template text"
        case .templateOutput: return "'[%='"
        case .templateClose: return "'%]'"
        case .endOfInput: return "end of input"
        }
    }

    /// Records a diagnostic.
    ///
    /// - Parameter error: The error to record.
    package mutating func record(_ error: EOLError) {
        var diagnostic = error.diagnostic
        if diagnostic.document == nil { diagnostic.document = document }
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
    }

    /// Skips tokens after an error until the end of the current statement or block.
    ///
    /// Tokens are skipped up to and including the next `;` outside nested braces,
    /// or up to (not including) a `}` that closes the enclosing block.
    ///
    /// - Parameter start: The position at which the failed construct started.
    package mutating func synchronise(from start: Int) {
        if position == start { advance() }
        var depth = 0
        while !isAtEnd {
            if current.isSymbol(EOLLanguage.Symbol.openBrace) {
                depth += 1
            } else if current.isSymbol(EOLLanguage.Symbol.closeBrace) {
                if depth == 0 { return }
                depth -= 1
                if depth == 0 {
                    advance()
                    if !current.isSymbol(EOLLanguage.Symbol.semicolon) { return }
                }
            } else if current.isSymbol(EOLLanguage.Symbol.semicolon), depth == 0 {
                advance()
                return
            } else if current.kind == .templateClose, depth == 0 {
                return
            }
            advance()
        }
    }

    /// Skips a whole top-level declaration after an error in it.
    ///
    /// - Parameter start: The position of the declaration's first token.
    package mutating func skipDeclaration(from start: Int) {
        position = start
        var depth = 0
        var sawBrace = false
        while !isAtEnd {
            let token = advance()
            if token.isSymbol(EOLLanguage.Symbol.openBrace) {
                depth += 1
                sawBrace = true
            } else if token.isSymbol(EOLLanguage.Symbol.closeBrace) {
                depth -= 1
                if depth <= 0, sawBrace { return }
            } else if token.isSymbol(EOLLanguage.Symbol.semicolon), depth == 0, !sawBrace {
                return
            }
        }
    }

    // MARK: - Modules

    /// Parses an EOL module up to the end of the input.
    ///
    /// - Returns: The module.
    package mutating func parseModule() -> EOLModule {
        var module = EOLModule(document: document)
        while !isAtEnd {
            parseModuleMember(into: &module)
        }
        return module
    }

    /// Parses one import, operation or statement of a module.
    ///
    /// - Parameter module: The module that receives the member.
    package mutating func parseModuleMember(into module: inout EOLModule) {
        let start = position
        do {
            if current.isWord(EOLLanguage.Keyword.import) {
                module.imports.append(try parseImport())
                return
            }
            if current.kind == .templateClose {
                advance()
                return
            }
            let annotations = try parseAnnotations()
            if current.isWord(EOLLanguage.Keyword.operation) || current.isWord(EOLLanguage.Keyword.function) {
                module.operations.append(try parseOperation(annotations: annotations))
                return
            }
            if let first = annotations.first {
                throw error(.unexpectedToken, "Annotations must precede a declaration", at: first.range)
            }
            if let statement = try parseStatementInBlock() { module.statements.append(statement) }
        } catch let failure as EOLError {
            record(failure)
            if position == start || isDeclarationStart(at: start) {
                skipDeclaration(from: start)
            } else {
                synchronise(from: start)
            }
        } catch {
            skipDeclaration(from: start)
        }
    }

    /// Whether the token at a position starts an operation declaration.
    private func isDeclarationStart(at index: Int) -> Bool {
        let token = tokens[index]
        return token.isWord(EOLLanguage.Keyword.operation) || token.isWord(EOLLanguage.Keyword.function)
            || token.isSymbol(EOLLanguage.Symbol.at) || token.isSymbol(EOLLanguage.Symbol.dollar)
    }

    /// Parses `import "path";`.
    ///
    /// - Returns: The import.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseImport() throws -> EOLImport {
        let start = try expectWord(EOLLanguage.Keyword.import).range
        let (path, _) = try expectString()
        try expect(EOLLanguage.Symbol.semicolon)
        let declaration = EOLImport(path: path, range: range(from: start))
        outline.append(
            OutlineNode(
                id: "import:\(path)", kind: EOLOutlineKind.import, name: path, range: declaration.range,
                selectionRange: declaration.range))
        return declaration
    }

    /// Parses the annotations before a declaration.
    ///
    /// Simple annotations are `@name`, optionally followed on the same line by a
    /// string or number value. Executable annotations are `$name expression`.
    ///
    /// - Returns: The annotations in source order.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseAnnotations() throws -> [EOLAnnotation] {
        var annotations: [EOLAnnotation] = []
        while current.isSymbol(EOLLanguage.Symbol.at) || current.isSymbol(EOLLanguage.Symbol.dollar) {
            let marker = advance()
            guard case .identifier(let name, _) = current.kind else { throw unexpected("an annotation name") }
            let nameToken = advance()
            if marker.isSymbol(EOLLanguage.Symbol.dollar) {
                let expression = try parseExpression()
                annotations.append(
                    EOLAnnotation(name: name, expression: expression, range: range(from: marker.range)))
                continue
            }
            var value: String?
            if current.range.start.line == nameToken.range.start.line {
                switch current.kind {
                case .string(let text): value = text; advance()
                case .integer(let number): value = String(number); advance()
                case .real(let number): value = String(number); advance()
                default: break
                }
            }
            annotations.append(EOLAnnotation(name: name, value: value, range: range(from: marker.range)))
        }
        return annotations
    }

    /// Parses an operation declaration.
    ///
    /// - Parameter annotations: The annotations written before it.
    /// - Returns: The operation.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseOperation(annotations: [EOLAnnotation]) throws -> EOLOperation {
        let start = annotations.first?.range ?? current.range
        advance()
        let first = try parseTypeReference()
        var contextType: EOLTypeReference?
        let name: String
        let nameRange: SourceRange
        if case .identifier(let operationName, _) = current.kind {
            contextType = first
            name = operationName
            nameRange = advance().range
        } else {
            guard first.model == nil, first.arguments.isEmpty else { throw unexpected("an operation name") }
            name = first.name
            nameRange = first.range
        }
        try expect(EOLLanguage.Symbol.openParen)
        var parameters: [EOLParameter] = []
        if !current.isSymbol(EOLLanguage.Symbol.closeParen) {
            repeat {
                parameters.append(try parseParameter())
            } while accept(EOLLanguage.Symbol.comma)
        }
        try expect(EOLLanguage.Symbol.closeParen)
        var returnType: EOLTypeReference?
        if accept(EOLLanguage.Symbol.colon) { returnType = try parseTypeReference() }
        let body = try parseBlock()
        let operation = EOLOperation(
            name: name, contextType: contextType, parameters: parameters, returnType: returnType, body: body,
            annotations: annotations, range: range(from: start), nameRange: nameRange, document: document)
        outline.append(
            OutlineNode(
                id: "operation:\(contextType?.description ?? ""):\(name):\(outline.count)", kind: EOLOutlineKind.operation,
                name: name, detail: contextType?.description, range: operation.range, selectionRange: nameRange))
        return operation
    }

    /// Parses `name` or `name : Type`.
    ///
    /// - Returns: The parameter.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseParameter() throws -> EOLParameter {
        let (name, nameRange) = try expectName()
        var type: EOLTypeReference?
        if accept(EOLLanguage.Symbol.colon) { type = try parseTypeReference() }
        return EOLParameter(name: name, type: type, range: range(from: nameRange))
    }

    /// Parses a type reference.
    ///
    /// Accepted forms are `Name`, `Model!Name`, `pkg::Name`, `Model!pkg::Name`,
    /// `Sequence(T)`, `Sequence<T>`, `Map(K, V)` and `Map<K, V>`.
    ///
    /// - Returns: The type reference.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseTypeReference() throws -> EOLTypeReference {
        let start = current.range
        var (name, _) = try expectTypeName()
        var model: String?
        if accept(EOLLanguage.Symbol.bang) {
            model = name
            (name, _) = try expectTypeName()
        }
        while accept(EOLLanguage.Symbol.packageSeparator) {
            let (part, _) = try expectTypeName()
            name += EOLLanguage.Symbol.packageSeparator + part
        }
        var arguments: [EOLTypeReference] = []
        if model == nil, EOLTypes.isParameterisable(name), peek(1).name != nil {
            let closing: String?
            if accept(EOLLanguage.Symbol.openParen) {
                closing = EOLLanguage.Symbol.closeParen
            } else if accept(EOLLanguage.Symbol.less) {
                closing = EOLLanguage.Symbol.greater
            } else {
                closing = nil
            }
            if let closing {
                repeat { arguments.append(try parseTypeReference()) } while accept(EOLLanguage.Symbol.comma)
                try expect(closing)
            }
        }
        if model == nil, name == EOLLanguage.TypeName.native {
            throw error(
                .nativeUnsupported, "Java interoperability ('Native') is not supported", at: range(from: start))
        }
        return EOLTypeReference(model: model, name: name, arguments: arguments, range: range(from: start))
    }

    /// Consumes a type name, which may be any identifier.
    private mutating func expectTypeName() throws -> (String, SourceRange) {
        guard case .identifier(let name, _) = current.kind else { throw unexpected("a type name") }
        return (name, advance().range)
    }

    // MARK: - Statements

    /// Parses a statement block in braces.
    ///
    /// - Returns: The statements.
    /// - Throws: ``EOLError`` if the opening brace is missing.
    package mutating func parseBlock() throws -> EOLBlock {
        try expect(EOLLanguage.Symbol.openBrace)
        let statements = parseStatements(until: EOLLanguage.Symbol.closeBrace)
        try expect(EOLLanguage.Symbol.closeBrace)
        return statements
    }

    /// Parses statements until a closing symbol, recovering from errors.
    ///
    /// - Parameter closing: The symbol that ends the list (not consumed).
    /// - Returns: The statements that parsed correctly.
    package mutating func parseStatements(until closing: String) -> EOLBlock {
        var statements: EOLBlock = []
        while !isAtEnd, !current.isSymbol(closing) {
            let start = position
            do {
                if let statement = try parseStatementInBlock() { statements.append(statement) }
            } catch let failure as EOLError {
                record(failure)
                synchronise(from: start)
            } catch {
                synchronise(from: start)
            }
        }
        return statements
    }

    /// Parses a block in braces, or a single statement.
    ///
    /// - Returns: The statements.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseStatementOrBlock() throws -> EOLBlock {
        if current.isSymbol(EOLLanguage.Symbol.openBrace) { return try parseBlock() }
        guard let statement = try parseStatementInBlock() else { return [] }
        return [statement]
    }

    /// Parses one statement, skipping template section ends.
    ///
    /// - Returns: The statement, or `nil` if only a separator was consumed.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseStatementInBlock() throws -> EOLStatement? {
        if current.kind == .templateClose {
            advance()
            return nil
        }
        return try parseStatement()
    }

    /// Parses one statement.
    ///
    /// - Returns: The statement.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseStatement() throws -> EOLStatement {
        let start = current.range
        switch current.kind {
        case .templateText(let text):
            advance()
            return EOLStatement(.templateText(text), range: start)
        case .templateOutput:
            advance()
            let value = try parseExpression()
            accept(EOLLanguage.Symbol.semicolon)
            if current.kind == .templateClose { advance() } else if !isAtEnd { throw unexpected("'%]'") }
            return EOLStatement(.templateOutput(value), range: range(from: start))
        default: break
        }
        if current.isSymbol(EOLLanguage.Symbol.openBrace) {
            let block = try parseBlock()
            return EOLStatement(.block(block), range: range(from: start))
        }
        if let word = current.bareName, EOLLanguage.Keyword.all.contains(word) {
            if let statement = try parseKeywordStatement(word, start: start) { return statement }
        }
        return try parseExpressionStatement(start: start)
    }

    /// Parses a statement that starts with a keyword.
    ///
    /// - Parameters:
    ///   - word: The keyword.
    ///   - start: The range of the keyword.
    /// - Returns: The statement, or `nil` if the keyword starts an expression.
    /// - Throws: ``EOLError`` on a syntax error.
    private mutating func parseKeywordStatement(_ word: String, start: SourceRange) throws -> EOLStatement? {
        typealias K = EOLLanguage.Keyword
        switch word {
        case K.variable, K.external:
            advance()
            return try parseVariableDeclaration(start: start)
        case K.if:
            advance()
            try expect(EOLLanguage.Symbol.openParen)
            let condition = try parseExpression()
            try expect(EOLLanguage.Symbol.closeParen)
            let then = try parseStatementOrBlock()
            var otherwise: EOLBlock?
            if acceptWord(K.else) { otherwise = try parseStatementOrBlock() }
            return EOLStatement(.if(condition, then, otherwise), range: range(from: start))
        case K.while:
            advance()
            try expect(EOLLanguage.Symbol.openParen)
            let condition = try parseExpression()
            try expect(EOLLanguage.Symbol.closeParen)
            let body = try parseStatementOrBlock()
            return EOLStatement(.while(condition, body), range: range(from: start))
        case K.for:
            advance()
            try expect(EOLLanguage.Symbol.openParen)
            let iterator = try parseParameter()
            try expectWord(K.in)
            let collection = try parseExpression()
            try expect(EOLLanguage.Symbol.closeParen)
            let body = try parseStatementOrBlock()
            return EOLStatement(.for(iterator, collection, body), range: range(from: start))
        case K.switch:
            advance()
            return try parseSwitch(start: start)
        case K.return:
            advance()
            var value: EOLExpression?
            if !isStatementEnd { value = try parseExpression() }
            try expectStatementEnd()
            return EOLStatement(.return(value), range: range(from: start))
        case K.break, K.breakAll, K.continue:
            advance()
            try expectStatementEnd()
            let kind: EOLStatement.Kind = word == K.break ? .break : word == K.breakAll ? .breakAll : .continue
            return EOLStatement(kind, range: range(from: start))
        case K.throw:
            advance()
            var value: EOLExpression?
            if !isStatementEnd { value = try parseExpression() }
            try expectStatementEnd()
            return EOLStatement(.throw(value), range: range(from: start))
        case K.delete:
            advance()
            let target = try parseExpression()
            try expectStatementEnd()
            return EOLStatement(.delete(target), range: range(from: start))
        case K.transaction, K.abort:
            throw error(.unsupportedConstruct, "The '\(word)' statement is not supported", at: start)
        default:
            return nil
        }
    }

    /// Whether the current token ends a statement.
    private var isStatementEnd: Bool {
        current.isSymbol(EOLLanguage.Symbol.semicolon) || current.kind == .templateClose
            || current.isSymbol(EOLLanguage.Symbol.closeBrace)
    }

    /// Consumes a statement terminator.
    ///
    /// A semicolon may be left out before the end of a template code section.
    private mutating func expectStatementEnd() throws {
        if accept(EOLLanguage.Symbol.semicolon) { return }
        if current.kind == .templateClose { return }
        throw unexpected("';'")
    }

    /// Parses the rest of a `var` declaration.
    private mutating func parseVariableDeclaration(start: SourceRange) throws -> EOLStatement {
        let (name, _) = try expectName()
        var type: EOLTypeReference?
        var creates = false
        var arguments: [EOLExpression] = []
        var value: EOLExpression?
        if accept(EOLLanguage.Symbol.colon) {
            creates = acceptWord(EOLLanguage.Keyword.new)
            type = try parseTypeReference()
            if creates, accept(EOLLanguage.Symbol.openParen) { arguments = try parseArguments() }
        }
        let special = current.isSymbol(EOLLanguage.Symbol.specialAssign)
        if accept(EOLLanguage.Symbol.equals) || accept(EOLLanguage.Symbol.colonEquals)
            || accept(EOLLanguage.Symbol.specialAssign)
        {
            value = try parseExpression()
        }
        try expectStatementEnd()
        return EOLStatement(
            .variable(name: name, type: type, creates: creates, arguments: arguments, value: value, special: special),
            range: range(from: start))
    }

    /// Parses the rest of a `switch` statement.
    private mutating func parseSwitch(start: SourceRange) throws -> EOLStatement {
        try expect(EOLLanguage.Symbol.openParen)
        let subject = try parseExpression()
        try expect(EOLLanguage.Symbol.closeParen)
        try expect(EOLLanguage.Symbol.openBrace)
        var cases: [EOLSwitchCase] = []
        var fallback: EOLBlock?
        while !current.isSymbol(EOLLanguage.Symbol.closeBrace), !isAtEnd {
            if acceptWord(EOLLanguage.Keyword.case) {
                let value = try parseExpression()
                try expect(EOLLanguage.Symbol.colon)
                cases.append(EOLSwitchCase(value: value, body: parseCaseBody()))
            } else if acceptWord(EOLLanguage.Keyword.default) {
                try expect(EOLLanguage.Symbol.colon)
                fallback = parseCaseBody()
            } else {
                throw unexpected("'case' or 'default'")
            }
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        return EOLStatement(.switch(subject, cases, fallback), range: range(from: start))
    }

    /// Parses the statements of a `case` up to the next case, default or closing brace.
    private mutating func parseCaseBody() -> EOLBlock {
        var statements: EOLBlock = []
        while !isAtEnd, !current.isSymbol(EOLLanguage.Symbol.closeBrace), !current.isWord(EOLLanguage.Keyword.case),
            !current.isWord(EOLLanguage.Keyword.default)
        {
            let start = position
            do {
                if let statement = try parseStatementInBlock() { statements.append(statement) }
            } catch let failure as EOLError {
                record(failure)
                synchronise(from: start)
            } catch {
                synchronise(from: start)
            }
        }
        return statements
    }

    /// Parses an expression statement, an assignment, or an increment.
    private mutating func parseExpressionStatement(start: SourceRange) throws -> EOLStatement {
        let target = try parseExpression(statementHead: true)
        typealias S = EOLLanguage.Symbol
        let operators: [(String, EOLAssignmentOperator)] = [
            (S.equals, .assign), (S.colonEquals, .assign), (S.specialAssign, .special), (S.plusAssign, .add),
            (S.minusAssign, .subtract), (S.timesAssign, .multiply), (S.divideAssign, .divide),
            (S.elvisAssign, .ifUndefined),
        ]
        for (symbol, assignment) in operators where current.isSymbol(symbol) {
            advance()
            try checkAssignable(target)
            let value = try parseExpression()
            try expectStatementEnd()
            return EOLStatement(.assignment(target, assignment, value), range: range(from: start))
        }
        if current.isSymbol(S.increment) || current.isSymbol(S.decrement) {
            let token = advance()
            try checkAssignable(target)
            try expectStatementEnd()
            let one = EOLExpression(.literal(.integer(1)), range: token.range)
            let assignment: EOLAssignmentOperator = token.isSymbol(S.increment) ? .add : .subtract
            return EOLStatement(.assignment(target, assignment, one), range: range(from: start))
        }
        try expectStatementEnd()
        return EOLStatement(.expression(target), range: range(from: start))
    }

    /// Checks that an expression can be assigned to.
    private func checkAssignable(_ target: EOLExpression) throws {
        switch target.kind {
        case .name, .property, .item: return
        default: throw error(.unexpectedToken, "The left-hand side of an assignment must be a variable, property or item", at: target.range)
        }
    }

    // MARK: - Expressions

    /// Parses an expression.
    ///
    /// - Parameter statementHead: Whether the expression starts a statement, in which case
    ///   a single `=` at the top level is left for the assignment.
    /// - Returns: The expression.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseExpression(statementHead: Bool = false) throws -> EOLExpression {
        let condition = try parseLogical(statementHead: statementHead)
        if accept(EOLLanguage.Symbol.elvis) {
            let fallback = try parseExpression()
            return EOLExpression(.elvis(condition, fallback), range: range(from: condition.range))
        }
        if accept(EOLLanguage.Symbol.question) {
            let whenTrue = try parseExpression()
            if !accept(EOLLanguage.Symbol.colon), !acceptWord(EOLLanguage.Keyword.else) {
                throw unexpected("':' or 'else'")
            }
            let whenFalse = try parseExpression()
            return EOLExpression(.conditional(condition, whenTrue, whenFalse), range: range(from: condition.range))
        }
        return condition
    }

    /// Parses logical operators, which share one precedence level and associate to the left.
    private mutating func parseLogical(statementHead: Bool) throws -> EOLExpression {
        var left = try parseRelational(statementHead: statementHead)
        while let word = current.bareName,
            let op = [EOLBinaryOperator.and, .or, .xor, .implies].first(where: { $0.rawValue == word })
        {
            advance()
            let right = try parseRelational(statementHead: statementHead)
            left = EOLExpression(.binary(op, left, right), range: range(from: left.range))
        }
        return left
    }

    /// Parses relational operators.
    private mutating func parseRelational(statementHead: Bool) throws -> EOLExpression {
        var left = try parseAdditive()
        typealias S = EOLLanguage.Symbol
        while true {
            let op: EOLBinaryOperator
            switch current.symbol {
            case S.equals?:
                if statementHead { return left }
                op = .equal
            case S.doubleEquals?: op = .equal
            case S.notEquals?, S.bangEquals?: op = .notEqual
            case S.less?: op = .less
            case S.greater?: op = .greater
            case S.lessOrEqual?: op = .lessOrEqual
            case S.greaterOrEqual?: op = .greaterOrEqual
            default: return left
            }
            advance()
            let right = try parseAdditive()
            left = EOLExpression(.binary(op, left, right), range: range(from: left.range))
        }
    }

    /// Parses additive operators.
    private mutating func parseAdditive() throws -> EOLExpression {
        var left = try parseMultiplicative()
        while current.isSymbol(EOLLanguage.Symbol.plus) || current.isSymbol(EOLLanguage.Symbol.minus) {
            let op: EOLBinaryOperator = advance().isSymbol(EOLLanguage.Symbol.plus) ? .plus : .minus
            let right = try parseMultiplicative()
            left = EOLExpression(.binary(op, left, right), range: range(from: left.range))
        }
        return left
    }

    /// Parses multiplicative operators.
    private mutating func parseMultiplicative() throws -> EOLExpression {
        var left = try parseUnary()
        while current.isSymbol(EOLLanguage.Symbol.times) || current.isSymbol(EOLLanguage.Symbol.divide) {
            let op: EOLBinaryOperator = advance().isSymbol(EOLLanguage.Symbol.times) ? .times : .divide
            let right = try parseUnary()
            left = EOLExpression(.binary(op, left, right), range: range(from: left.range))
        }
        return left
    }

    /// Parses unary operators.
    private mutating func parseUnary() throws -> EOLExpression {
        let start = current.range
        if acceptWord(EOLLanguage.Keyword.not) {
            let operand = try parseUnary()
            return EOLExpression(.unary(.not, operand), range: range(from: start))
        }
        if accept(EOLLanguage.Symbol.minus) {
            let operand = try parseUnary()
            return EOLExpression(.unary(.negate, operand), range: range(from: start))
        }
        return try parsePostfix()
    }

    /// Parses navigation and item selectors after a primary expression.
    private mutating func parsePostfix() throws -> EOLExpression {
        var expression = try parsePrimary()
        typealias S = EOLLanguage.Symbol
        while true {
            let navigation: EOLNavigation
            if accept(S.dot) {
                navigation = .dot
            } else if accept(S.safeDot) {
                navigation = .safeDot
            } else if accept(S.arrow) {
                navigation = .arrow
            } else if current.isSymbol(S.openBracket) {
                advance()
                let index = try parseExpression()
                try expect(S.closeBracket)
                expression = EOLExpression(.item(expression, index), range: range(from: expression.range))
                continue
            } else {
                return expression
            }
            let extended = accept(S.tilde)
            guard case .identifier(let name, _) = current.kind else { throw unexpected("a property or operation name") }
            advance()
            if !extended, accept(S.openParen) {
                if looksLikeIterator() {
                    let (iterators, bodies) = try parseFirstOrderArguments()
                    expression = EOLExpression(
                        .firstOrder(target: expression, name: name, iterators: iterators, bodies: bodies, navigation: navigation),
                        range: range(from: expression.range))
                } else {
                    let arguments = try parseArguments()
                    expression = EOLExpression(
                        .call(target: expression, name: name, arguments: arguments, navigation: navigation),
                        range: range(from: expression.range))
                }
            } else {
                expression = EOLExpression(
                    .property(target: expression, name: name, navigation: navigation, extended: extended),
                    range: range(from: expression.range))
            }
        }
    }

    /// Whether the tokens after an opening parenthesis declare a first-order iterator.
    private func looksLikeIterator() -> Bool {
        var probe = self
        do {
            _ = try probe.expectName()
            if probe.accept(EOLLanguage.Symbol.colon) { _ = try probe.parseTypeReference() }
            return probe.current.isSymbol(EOLLanguage.Symbol.pipe)
        } catch {
            return false
        }
    }

    /// Parses `iterator | body (, body)*)` after the opening parenthesis.
    private mutating func parseFirstOrderArguments() throws -> ([EOLParameter], [EOLExpression]) {
        let iterator = try parseParameter()
        try expect(EOLLanguage.Symbol.pipe)
        var bodies = [try parseExpression()]
        while accept(EOLLanguage.Symbol.comma) { bodies.append(try parseExpression()) }
        try expect(EOLLanguage.Symbol.closeParen)
        return ([iterator], bodies)
    }

    /// Parses call arguments after the opening parenthesis, including the closing one.
    ///
    /// - Returns: The arguments.
    /// - Throws: ``EOLError`` on a syntax error.
    package mutating func parseArguments() throws -> [EOLExpression] {
        var arguments: [EOLExpression] = []
        if !current.isSymbol(EOLLanguage.Symbol.closeParen) {
            repeat { arguments.append(try parseExpression()) } while accept(EOLLanguage.Symbol.comma)
        }
        try expect(EOLLanguage.Symbol.closeParen)
        return arguments
    }

    /// Parses a primary expression.
    private mutating func parsePrimary() throws -> EOLExpression {
        let start = current.range
        typealias S = EOLLanguage.Symbol
        typealias K = EOLLanguage.Keyword
        switch current.kind {
        case .string(let text):
            advance()
            return EOLExpression(.literal(.string(text)), range: start)
        case .integer(let value):
            advance()
            return EOLExpression(.literal(.integer(value)), range: start)
        case .real(let value):
            advance()
            return EOLExpression(.literal(.real(value)), range: start)
        case .symbol(S.openParen):
            advance()
            let inner = try parseExpression()
            try expect(S.closeParen)
            return EOLExpression(inner.kind, range: range(from: start))
        case .symbol(S.hash):
            advance()
            let (literal, _) = try expectTypeName()
            return EOLExpression(.enumerationLiteral(nil, literal), range: range(from: start))
        case .identifier(let name, let quoted):
            if !quoted {
                switch name {
                case K.true, K.false:
                    advance()
                    return EOLExpression(.literal(.boolean(name == K.true)), range: start)
                case K.null:
                    advance()
                    return EOLExpression(.literal(.undefined), range: start)
                case K.new:
                    return try parseNew()
                default:
                    if K.all.contains(name) { throw unexpected("an expression") }
                }
            }
            return try parseNamePrimary(name, start: start)
        default:
            throw unexpected("an expression")
        }
    }

    /// Parses a primary expression that starts with a name.
    private mutating func parseNamePrimary(_ name: String, start: SourceRange) throws -> EOLExpression {
        typealias S = EOLLanguage.Symbol
        let next = peek(1)
        if next.isSymbol(S.bang) || next.isSymbol(S.packageSeparator) {
            let type = try parseTypeReference()
            if accept(S.hash) {
                let (literal, _) = try expectTypeName()
                return EOLExpression(.enumerationLiteral(type, literal), range: range(from: start))
            }
            return EOLExpression(.type(type), range: type.range)
        }
        if next.isSymbol(S.hash) {
            advance()
            advance()
            let (literal, _) = try expectTypeName()
            let type = EOLTypeReference(name: name, range: start)
            return EOLExpression(.enumerationLiteral(type, literal), range: range(from: start))
        }
        if EOLTypes.isCollectionLiteralType(name), next.isSymbol(S.openBrace) || next.isSymbol(S.openParen) || next.isSymbol(S.less) {
            if let literal = try parseCollectionLiteral(name, start: start) { return literal }
        }
        advance()
        if accept(S.openParen) {
            if name == EOLLanguage.TypeName.native {
                throw error(.nativeUnsupported, "Java interoperability ('Native') is not supported", at: start)
            }
            let arguments = try parseArguments()
            return EOLExpression(.call(target: nil, name: name, arguments: arguments, navigation: .dot), range: range(from: start))
        }
        return EOLExpression(.name(name), range: start)
    }

    /// Parses a collection or map literal, or returns `nil` if the tokens are a type reference instead.
    private mutating func parseCollectionLiteral(_ name: String, start: SourceRange) throws -> EOLExpression? {
        let saved = position
        let type = try parseTypeReference()
        guard accept(EOLLanguage.Symbol.openBrace) else {
            if !type.arguments.isEmpty { return EOLExpression(.type(type), range: type.range) }
            position = saved
            return nil
        }
        if type.name == EOLLanguage.TypeName.map {
            var entries: [EOLMapEntry] = []
            if !current.isSymbol(EOLLanguage.Symbol.closeBrace) {
                repeat {
                    let key = try parseAdditive()
                    try expect(EOLLanguage.Symbol.equals)
                    let value = try parseExpression()
                    entries.append(EOLMapEntry(key: key, value: value))
                } while accept(EOLLanguage.Symbol.comma)
            }
            try expect(EOLLanguage.Symbol.closeBrace)
            return EOLExpression(.map(type, entries), range: range(from: start))
        }
        var items: [EOLCollectionItem] = []
        if !current.isSymbol(EOLLanguage.Symbol.closeBrace) {
            repeat {
                let first = try parseExpression()
                if accept(EOLLanguage.Symbol.range) {
                    items.append(.range(first, try parseExpression()))
                } else {
                    items.append(.element(first))
                }
            } while accept(EOLLanguage.Symbol.comma)
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        return EOLExpression(.collection(type, items), range: range(from: start))
    }

    /// Parses `new Type` or `new Type(arguments)`.
    private mutating func parseNew() throws -> EOLExpression {
        let start = advance().range
        let type = try parseTypeReference()
        var arguments: [EOLExpression] = []
        if accept(EOLLanguage.Symbol.openParen) { arguments = try parseArguments() }
        return EOLExpression(.new(type, arguments), range: range(from: start))
    }
}
