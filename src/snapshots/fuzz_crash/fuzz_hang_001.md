# META
~~~ini
description=fuzz crash
type=file
~~~
# SOURCE
~~~roc
0 (
~~~
# EXPECTED
MISSING HEADER - fuzz_hang_001.md:1:1:1:2
PARSE ERROR - fuzz_hang_001.md:1:4:1:4
INVALID STATEMENT - fuzz_hang_001.md:1:3:1:4
# PROBLEMS
**MISSING HEADER**
Roc files must start with a module header.

For example:
        module [main]
or for an app:
        app [main!] { pf: platform "../basic-cli/platform.roc" }

Here is the problematic code:
**fuzz_hang_001.md:1:1:1:2:**
```roc
0 (
```
^


**PARSE ERROR**
A parsing error occurred: `expected_expr_close_round_or_comma`
This is an unexpected parsing error. Please check your syntax.

Here is the problematic code:
**fuzz_hang_001.md:1:4:1:4:**
```roc
0 (
```
   


**INVALID STATEMENT**
The statement `expression` is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**fuzz_hang_001.md:1:3:1:4:**
```roc
0 (
```
  ^


# TOKENS
~~~zig
Int(1:1-1:2),OpenRound(1:3-1:4),EndOfFile(1:4-1:4),
~~~
# PARSE
~~~clojure
(file @1.1-1.4
	(malformed-header @1.1-1.2 (tag "missing_header"))
	(statements
		(e-malformed @1.4-1.4 (reason "expected_expr_close_round_or_comma"))))
~~~
# FORMATTED
~~~roc

~~~
# CANONICALIZE
~~~clojure
(can-ir (empty true))
~~~
# TYPES
~~~clojure
(inferred-types
	(defs)
	(expressions))
~~~
