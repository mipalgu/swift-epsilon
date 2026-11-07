# Understanding ETL

How a transformation runs, how rules relate source and target elements, and which ETL constructs are supported.

## Overview

ETL rules transform elements of source models into elements of target models
(Kolovos, Paige and Polack, "The Epsilon Transformation Language", ICMT 2008).
Its semantics follow the Epsilon documentation; where the documentation leaves a
detail open, the choice made here is stated.

## Phases

``ETLTransformer/transform()`` runs a transformation in four phases:

1. The `pre` blocks run, and the variables they declare stay visible.
2. For every non-abstract, non-lazy rule in declaration order, each source
   element of the rule's source type whose guards hold is matched, and the
   rule's target elements are created and recorded in the trace. A rule matches
   elements of exactly its source type unless it is `@greedy`, which also
   matches subtypes.
3. The bodies of all matches run in the same order, with the bodies of extended
   rules before the extending rule's own body.
4. The `post` blocks run.

Because every target exists before any body runs, a body can refer to the
targets of other elements regardless of the order of the rules.

## Equivalents

Within rules, `equivalent()` and `equivalents()` resolve a source element to its
targets. Both accept rule names to restrict the rules considered. Primary rules
are tried first, and `@lazy` rules run on demand, once per element.

The special assignment `::=` assigns the equivalent of its right-hand side:
elements map to their first equivalent, and other values stay unchanged.

## The trace

``ETLTransformer/trace`` holds an ``ETLTraceLink`` for every rule application, in
the order the applications happened. ``ETLTrace/links(for:)`` returns the links
of one source element. The trace is available from Swift only; `transTrace` is
not supported inside programs.

## Errors

Inconsistent modules, such as an unknown or cyclic `extends`, a duplicate rule
or an unresolvable type, throw an `EOLError` before any rule runs. Errors raised
in guards, initialisers and bodies are thrown as `EOLError` values.

## Supported constructs

| Construct | Status | Notes |
|:--|:--|:--|
| `rule R transform s : M!A to t : M!B (= init)?, … extends … { guard … body }` | Supported | Targets are created for all matches first, then bodies run; extended rules' bodies run first. |
| `@lazy`, `@primary`, `@abstract`, `@greedy` | Supported | Also accepted as bare words before `rule`. Rules match exact types unless greedy. |
| `equivalent()`, `equivalents()`, named-rule variants | Supported | Primary rules first; lazy rules run on demand once per element. |
| `::=` in assignments and declarations | Supported | Elements map to their first equivalent; other values stay unchanged. |
| `pre`/`post`, operations, `import` | Supported | Imported modules contribute operations only. |
| `transTrace`, `@parallel`, rule overriding from imports | Unsupported | The trace is available from Swift. |

All EOL constructs are available inside guards, bodies and blocks, as listed in
the EOL documentation.

## Topics

### Essentials

- <doc:GettingStarted>
