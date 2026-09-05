# JavaScript LLM editing card

Use this compact card for source edits. It provides the same index-first workflow as
the Neper and Rust cards used by the benchmark.

## Core syntax

```text
import { item } from "./module.js";
export const NAME = value;
export function name(arg, ...) { ... }
const value = expression;
return expression;
```

Declarations and blocks use braces; ordinary statements end in `;`. Comments are
`//`. Functions, values, fields, and modules conventionally use `camelCase`; classes
use `PascalCase`; constants use `SCREAMING_SNAKE`. JavaScript has no static parameter
types: preserve the existing function and module style rather than adding annotations.

ES modules use explicit imports and exports. Keep import paths and extensions as
written. Avoid unrelated formatting changes, dynamic property access, or broad textual
replacement when a resolved call-site list is available.

For the common signature edit shape:

```text
export function adjust(reading, offset) {
    return reading + offset;
}

// after adding gain
export function adjust(reading, gain, offset) {
    return reading * gain + offset;
}

const x = adjust(41.7, 1.0, 0.25);
```

## Tool-assisted navigation

The benchmark exposes a versioned structured index with definition and resolved call
reference records. Use it to locate the target definition and every call site before
reading source. Read only those spans, edit exact occurrences, and validate that no
old call spelling remains.
