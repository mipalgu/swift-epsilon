# ``EOL``

Parse and run programs in the Epsilon Object Language against Ecore models.

## Overview

EOL is the imperative core of the Epsilon family of model management languages
(Kolovos, Paige and Polack,
"[The Epsilon Object Language (EOL)](https://doi.org/10.1007/11787044_11)", ECMDA-FA 2006).
This module provides a hand-written lexer and recovering parser that report
`SourceDiagnostic` values with lines and columns, an outline and
highlighting tokens, and an interpreter that works on the `Resource` actors of
`ECore` models.

```swift
let resourceSet = ResourceSet()
let library = try await EOLModel.load(
    name: "Library", url: modelURL, metamodels: [metamodelURL], resourceSet: resourceSet)
let module = try EOLSyntax.parse(source, document: "report.eol").get()
let interpreter = EOLInterpreter(models: [library])
try await interpreter.run(module)
```

The dialect modules EVL, ETL and EGL build on the parser and interpreter of this
module. The supported subset of EOL is listed in <doc:LanguageCoverage>.

## Topics

### Parsing

- ``EOLSyntax``
- ``EOLParseResult``
- ``EOLModule``
- ``EOLOperation``
- ``EOLStatement``
- ``EOLExpression``
- ``EOLTypeReference``

### Running

- ``EOLInterpreter``
- ``EOLModel``
- ``EOLValue``
- ``EOLType``
- ``EOLExtension``
- ``EOLHostObject``

### Diagnostics

- ``EOLError``
- ``EOLDiagnosticCode``

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingEOL>
- <doc:LanguageCoverage>
