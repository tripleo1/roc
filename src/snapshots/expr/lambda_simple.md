# META
~~~ini
description=Lambda expression
type=expr
~~~
# SOURCE
~~~roc
|x| x + 1
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:3),OpBar(1:3-1:4),LowerIdent(1:5-1:6),OpPlus(1:7-1:8),Int(1:9-1:10),EndOfFile(1:10-1:10),
~~~
# PARSE
~~~clojure
(lambda (1:1-1:10)
	(args (ident (1:2-1:3) "x"))
	(binop (1:5-1:10)
		"+"
		(ident (1:5-1:6) "" "x")
		(int (1:9-1:10) "1")))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_lambda (1:1-1:10)
	(args
		(p_assign (1:2-1:3)
			(pid 72)
			(ident "x")))
	(e_binop (1:5-1:10)
		"add"
		(e_lookup (1:5-1:6) (pid 72))
		(e_int (1:9-1:10)
			(int_var 75)
			(precision_var 74)
			(literal "1")
			(value "TODO")
			(bound "u8"))))
~~~
# TYPES
~~~clojure
(expr 78 (type "*"))
~~~