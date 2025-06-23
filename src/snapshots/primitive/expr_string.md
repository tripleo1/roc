# META
~~~ini
description=A primitive
type=file
~~~
# SOURCE
~~~roc
module [foo]
name = "luc"
foo = "hello ${name}"
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:12),CloseSquare(1:12-1:13),Newline(1:1-1:1),
LowerIdent(2:1-2:5),OpAssign(2:6-2:7),StringStart(2:8-2:9),StringPart(2:9-2:12),StringEnd(2:12-2:13),Newline(1:1-1:1),
LowerIdent(3:1-3:4),OpAssign(3:5-3:6),StringStart(3:7-3:8),StringPart(3:8-3:14),OpenStringInterpolation(3:14-3:16),LowerIdent(3:16-3:20),CloseStringInterpolation(3:20-3:21),StringPart(3:21-3:21),StringEnd(3:21-3:22),EndOfFile(3:22-3:22),
~~~
# PARSE
~~~clojure
(file (1:1-3:22)
	(module (1:1-1:13)
		(exposes (1:8-1:13) (exposed_item (lower_ident "foo"))))
	(statements
		(decl (2:1-2:13)
			(ident (2:1-2:5) "name")
			(string (2:8-2:13) (string_part (2:9-2:12) "luc")))
		(decl (3:1-3:22)
			(ident (3:1-3:4) "foo")
			(string (3:7-3:22)
				(string_part (3:8-3:14) "hello ")
				(ident (3:16-3:20) "" "name")
				(string_part (3:21-3:21) "")))))
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
			(p_assign (2:1-2:5)
				(pid 72)
				(ident "name")))
		(def_expr
			(e_string (2:8-2:13) (e_literal (2:9-2:12) "luc"))))
	(d_let
		(def_pattern
			(p_assign (3:1-3:4)
				(pid 76)
				(ident "foo")))
		(def_expr
			(e_string (3:7-3:22)
				(e_literal (3:8-3:14) "hello ")
				(e_lookup (3:16-3:20) (pid 72))
				(e_literal (3:21-3:21) "")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "name" 75 (type "Str"))
		(def "foo" 81 (type "Str")))
	(expressions
		(expr (2:8-2:13) 74 (type "Str"))
		(expr (3:7-3:22) 80 (type "Str"))))
~~~