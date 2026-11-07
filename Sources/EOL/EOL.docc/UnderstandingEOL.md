# Understanding EOL

How the module parses, resolves and evaluates Epsilon Object Language programs.

## Overview

EOL is the imperative core of the Epsilon family (Kolovos, Paige and Polack,
"The Epsilon Object Language (EOL)", ECMDA-FA 2006). It combines an
OCL-like expression language with statements, user-defined operations and
access to the elements of one or more models. The constructs this module
supports are listed in <doc:LanguageCoverage>.

## Parsing and diagnostics

The lexer and parser are hand-written and recover from errors, so a program with
mistakes still yields a module, an outline and highlighting tokens. Each
problem is a `SourceDiagnostic` with a code from ``EOLDiagnosticCode``, a
message, and a line and column. ``EOLParseResult/hasErrors`` tells whether any
diagnostic is an error, and ``EOLParseResult/get()`` turns errors into a thrown
``EOLError``.

Constructs that are recognised but not supported, such as `transaction` or
`Native`, are reported as diagnostics rather than being silently ignored.

## Models and types

An ``EOLModel`` pairs a swift-ecore `Resource` with the metamodel packages that
define its types. Programs name a type as `Type`, `pkg::Type` or `Model!Type`.
An unqualified name resolves in the first model that defines it. `Type.all`,
`allInstances`, `allOfKind` and `allOfType` enumerate elements, and element
properties are read and written through the metamodel's features.

## Evaluation

``EOLInterpreter`` evaluates statements in nested scopes. Operations are
dispatched on the type of their receiver, preferring an exact match over the
first compatible one in declaration order. Collections and maps have reference
semantics, and indices start at zero.

Errors raised by `throw`, by failed operation pre- and postconditions or by the
runtime are thrown as ``EOLError``. Imported modules are read through an
`EOLModuleLoading` value, which defaults to the file system.

## Extending the interpreter

The dialect modules plug into the interpreter through ``EOLExtension``, which
adds operations and special assignments. ``EOLHostObject`` lets Swift values
appear in programs as variables with their own properties and operations.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:LanguageCoverage>
