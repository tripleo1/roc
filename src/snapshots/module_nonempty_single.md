# META
~~~ini
description=An empty module with singleline exposes
type=file
~~~
# SOURCE
~~~roc
module [something, SomeType]
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:18),Comma(1:18-1:19),UpperIdent(1:20-1:28),CloseSquare(1:28-1:29),EndOfFile(1:29-1:29),
~~~
# PARSE
~~~clojure
(file (1:1-1:29)
	(module (1:1-1:29)
		(exposes (1:8-1:29)
			(exposed_item (lower_ident "something"))
			(exposed_item (upper_ident "SomeType"))))
	(statements))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(can_ir "empty")
~~~
# TYPES
~~~clojure
(inferred_types (defs) (expressions))
~~~