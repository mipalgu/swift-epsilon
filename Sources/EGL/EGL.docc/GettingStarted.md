# Getting Started with EGL

Add the package, render a template, merge protected regions and run EGX rules.

## Overview

The EGL module generates text from models using templates that mix static text
with EOL code, and runs EGX rules that generate one file per model element. This
article shows how to render a template, keep hand-written code when files are
regenerated, and generate files with EGX.

## Add the package

Add swift-epsilon to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main"),
]
```

Then add the `EGL` product, together with `EOL` for loading models, to your
target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EGL", package: "swift-epsilon"),
        .product(name: "EOL", package: "swift-epsilon"),
    ]
)
```

## Parse a template

``EGLSyntax/parse(_:document:)`` recovers from errors and reports positioned
diagnostics:

```swift
import ECore
import EGL
import EOL
import Foundation

let parsed = EGLSyntax.parse(
    "[% for (b in Book.all) { %]\n[%= b.title %]\n[% } %]\n", document: "index.egl")
for diagnostic in parsed.diagnostics {
    print(diagnostic.message)
}
let template = try parsed.get()
```

## Render a template

``EGLTemplateRunner`` renders a template with an `EOLInterpreter` that holds the
models. Variables passed to ``EGLTemplateRunner/render(_:variables:)`` are
visible to the template:

```swift
let library = try await EOLModel.load(
    name: "Library",
    url: URL(fileURLWithPath: "Library.xmi"),
    metamodels: [URL(fileURLWithPath: "Library.ecore")],
    resourceSet: ResourceSet())
let runner = EGLTemplateRunner(interpreter: EOLInterpreter(models: [library]))
let text = try await runner.render(template, variables: ["title": .string("Books")])
```

To parse and render template text in one step, use
``EGLTemplateRunner/render(_:document:variables:)``, which throws the first parse
error.

## Keep hand-written code

A template marks a region for hand-written code with `out.preserve`:

```
[%= out.preserve('//', '', 'notes', true, 'none') %]
```

This produces `// protected region notes on begin`, the default contents and
`// protected region notes end`. When a file is regenerated,
``EGLProtectedRegions/merge(generated:existing:document:)`` keeps the contents of
each enabled region from the existing file:

```swift
let existing = "// protected region notes on begin\nmy own notes\n// protected region notes end\n"
let generated = "// protected region notes on begin\nnone\n// protected region notes end\n"
let merged = EGLProtectedRegions.merge(generated: generated, existing: existing)
print(merged.text)         // keeps "my own notes"
print(merged.diagnostics)  // warnings for regions whose contents were lost
```

## Generate files with EGX

An EGX module declares rules that render a template for each matching element
and write the result to a target path. ``EGXGenerator`` writes through an
``EGXFileSystem``. ``EGXInMemoryFileSystem`` collects files in a dictionary,
which suits tests and previews, and templates can be supplied from memory too:

```swift
let egx = """
    rule Book2Text transform b : Book {
      guard : b.pages > 400
      parameters : Map{"title" = b.title, "pages" = b.pages}
      template : "book.egl"
      target : "books/" + b.title + ".txt"
    }
    """
let module = try EGXSyntax.parse(egx, document: "books.egx").get()
let fileSystem = EGXInMemoryFileSystem()
let generator = EGXGenerator(
    interpreter: EOLInterpreter(models: [library]),
    templateLoader: EOLInMemoryModuleLoader([
        "book.egl": "Title: [%= title %]\nPages: [%= pages %]\n"
    ]),
    fileSystem: fileSystem)
let result = try await generator.generate(module)
for file in result.files {
    print(file.rule, file.path ?? "(no target)", file.status)
}
```

To write real files, use ``EGXDirectoryFileSystem``, which is confined to a
directory by default. Templates are then read relative to the EGX document by
default:

```swift
let generator = EGXGenerator(
    interpreter: EOLInterpreter(models: [library]),
    fileSystem: EGXDirectoryFileSystem(base: URL(fileURLWithPath: "generated")))
```

Each ``EGXGeneratedFile`` reports whether the file was created, updated, left
unchanged or skipped, and ``EGXResult/diagnostics`` holds warnings such as
discarded protected regions.

## Next steps

- <doc:UnderstandingEGL> describes the template syntax, protected regions and
  EGX rules, and lists the supported constructs.
