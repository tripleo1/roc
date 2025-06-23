# META
~~~ini
description=Binary operation expression simple addition
type=expr
~~~
# SOURCE
~~~roc
1 + 2
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
Int(1:1-1:2),OpPlus(1:3-1:4),Int(1:5-1:6),EndOfFile(1:6-1:6),
~~~
# PARSE
~~~clojure
(binop (1:1-1:6)
	"+"
	(int (1:1-1:2) "1")
	(int (1:5-1:6) "2"))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_binop (1:1-1:6)
	"add"
	(e_int (1:1-1:2)
		(int_var 73)
		(precision_var 72)
		(literal "1")
		(value "TODO")
		(bound "u8"))
	(e_int (1:5-1:6)
		(int_var 76)
		(precision_var 75)
		(literal "2")
		(value "TODO")
		(bound "u8")))
~~~
# TYPES
~~~clojure
(expr 78 (type "*"))
~~~