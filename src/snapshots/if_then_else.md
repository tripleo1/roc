# META
~~~ini
description=Example if-then-else statement
type=file
~~~
# SOURCE
~~~roc
module [foo]

foo = if true A

    else {
    B
    }
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize if_then_else expression

# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:12),CloseSquare(1:12-1:13),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(3:1-3:4),OpAssign(3:5-3:6),KwIf(3:7-3:9),LowerIdent(3:10-3:14),UpperIdent(3:15-3:16),Newline(1:1-1:1),
Newline(1:1-1:1),
KwElse(5:5-5:9),OpenCurly(5:10-5:11),Newline(1:1-1:1),
UpperIdent(6:5-6:6),Newline(1:1-1:1),
CloseCurly(7:5-7:6),EndOfFile(7:6-7:6),
~~~
# PARSE
~~~clojure
(file (1:1-7:6)
	(module (1:1-1:13)
		(exposes (1:8-1:13) (exposed_item (lower_ident "foo"))))
	(statements
		(decl (3:1-7:6)
			(ident (3:1-3:4) "foo")
			(if_then_else (3:7-7:6)
				(ident (3:10-3:14) "" "true")
				(tag (3:15-3:16) "A")
				(block (5:10-7:6)
					(statements (tag (6:5-6:6) "B")))))))
~~~
# FORMATTED
~~~roc
module [foo]

foo = if true A

	else {
		B
	}
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (3:1-3:4)
				(pid 72)
				(ident "foo")))
		(def_expr (e_runtime_error (1:1-1:1) "not_implemented"))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "foo" 75 (type "Error")))
	(expressions
		(expr (3:7-7:6) 74 (type "Error"))))
~~~