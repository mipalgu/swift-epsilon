//
//  EGXGeneratorTests.swift
//  EGLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL
import EpsilonTestSupport
import Foundation
import Testing

@testable import EGL

/// The templates that the EGX tests generate from.
let templateSources: [String: String] = [
    "book.egl": "Title: [%= title %]\nPages: [%= pages %]\n[%= out.preserve('//', '', 'notes', true, 'none') %]\n",
    "index.egl": "[% for (b in Book.all) { %]\n[%= b.title %]\n[% } %]\n",
    "publication.egl": "[%= p.title %]\n",
    "broken.egl": "ok\n[%= %]\n",
]

/// A finished EGX run.
struct Generation {
    /// The result of the generator.
    let result: EGXResult
    /// The files after the run.
    let files: [String: String]
    /// What the module printed.
    let output: String
}

/// Parses and runs an EGX module against the library model.
///
/// - Parameters:
///   - source: The module text.
///   - files: The files that exist before the run.
/// - Returns: The result, the files and the printed text.
/// - Throws: ``EOLError`` for parse or run-time errors.
func generate(_ source: String, files: [String: String] = [:]) async throws -> Generation {
    let module = try EGXSyntax.parse(source, document: "test.egx").get()
    let output = EOLStringOutput()
    let interpreter = EOLInterpreter(models: [try await EpsilonFixtures.library()], output: output, errorOutput: output)
    let fileSystem = EGXInMemoryFileSystem(files: files)
    let generator = EGXGenerator(interpreter: interpreter, templateLoader: EOLInMemoryModuleLoader(templateSources), fileSystem: fileSystem)
    let result = try await generator.generate(module)
    return Generation(result: result, files: fileSystem.files, output: output.text)
}

@Suite("EGX generation")
struct EGXGeneratorTests {
    static let bookModule = """
        pre { var count = 0; }
        rule Book2Text transform b : Book {
          guard : b.pages > 400
          parameters : Map{"title" = b.title, "pages" = b.pages}
          template : "book.egl"
          target : "books/" + b.title + ".txt"
          post { count = count + 1; generated.println(); }
        }
        post { ('generated ' + count).println(); }
        """

    @Test("One file is generated per matching element, with parameters and guard")
    func perElement() async throws {
        let run = try await generate(Self.bookModule)
        #expect(run.files.keys.sorted() == ["books/Dune.txt", "books/Emma.txt"])
        #expect(run.files["books/Dune.txt"] == "Title: Dune\nPages: 412\n// protected region notes on begin\nnone\n// protected region notes end\n")
        #expect(run.result.files.map(\.status) == [.created, .created])
        #expect(run.output == "books/Dune.txt\nbooks/Emma.txt\ngenerated 2\n")
    }

    @Test("Regeneration keeps an enabled protected region and reports the file as updated or unchanged")
    func mergePreservesRegion() async throws {
        let edited = "Title: Old\nPages: 1\n// protected region notes on begin\nmy own notes\n// protected region notes end\n"
        let current = "Title: Emma\nPages: 474\n// protected region notes on begin\nnone\n// protected region notes end\n"
        let run = try await generate(Self.bookModule, files: ["books/Dune.txt": edited, "books/Emma.txt": current])
        #expect(run.files["books/Dune.txt"] == "Title: Dune\nPages: 412\n// protected region notes on begin\nmy own notes\n// protected region notes end\n")
        #expect(run.result.files.map(\.status) == [.updated, .unchanged])
    }

    @Test("merge : false replaces protected regions")
    func noMerge() async throws {
        let edited = "// protected region notes on begin\nmy own notes\n// protected region notes end\n"
        let module = Self.bookModule.replacingOccurrences(of: "  template :", with: "  merge : false\n  template :")
        let run = try await generate(module, files: ["books/Dune.txt": edited])
        #expect(run.files["books/Dune.txt"]?.contains("my own notes") == false)
    }

    @Test("overwrite : false leaves an existing file alone")
    func noOverwrite() async throws {
        let module = Self.bookModule.replacingOccurrences(of: "  template :", with: "  overwrite : false\n  template :")
        let run = try await generate(module, files: ["books/Dune.txt": "keep me"])
        #expect(run.files["books/Dune.txt"] == "keep me")
        #expect(run.result.files.map(\.status) == [.skipped, .created])
    }

    @Test("A rule without transform runs once")
    func singleRule() async throws {
        let run = try await generate("rule Index { template : \"index.egl\" target : \"index.txt\" }")
        #expect(run.files["index.txt"] == "Dune\nCosmos\nEmma\n")
    }

    @Test("Rules match direct instances unless @greedy")
    func greedy() async throws {
        let plain = try await generate(
            "rule P transform p : Publication { parameters : Map{\"p\" = p} template : \"publication.egl\" target : p.title + \".txt\" }")
        #expect(plain.files.isEmpty)
        let greedy = try await generate(
            "@greedy\nrule P transform p : Publication { parameters : Map{\"p\" = p} template : \"publication.egl\" target : p.title + \".txt\" }")
        #expect(greedy.files.count == 4)
        #expect(greedy.files["Nature Weekly.txt"] == "Nature Weekly\n")
    }

    @Test("An explicit domain and block-valued properties are supported")
    func domainAndBlocks() async throws {
        let run = try await generate(
            """
            rule Fiction transform b : Book in : Book.all.select(x | x.genre = #fiction) {
              pre { var stem = b.title.toLowerCase(); }
              parameters { return Map{"p" = b}; }
              template { return "publication.egl"; }
              target { return "fiction/" + stem + ".md"; }
            }
            """)
        #expect(run.files.keys.sorted() == ["fiction/dune.md", "fiction/emma.md"])
    }

    @Test("A rule without a target generates text without writing it")
    func noTarget() async throws {
        let run = try await generate("rule Index { template : \"index.egl\" post { generated.print(); } }")
        #expect(run.files.isEmpty)
        #expect(run.result.files.first?.status == .notWritten)
        #expect(run.output == "Dune\nCosmos\nEmma\n")
    }

    @Test("Templates are given only their parameters, not the rule's variables")
    func templateScope() async {
        await #expect(throws: EOLError.self) {
            _ = try await generate("rule R transform b : Book { template : \"publication.egl\" target : b.title }")
        }
    }

    @Test("Syntax errors in EGX modules are reported with positions")
    func syntaxErrors() {
        let result = EGXSyntax.parse("rule R transform b : Book {\n  templat : \"x.egl\"\n}\nrule S { }", document: "bad.egx")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.range?.start.line == 2)
        #expect(result.diagnostics.first?.range?.start.column == 3)
        #expect(result.diagnostics.first?.message.contains("templat") == true)
        #expect(result.module.rules.map(\.name) == ["S"])
        #expect(result.outline.map(\.name) == ["S"])
    }

    @Test("Generation errors carry codes", arguments: [
        ("rule R { target : \"x\" }", EOLDiagnosticCode.invalidDeclaration),
        ("rule R { template : \"missing.egl\" }", .fileAccess),
        ("rule R transform b : Book { guard : 1 template : \"index.egl\" }", .typeMismatch),
        ("rule R { parameters : Sequence{} template : \"index.egl\" }", .typeMismatch),
        ("rule R { template : \"broken.egl\" }", .unexpectedToken),
    ])
    func generationErrors(source: String, code: EOLDiagnosticCode) async {
        do {
            _ = try await generate(source)
            Issue.record("expected an error for \(source)")
        } catch let error as EOLError {
            #expect(error.code == code.rawValue, "\(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A template error reports the template document and position")
    func templateErrorLocation() async {
        do {
            _ = try await generate("rule R { template : \"broken.egl\" }")
            Issue.record("expected a template error")
        } catch let error as EOLError {
            #expect(error.diagnostic.document == "broken.egl")
            #expect(error.range?.start.line == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Files are written below a base directory")
    func directoryFileSystem() throws {
        let scratch = EpsilonFixtures.url("Library.ecore").deletingLastPathComponent()
        let base = scratch.appendingPathComponent("EGXOutput-\(UUID().uuidString)")
        let fileSystem = EGXDirectoryFileSystem(base: base)
        #expect(try fileSystem.read("a/b.txt") == nil)
        try fileSystem.write("hello", to: "a/b.txt")
        #expect(try fileSystem.read("a/b.txt") == "hello")
    }

    @Test("The directory file system rejects paths that lead outside its directory")
    func directoryConfinement() throws {
        let scratch = EpsilonFixtures.url("Library.ecore").deletingLastPathComponent()
        let base = scratch.appendingPathComponent("EGXConfinement-\(UUID().uuidString)")
        let fileSystem = EGXDirectoryFileSystem(base: base)
        for path in ["../escape.txt", "a/../../escape.txt", "/etc/escape.txt"] {
            #expect(throws: EOLError.self) { try fileSystem.write("x", to: path) }
        }
        #expect(throws: Never.self) { try fileSystem.write("x", to: "a/../inside.txt") }
        let trusting = EGXDirectoryFileSystem(base: base, allowsPathsOutsideBase: true)
        #expect(try trusting.url(for: "../outside.txt").lastPathComponent == "outside.txt")
    }
}
