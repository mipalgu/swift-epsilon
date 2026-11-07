//
//  EGLProtectedRegionTests.swift
//  EGLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL
import Testing

@testable import EGL

@Suite("EGL protected regions")
struct EGLProtectedRegionTests {
    @Test("preserve with explicit delimiters emits start marker, contents and end marker")
    func preserveExplicit() async throws {
        let output = try await render("[%=out.preserve('/*', '*/', 'body', true, 'default code')%]\n")
        #expect(output == "/* protected region body on begin */\ndefault code\n/* protected region body end */\n")
    }

    @Test("setContentType selects the comment style", arguments: [
        ("Java", "// protected region r off begin\nx\n// protected region r end\n"),
        ("HTML", "<!-- protected region r off begin -->\nx\n<!-- protected region r end -->\n"),
        ("EGL", "[* protected region r off begin *]\nx\n[* protected region r end *]\n"),
    ])
    func contentTypes(type: String, expected: String) async throws {
        let output = try await render("[% out.setContentType('\(type)'); %]\n[%=out.preserve('r', false, 'x')%]\n")
        #expect(output == expected)
    }

    @Test("startPreserve and stopPreserve enclose template text")
    func startStop() async throws {
        let output = try await render("[%=out.startPreserve('//', '', 'x', true)%]\nkeep [%= 1 + 1 %]\n[%=out.stopPreserve()%]\ntail\n")
        #expect(output == "// protected region x on begin\nkeep 2\n// protected region x end\ntail\n")
    }

    @Test("Misused region operations are reported", arguments: [
        "[%= out.stopPreserve() %]",
        "[%= out.preserve('r', true, 'x') %]",
        "[% out.setContentType('Cobol'); %]",
        "[%= out.preserve('//', '', 'r', 'yes', 'x') %]",
    ])
    func misuse(template: String) async {
        await #expect(throws: EOLError.self) { try await render(template) }
    }

    static let generated = "a\n// protected region r on begin\ngenerated\n// protected region r end\nb\n"

    @Test("An enabled existing region keeps the user's contents")
    func keepsEnabled() {
        let existing = "old a\n// protected region r on begin\nuser code\n// protected region r end\nold b\n"
        let merged = EGLProtectedRegions.merge(generated: Self.generated, existing: existing)
        #expect(merged.text == "a\n// protected region r on begin\nuser code\n// protected region r end\nb\n")
        #expect(merged.diagnostics.isEmpty)
    }

    @Test("A disabled existing region is regenerated")
    func regeneratesDisabled() {
        let existing = "a\n// protected region r off begin\nuser code\n// protected region r end\nb\n"
        let merged = EGLProtectedRegions.merge(generated: Self.generated, existing: existing)
        #expect(merged.text == Self.generated)
    }

    @Test("A region the user enabled survives even if generated disabled")
    func userEnabledWins() {
        let generatedOff = "// protected region r off begin\ndefault\n// protected region r end\n"
        let existing = "// protected region r on begin\nmine\n// protected region r end\n"
        let merged = EGLProtectedRegions.merge(generated: generatedOff, existing: existing)
        #expect(merged.text == existing)
    }

    @Test("Enabled regions that are no longer generated are reported")
    func lostRegions() {
        let existing = "// protected region gone on begin\nwork\n// protected region gone end\n"
            + "// protected region idle off begin\nx\n// protected region idle end\n"
        let merged = EGLProtectedRegions.merge(generated: "fresh\n", existing: existing, document: "out.txt")
        #expect(merged.text == "fresh\n")
        #expect(merged.diagnostics.count == 1)
        #expect(merged.diagnostics.first?.severity == .warning)
        #expect(merged.diagnostics.first?.message.contains("gone") == true)
        #expect(merged.diagnostics.first?.document == "out.txt")
    }

    @Test("Unterminated regions are treated as ordinary text")
    func unterminated() {
        #expect(EGLProtectedRegions.regions(in: "// protected region x on begin\nno end\n").isEmpty)
        let regions = EGLProtectedRegions.regions(in: Self.generated)
        #expect(regions.map(\.id) == ["r"])
        #expect(regions.first?.contents == "generated\n")
        #expect(regions.first?.isEnabled == true)
    }
}
