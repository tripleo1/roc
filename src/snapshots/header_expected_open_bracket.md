# META
~~~ini
description=Expected an open bracket for the header
type=file
~~~
# SOURCE
~~~roc
module
~~~
# PROBLEMS
**PARSE ERROR**
A parsing error occurred: `header_expected_open_square`
This is an unexpected parsing error. Please check your syntax.

# TOKENS
~~~zig
KwModule(1:1-1:7),EndOfFile(1:7-1:7),
~~~
# PARSE
~~~clojure
(file (1:1-1:7)
	(malformed_header (1:7-1:7) "header_expected_open_square")
	(statements))
~~~
# FORMATTED
~~~roc

~~~
# CANONICALIZE
~~~clojure
(can_ir "empty")
~~~
# TYPES
~~~clojure
(inferred_types (defs) (expressions))
~~~