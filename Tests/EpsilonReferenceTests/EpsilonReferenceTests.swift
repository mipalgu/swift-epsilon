//
//  EpsilonReferenceTests.swift
//  EpsilonReferenceTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EGL
import EOL
import ETL
import ECore
import EVL
import Foundation
import Testing

/// The environment variable that names a directory of Epsilon reference sources.
private let referenceVariable = "EPSILON_REFERENCE_DIR"

/// The reference directory, if the comparison was requested.
private var referenceDirectory: URL? {
    ProcessInfo.processInfo.environment[referenceVariable].map { URL(fileURLWithPath: $0, isDirectory: true) }
}

/// A parser for one file extension.
struct ReferenceLanguage: Sendable {
    /// The file extension.
    let fileExtension: String
    /// Parses source text and returns its diagnostics.
    let parse: @Sendable (String, String) -> [SourceDiagnostic]
}

/// The languages compared, by file extension.
let referenceLanguages: [ReferenceLanguage] = [
    ReferenceLanguage(fileExtension: "eol") { EOLSyntax.parse($0, document: $1).diagnostics },
    ReferenceLanguage(fileExtension: "evl") { EVLSyntax.parse($0, document: $1).diagnostics },
    ReferenceLanguage(fileExtension: "etl") { ETLSyntax.parse($0, document: $1).diagnostics },
    ReferenceLanguage(fileExtension: "egl") { EGLSyntax.parse($0, document: $1).diagnostics },
    ReferenceLanguage(fileExtension: "egx") { EGXSyntax.parse($0, document: $1).diagnostics },
]

/// Opt-in comparison with the public Epsilon examples.
///
/// The suite runs only when `EPSILON_REFERENCE_DIR` names a directory, for example a
/// checkout of the `examples` folder of the Epsilon repository. It parses every source
/// file of the supported languages and prints how many parse without errors, with the
/// first diagnostic of each file that does not. Unsupported constructs (such as Java
/// interoperability) are counted separately because they are reported deliberately.
@Suite("Epsilon reference comparison", .enabled(if: referenceDirectory != nil))
struct EpsilonReferenceTests {
    @Test("Reference sources parse", arguments: referenceLanguages.map(\.fileExtension))
    func parse(fileExtension: String) throws {
        let directory = try #require(referenceDirectory).resolvingSymlinksInPath()
        let language = try #require(referenceLanguages.first { $0.fileExtension == fileExtension })
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == fileExtension }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
        var clean = 0
        var unsupported = 0
        var failures: [String] = []
        for file in files {
            guard let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else { continue }
            let relative = file.resolvingSymlinksInPath().path.replacingOccurrences(of: directory.path + "/", with: "")
            let errors = language.parse(text, relative).filter { $0.severity == .error }
            if errors.isEmpty {
                clean += 1
            } else if errors.allSatisfy({
                $0.code == EOLDiagnosticCode.nativeUnsupported.rawValue || $0.code == EOLDiagnosticCode.unsupportedConstruct.rawValue
            }) {
                unsupported += 1
                failures.append("  unsupported \(relative): \(errors[0].message)")
            } else {
                let place = errors[0].range.map { "\($0.start.line):\($0.start.column)" } ?? "?"
                failures.append("  error \(relative):\(place): \(errors[0].message)")
            }
        }
        print("[reference] \(fileExtension): \(clean)/\(files.count) clean, \(unsupported) deliberately unsupported")
        for line in failures { print("[reference]\(line)") }
        #expect(files.count > 0, "no .\(fileExtension) files below \(directory.path)")
    }

    @Test("Reference EOL programs run without models")
    func runWithoutModels() async throws {
        let directory = try #require(referenceDirectory).resolvingSymlinksInPath()
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "eol" }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
        var completed = 0
        var needModels = 0
        var lines: [String] = []
        for file in files {
            guard let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)),
                let module = try? EOLSyntax.parse(text, document: file.absoluteString).get()
            else { continue }
            let relative = file.resolvingSymlinksInPath().path.replacingOccurrences(of: directory.path + "/", with: "")
            let outcome = await Self.run(module)
            switch outcome {
            case nil:
                completed += 1
            case let error? where [EOLDiagnosticCode.unresolvedType.rawValue, EOLDiagnosticCode.unresolvedName.rawValue,
                EOLDiagnosticCode.importFailed.rawValue].contains(error.code):
                needModels += 1
            case let error?:
                lines.append("  \(relative): \(error)")
            }
        }
        print("[reference] eol run: \(completed) completed, \(needModels) need models or imports, \(lines.count) other errors")
        for line in lines { print("[reference]\(line)") }
    }

    /// Runs a module without models, stopping it after two seconds.
    ///
    /// - Parameter module: The module.
    /// - Returns: The error it raised, or `nil` if it completed.
    private static func run(_ module: EOLModule) async -> EOLError? {
        await withTaskGroup(of: EOLError?.self) { group in
            group.addTask {
                let output = EOLStringOutput()
                let interpreter = EOLInterpreter(output: output, errorOutput: output)
                do {
                    try await interpreter.run(module)
                    return nil
                } catch let error as EOLError {
                    return error
                } catch {
                    return EOLError(.userError, "\(error)")
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return EOLError(.cancelled, "Timed out")
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test("The reference Tree2Graph transformation runs on its own models")
    func treeToGraph() async throws {
        let examples = try #require(referenceDirectory).resolvingSymlinksInPath()
        let metamodels = examples.appendingPathComponent("org.eclipse.epsilon.examples.metamodels")
        let example = examples.appendingPathComponent("org.eclipse.epsilon.examples.tree2graph")
        let resourceSet = ResourceSet()
        let tree = try await EOLModel.load(
            name: "Tree", url: example.appendingPathComponent("tree.model"),
            metamodels: [metamodels.appendingPathComponent("Tree.ecore")], resourceSet: resourceSet)
        let graphPackages = try await ModelIO.registerMetamodels(
            at: [metamodels.appendingPathComponent("Graph.ecore")], in: resourceSet)
        let graph = await EOLModel.empty(name: "Graph", packages: graphPackages, resourceSet: resourceSet, uri: "memory:/graph.model")
        let source = try String(contentsOf: example.appendingPathComponent("Tree2Graph.etl"), encoding: .utf8)
        let module = try ETLSyntax.parse(source, document: "Tree2Graph.etl").get()
        let output = EOLStringOutput()
        let transformer = ETLTransformer(module: module, models: [tree, graph], output: output, errorOutput: output)
        try await transformer.transform()
        let summary = try await EOLInterpreter(models: [graph], output: output).run(
            EOLSyntax.parse(
                """
                return Graph!Node.all.collect(n | n.name).concat(',') + ' | '
                    + Graph!Edge.all.collect(e | e.source.name + '->' + e.target.name).concat(',');
                """
            ).get())
        print("[reference] Tree2Graph: \(summary)")
        #expect(summary == .string("t1,t2 | t1->t2"))
    }
}
