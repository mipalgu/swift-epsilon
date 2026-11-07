//
//  EOLSyntaxTests.swift
//  EOLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EpsilonTestSupport
import Testing

@testable import EOL

@Suite("EOL lexer")
struct EOLLexerTests {
    @Test("Tokens carry one-based lines and columns")
    func positions() {
        let scan = EOLLexer.scan("var x = 1;\n  x.println();")
        let names = scan.tokens.compactMap(\.name)
        #expect(names == ["var", "x", "x", "println"])
        let printlnToken = scan.tokens.first { $0.name == "println" }
        #expect(printlnToken?.range.start.line == 2)
        #expect(printlnToken?.range.start.column == 5)
    }

    @Test("String escapes are decoded and both quote styles are accepted")
    func strings() {
        let scan = EOLLexer.scan(#"'a\tb' "c\"d" 'eA' 'x\s'"#)
        let strings = scan.tokens.compactMap { token -> String? in
            if case .string(let text) = token.kind { return text }
            return nil
        }
        #expect(strings == ["a\tb", "c\"d", "eA", "x\\s"])
    }

    @Test("Numbers distinguish integers, reals and ranges")
    func numbers() {
        let kinds = EOLLexer.scan("1 2.5 3.0f 4l 1..3 1e3").tokens.map(\.kind)
        #expect(kinds.contains(.integer(1)))
        #expect(kinds.contains(.real(2.5)))
        #expect(kinds.contains(.real(3.0)))
        #expect(kinds.contains(.integer(4)))
        #expect(kinds.contains(.symbol("..")))
        #expect(kinds.contains(.real(1000)))
    }

    @Test("Comments are recorded but not passed to the parser")
    func comments() {
        let scan = EOLLexer.scan("// line\n/* block */ x")
        #expect(scan.comments.count == 2)
        #expect(scan.tokens.compactMap(\.name) == ["x"])
    }

    @Test("An unterminated string is reported at its start")
    func unterminatedString() {
        let scan = EOLLexer.scan("var s = 'abc")
        #expect(scan.diagnostics.first?.code == EOLDiagnosticCode.unterminatedString.rawValue)
        #expect(scan.diagnostics.first?.range?.start.column == 9)
    }

    @Test("An unexpected character is reported with its position")
    func unexpectedCharacter() {
        let scan = EOLLexer.scan("x ^ y")
        #expect(scan.diagnostics.first?.code == EOLDiagnosticCode.unexpectedCharacter.rawValue)
        #expect(scan.diagnostics.first?.range?.start.column == 3)
    }

    @Test("Highlighting classifies keywords, types and literals")
    func highlighting() {
        let tokens = EOLSyntax.tokens(in: "var b : Library!Book = true; // note")
        let kinds = tokens.map(\.kind)
        #expect(kinds.first == .keyword)
        #expect(kinds.contains(.typeName))
        #expect(kinds.contains(.boolean))
        #expect(kinds.last == .comment)
    }
}

@Suite("EOL parser")
struct EOLParserTests {
    /// Parses a single expression statement and returns its expression.
    private func expression(_ text: String) throws -> EOLExpression {
        try EOLSyntax.parseExpression(text)
    }

    @Test("Logical operators share one precedence level and associate to the left")
    func logicalPrecedence() throws {
        guard case .binary(.and, let left, _) = try expression("true or true and false").kind else {
            Issue.record("expected 'and' at the top")
            return
        }
        guard case .binary(.or, _, _) = left.kind else {
            Issue.record("expected 'or' on the left")
            return
        }
    }

    @Test("Multiplication binds tighter than addition, which binds tighter than comparison")
    func arithmeticPrecedence() throws {
        guard case .binary(.less, let left, _) = try expression("1 + 2 * 3 < 10").kind,
            case .binary(.plus, _, let product) = left.kind, case .binary(.times, _, _) = product.kind
        else {
            Issue.record("unexpected tree")
            return
        }
    }

    @Test("A single '=' starting a statement is an assignment, elsewhere equality")
    func assignmentVersusEquality() throws {
        let module = try EOLSyntax.parse("var a = 1; a = 2; var b = a = 2;").get()
        guard case .assignment(_, .assign, _) = module.statements[1].kind else {
            Issue.record("expected an assignment")
            return
        }
        guard case .variable(_, _, _, _, let value?, _) = module.statements[2].kind, case .binary(.equal, _, _) = value.kind else {
            Issue.record("expected equality in the initialiser")
            return
        }
    }

    @Test("Compound and special assignments are recognised", arguments: ["+=", "-=", "*=", "/=", "?=", ":=", "::="])
    func compoundAssignments(op: String) throws {
        let module = try EOLSyntax.parse("var a = 1; a \(op) 2;").get()
        guard case .assignment = module.statements[1].kind else {
            Issue.record("expected an assignment for \(op)")
            return
        }
    }

    @Test("First-order calls are told apart from ordinary calls")
    func firstOrder() throws {
        guard case .firstOrder(_, "select", let iterators, _, _) = try expression("c.select(x : Integer | x > 1)").kind else {
            Issue.record("expected a first-order call")
            return
        }
        #expect(iterators.first?.type?.name == "Integer")
        guard case .call(_, "including", let arguments, _) = try expression("c.including(x)").kind else {
            Issue.record("expected an ordinary call")
            return
        }
        #expect(arguments.count == 1)
    }

    @Test("Model types, package paths and enumeration literals parse as types")
    func modelTypes() throws {
        guard case .property(let target, "all", _, _) = try expression("Library!Book.all").kind,
            case .type(let type) = target.kind
        else {
            Issue.record("expected a type receiver")
            return
        }
        #expect(type.model == "Library")
        #expect(type.name == "Book")
        guard case .enumerationLiteral(let enumeration, "fiction") = try expression("Library!Genre#fiction").kind else {
            Issue.record("expected an enumeration literal")
            return
        }
        #expect(enumeration?.name == "Genre")
        guard case .type(let qualified) = try expression("M!a::b::C").kind else {
            Issue.record("expected a qualified type")
            return
        }
        #expect(qualified.name == "a::b::C")
    }

    @Test("Operations record context type, parameters, return type and annotations")
    func operations() throws {
        let result = EOLSyntax.parse(
            """
            @cached
            operation Library!Book summary(prefix : String) : String { return prefix + self.title; }
            operation twice(x : Integer) : Integer { return 2 * x; }
            """)
        let module = try result.get()
        #expect(module.operations.count == 2)
        let summary = module.operations[0]
        #expect(summary.contextType?.description == "Library!Book")
        #expect(summary.parameters.map(\.name) == ["prefix"])
        #expect(summary.returnType?.name == "String")
        #expect(summary.hasAnnotation("cached"))
        #expect(module.operations[1].contextType == nil)
        #expect(result.outline.map(\.name) == ["summary", "twice"])
        #expect(result.outline[0].selectionRange.start.line == 2)
    }

    @Test("Syntax errors are reported with positions and parsing recovers")
    func recovery() {
        let result = EOLSyntax.parse(
            """
            var a = ;
            var b = 2;
            b.println(;
            "ok".println();
            """)
        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics[0].range?.start.line == 1)
        #expect(result.diagnostics[0].range?.start.column == 9)
        #expect(result.diagnostics[1].range?.start.line == 3)
        #expect(result.module.statements.count == 2)
    }

    @Test("Java interoperability is rejected with a clear diagnostic")
    func nativeRejected() {
        for source in ["var f = new Native('java.io.File');", "var c = Native('java.util.Collections');"] {
            let result = EOLSyntax.parse(source)
            #expect(result.diagnostics.first?.code == EOLDiagnosticCode.nativeUnsupported.rawValue)
            #expect(result.diagnostics.first?.message.contains("not supported") == true)
        }
    }

    @Test("Transactions are reported as unsupported")
    func transactionRejected() {
        let result = EOLSyntax.parse("transaction { var x = 1; }")
        #expect(result.diagnostics.first?.code == EOLDiagnosticCode.unsupportedConstruct.rawValue)
        #expect(result.diagnostics.first?.range?.start.column == 1)
    }

    @Test("Executable annotations parse as expressions")
    func executableAnnotations() throws {
        let module = try EOLSyntax.parse(
            """
            $pre i > 0
            $post _result > i
            operation inc(i : Integer) : Integer { return i + 1; }
            """
        ).get()
        #expect(module.operations[0].annotations.map(\.name) == ["pre", "post"])
        #expect(module.operations[0].annotations.allSatisfy { $0.expression != nil })
    }
}

@Suite("EOL parser regressions from the reference examples")
struct EOLReferenceRegressionTests {
    @Test("'new Sequence()' takes empty constructor arguments, not type arguments")
    func newWithEmptyArguments() async throws {
        #expect(try await EpsilonFixtures.run("var s = new Sequence(); s.add(1); s.println();") == "Sequence {1}\n")
        #expect(try await EpsilonFixtures.run("var s : Sequence(String) = new Sequence(); s.size().println();") == "0\n")
    }

    @Test("Operations without arguments can be called as properties")
    func parameterlessOperationsAsProperties() async throws {
        #expect(try await EpsilonFixtures.run("'hi'.println; Sequence{1, 2}.size.println(); 1.to(3).asSet().size.println('n: ');") == "hi\n2\nn: 3\n")
        #expect(try await EpsilonFixtures.run("1.to(3).aggregate(x | x, x * 10).println();") == "Map {1=10, 2=20, 3=30}\n")
    }
}
