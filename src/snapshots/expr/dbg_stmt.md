# META
~~~ini
description=Debug expression stmt
type=expr
~~~
# SOURCE
~~~roc
dbg x
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented or doesn't have a proper error report yet: canonicalize dbg expression
Let us know if you want to help!

# TOKENS
~~~zig
KwDbg(1:1-1:4),LowerIdent(1:5-1:6),EndOfFile(1:6-1:6),
~~~
# PARSE
~~~clojure
(e-dbg
	(e-ident @1.5-1.6 (qaul "") (raw "x")))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-runtime-error (tag "not_implemented") (id 74))
~~~
# TYPES
~~~clojure
(expr (id 74) (type "Error"))
~~~
