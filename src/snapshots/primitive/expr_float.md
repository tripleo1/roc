# META
~~~ini
description=A primitive
type=file
~~~
# SOURCE
~~~roc
module [foo]
foo = 12.34
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:12),CloseSquare(1:12-1:13),Newline(1:1-1:1),
LowerIdent(2:1-2:4),OpAssign(2:5-2:6),Float(2:7-2:12),EndOfFile(2:12-2:12),
~~~
# PARSE
~~~clojure
(file (1:1-2:12)
	(module (1:1-1:13)
		(exposes (1:8-1:13) (exposed_item (lower_ident "foo"))))
	(statements
		(decl (2:1-2:12)
			(ident (2:1-2:4) "foo")
			(float (2:7-2:12) "12.34"))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (2:1-2:4)
				(pid 72)
				(ident "foo")))
		(def_expr
			(e_float (2:7-2:12)
				(frac_var 74)
				(precision_var 73)
				(literal "12.34")
				(value "0")
				(bound "f32")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "foo" 76 (type "Num(FloatingPoint(*))")))
	(expressions
		(expr (2:7-2:12) 75 (type "Num(FloatingPoint(*))"))))
~~~