//
//  EpsilonFixtures.swift
//  EpsilonTestSupport
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL
import Foundation

/// Neutral, self-authored metamodels and models shared by the Epsilon test suites.
public enum EpsilonFixtures {
    /// The location of a fixture file.
    ///
    /// - Parameter name: The file name, including its extension.
    /// - Returns: The file URL inside the test resources.
    public static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")
            ?? Bundle.module.resourceURL!.appendingPathComponent("Resources").appendingPathComponent(name)
    }

    /// Loads the library model (books, a magazine and authors).
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - resourceSet: The [`ResourceSet`](https://mipalgu.github.io/swift-ecore/documentation/ecore/resourceset/) to load into.
    /// - Returns: The model.
    /// - Throws: The error of the loader.
    public static func library(named name: String = "Library", in resourceSet: ResourceSet = ResourceSet()) async throws
        -> EOLModel
    {
        try await EOLModel.load(
            name: name, url: url("Library.xmi"), metamodels: [url("Library.ecore")], resourceSet: resourceSet)
    }

    /// Loads the tree model.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - resourceSet: The [`ResourceSet`](https://mipalgu.github.io/swift-ecore/documentation/ecore/resourceset/) to load into.
    /// - Returns: The model.
    /// - Throws: The error of the loader.
    public static func tree(named name: String = "Tree", in resourceSet: ResourceSet = ResourceSet()) async throws
        -> EOLModel
    {
        try await EOLModel.load(name: name, url: url("Tree.xmi"), metamodels: [url("Tree.ecore")], resourceSet: resourceSet)
    }

    /// Creates an empty graph model.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - resourceSet: The [`ResourceSet`](https://mipalgu.github.io/swift-ecore/documentation/ecore/resourceset/) to create the model in.
    /// - Returns: The model.
    /// - Throws: The error of the metamodel loader.
    public static func emptyGraph(named name: String = "Graph", in resourceSet: ResourceSet = ResourceSet()) async throws
        -> EOLModel
    {
        let packages = try await ModelIO.registerMetamodels(at: [url("Graph.ecore")], in: resourceSet)
        return await EOLModel.empty(name: name, packages: packages, resourceSet: resourceSet, uri: "memory:/graph.xmi")
    }

    /// Creates an empty annotation model.
    ///
    /// The annotation metamodel has references typed with `EObject`, single- and many-valued,
    /// containment and not, a reference typed with the Ecore class `EClass`, and a reference
    /// typed with a class of a separate base metamodel whose subclass it defines.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - resourceSet: The [`ResourceSet`](https://mipalgu.github.io/swift-ecore/documentation/ecore/resourceset/) to create the model in.
    /// - Returns: The model.
    /// - Throws: The error of the metamodel loader.
    public static func emptyAnnotations(named name: String = "Annotations", in resourceSet: ResourceSet = ResourceSet())
        async throws -> EOLModel
    {
        let packages = try await ModelIO.registerMetamodels(
            at: [url("Base.ecore"), url("Annotation.ecore")], in: resourceSet)
        return await EOLModel.empty(name: name, packages: packages, resourceSet: resourceSet, uri: "memory:/annotations.xmi")
    }

    /// Runs an EOL program and returns what it printed.
    ///
    /// - Parameters:
    ///   - source: The program text.
    ///   - models: The models the program accesses.
    ///   - loader: How imports are read.
    /// - Returns: The printed text.
    /// - Throws: ``EOLError`` for parse or run-time errors.
    public static func run(
        _ source: String, models: [EOLModel] = [], loader: any EOLModuleLoading = EOLInMemoryModuleLoader([:])
    ) async throws -> String {
        let module = try EOLSyntax.parse(source, document: "test.eol").get()
        let output = EOLStringOutput()
        let interpreter = EOLInterpreter(models: models, output: output, errorOutput: output, moduleLoader: loader)
        try await interpreter.run(module)
        return output.text
    }

    /// Runs an EOL program and returns the error it raised.
    ///
    /// - Parameters:
    ///   - source: The program text.
    ///   - models: The models the program accesses.
    /// - Returns: The error, or `nil` if the program succeeded.
    public static func failure(_ source: String, models: [EOLModel] = []) async -> EOLError? {
        do {
            _ = try await run(source, models: models)
            return nil
        } catch let error as EOLError {
            return error
        } catch {
            return EOLError(.userError, "\(error)")
        }
    }
}
