# ``ETL``

Transform Ecore models with the Epsilon Transformation Language.

## Overview

ETL rules transform elements of source models into elements of target models
(Kolovos, Paige and Polack,
"[The Epsilon Transformation Language](https://doi.org/10.1007/978-3-540-69927-9_4)", ICMT 2008).
``ETLSyntax`` parses a module, and ``ETLTransformer`` runs it: targets are created
for every match before any rule body runs, and `equivalent()`, `equivalents()`
and the special assignment `::=` resolve source elements to their targets.

```swift
let module = try ETLSyntax.parse(source, document: "tree2graph.etl").get()
let transformer = ETLTransformer(module: module, models: [tree, graph])
try await transformer.transform()
```

The supported subset of ETL is listed in <doc:UnderstandingETL>. Models are loaded
and programs are parsed as described in the EOL documentation.

## Related Documentation

### Command Line and Tutorials

- [swift-epsilon](https://mipalgu.github.io/swift-modelling/documentation/swift_epsilon/index.html) - the command-line tool of swift-modelling
- [Transforming Models and Generating Text with ETL and EGL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-02-etl-egl/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Epsilon Modules

- [EOL](https://mipalgu.github.io/swift-epsilon/documentation/eol/) - the Epsilon Object Language
- [EVL](https://mipalgu.github.io/swift-epsilon/documentation/evl/) - model validation
- [EGL](https://mipalgu.github.io/swift-epsilon/documentation/egl/) - text generation from templates

### Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/documentation/ecore/) - the Ecore metamodels and models that programs work on
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - command-line tools and tutorials for the whole toolkit

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingETL>

### Transforming

- ``ETLSyntax``
- ``ETLTransformer``
- ``ETLTrace``
- ``ETLTraceLink``

### Syntax Tree

- ``ETLModule``
- ``ETLRule``
