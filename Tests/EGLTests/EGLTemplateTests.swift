//
//  EGLTemplateTests.swift
//  EGLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL
import EpsilonTestSupport
import Testing

@testable import EGL

/// Renders template text with a fresh interpreter.
///
/// - Parameters:
///   - text: The template text.
///   - models: The models the template accesses.
///   - variables: The variables the template can read.
/// - Returns: The generated text.
func render(_ text: String, models: [EOLModel] = [], variables: [String: EOLValue] = [:]) async throws -> String {
    let interpreter = EOLInterpreter(models: models, output: EOLStringOutput(), errorOutput: EOLStringOutput())
    return try await EGLTemplateRunner(interpreter: interpreter).render(text, document: "test.egl", variables: variables)
}

/// One template and the text it should generate.
struct TemplateCase: Sendable, CustomTestStringConvertible {
    /// The template.
    let template: String
    /// The expected output.
    let expected: String
    /// A short label for the test report.
    let testDescription: String

    init(_ label: String, _ template: String, _ expected: String) {
        self.template = template
        self.expected = expected
        testDescription = label
    }
}

@Suite("EGL templates")
struct EGLTemplateTests {
    static let goldenCases: [TemplateCase] = [
        TemplateCase("static text", "Hello\nworld\n", "Hello\nworld\n"),
        TemplateCase("output section", "Hi [%= 'Ann' %]!", "Hi Ann!"),
        TemplateCase("output of expressions", "[%= 6 * 7 %] [%= Sequence{1, 2} %]", "42 Sequence {1, 2}"),
        TemplateCase(
            "loop with standalone control lines", "[% for (i in Sequence{1..3}) { %]\ni is [%=i%]\n[% } %]\n",
            "i is 1\ni is 2\ni is 3\n"),
        TemplateCase("indented control lines", "  [% if (true) { %]\n  yes\n  [% } %]\nend\n", "  yes\nend\n"),
        TemplateCase("inline code is kept on its line", "a [% var x = 1; %]b[%= x %]\n", "a b1\n"),
        TemplateCase("comments", "a[* note *]b\n[* whole line *]\nc\n", "ab\nc\n"),
        TemplateCase(
            "ordinary operation", "[% operation Integer twice() : Integer { return self * 2; } %]\n[%= 21.twice() %]\n", "42\n"),
        TemplateCase(
            "appending operation",
            "[% operation String line() { %]\n* [%= self %]\n[% } %]\n[% 'a'.line(); 'b'.line(); %]\n", "* a\n* b\n"),
        TemplateCase(
            "@template operation returns its text",
            "[% @template\noperation String greet() { %]\nHello [%= self %]!\n[% } %]\n[%= 'Ann'.greet() %][%= 'Bob'.greet().toUpperCase() %]\n",
            "Hello Ann!\nHELLO BOB!\n\n"),
        TemplateCase(
            "out print, println and chop",
            "[% for (x in Sequence{'a', 'b', 'c'}) { out.print(x + ', '); } out.chop(2); out.println(); out.println('done'); %]",
            "a, b, c\ndone\n"),
        TemplateCase("outdenting close is accepted", "[% if (true) { -%]\nx\n[% } -%]\n", "x\n"),
        TemplateCase("semicolon may be omitted before %]", "[% var n = 3 %][%= n %]", "3"),
    ]

    @Test("Templates generate the expected text", arguments: goldenCases)
    func golden(test: TemplateCase) async throws {
        #expect(try await render(test.template) == test.expected)
    }

    @Test("Variables are passed to the template")
    func variables() async throws {
        #expect(try await render("Hello [%= name %]", variables: ["name": .string("World")]) == "Hello World")
    }

    @Test("Templates navigate models")
    func models() async throws {
        let library = try await EpsilonFixtures.library()
        let output = try await render(
            "[% for (b in Book.all.sortBy(b | b.pages)) { %]\n- [%= b.title %] ([%= b.pages %] pages)\n[% } %]\n",
            models: [library])
        #expect(output == "- Cosmos (396 pages)\n- Dune (412 pages)\n- Emma (474 pages)\n")
    }

    @Test("Several renderings with one runner keep separate output")
    func repeatedRendering() async throws {
        let runner = EGLTemplateRunner(interpreter: EOLInterpreter(output: EOLStringOutput()))
        let template = try EGLSyntax.parse("[%= n %];", document: "n.egl").get()
        let first = try await runner.render(template, variables: ["n": .integer(1)])
        let second = try await runner.render(template, variables: ["n": .integer(2)])
        #expect(first == "1;")
        #expect(second == "2;")
    }

    @Test("Parse errors are reported with lines and columns", arguments: [
        ("Hello [%= %]\n", 1, 11),
        ("line one\n[% var x = ; %]\n", 2, 12),
        ("[% for (i in Sequence{1..2}) { %]\nx\n", 3, 1),
    ])
    func parseErrors(template: String, line: Int, column: Int) {
        let result = EGLSyntax.parse(template, document: "bad.egl")
        #expect(result.hasErrors)
        #expect(result.diagnostics.first?.range?.start.line == line, "\(result.diagnostics)")
        #expect(result.diagnostics.first?.range?.start.column == column, "\(result.diagnostics)")
        #expect(result.diagnostics.first?.document == "bad.egl")
    }

    @Test("Run-time errors carry the template position")
    func runtimeError() async {
        do {
            _ = try await render("ok\n[%= undefinedName %]\n")
            Issue.record("expected an error")
        } catch let error as EOLError {
            #expect(error.code == EOLDiagnosticCode.unresolvedName.rawValue)
            #expect(error.range?.start.line == 2)
            #expect(error.range?.start.column == 5)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Highlighting distinguishes static text, delimiters and code")
    func highlighting() {
        let kinds = EGLSyntax.tokens(in: "text [%= x %] [% if (true) {} %]").map(\.kind)
        #expect(kinds.contains(.text))
        #expect(kinds.contains(.directive))
        #expect(kinds.contains(.keyword))
        #expect(kinds.contains(.identifier))
    }

    @Test("Template operations appear in the outline")
    func outline() {
        let result = EGLSyntax.parse("[% operation String a() { %]x[% } %]")
        #expect(result.outline.map(\.name) == ["a"])
    }
}
