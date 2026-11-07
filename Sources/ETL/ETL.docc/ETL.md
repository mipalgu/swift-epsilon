# ``ETL``

Transform Ecore models with the Epsilon Transformation Language.

## Overview

ETL rules transform elements of source models into elements of target models
(Kolovos, Paige and Polack, "The Epsilon Transformation Language", ICMT 2008).
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
