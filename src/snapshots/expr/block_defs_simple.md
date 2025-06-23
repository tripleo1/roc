# META
~~~ini
description=Block expression with two decls and final binop expr
type=expr
~~~
# SOURCE
~~~roc
{
    x = 42
    y = x + 1
    y * 2
}
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
OpenCurly(1:1-1:2),Newline(1:1-1:1),
LowerIdent(2:5-2:6),OpAssign(2:7-2:8),Int(2:9-2:11),Newline(1:1-1:1),
LowerIdent(3:5-3:6),OpAssign(3:7-3:8),LowerIdent(3:9-3:10),OpPlus(3:11-3:12),Int(3:13-3:14),Newline(1:1-1:1),
LowerIdent(4:5-4:6),OpStar(4:7-4:8),Int(4:9-4:10),Newline(1:1-1:1),
CloseCurly(5:1-5:2),EndOfFile(5:2-5:2),
~~~
# PARSE
~~~clojure
(block (1:1-5:2)
	(statements
		(decl (2:5-2:11)
			(ident (2:5-2:6) "x")
			(int (2:9-2:11) "42"))
		(decl (3:5-4:6)
			(ident (3:5-3:6) "y")
			(binop (3:9-4:6)
				"+"
				(ident (3:9-3:10) "" "x")
				(int (3:13-3:14) "1")))
		(binop (4:5-5:2)
			"*"
			(ident (4:5-4:6) "" "y")
			(int (4:9-4:10) "2"))))
~~~
# FORMATTED
~~~roc
{
	x = 42
	y = x + 1
	y * 2
}
~~~
# CANONICALIZE
~~~clojure
(e_block (1:1-5:2)
	(s_let (2:5-2:11)
		(p_assign (2:5-2:6)
			(pid 72)
			(ident "x"))
		(e_int (2:9-2:11)
			(int_var 74)
			(precision_var 73)
			(literal "42")
			(value "TODO")
			(bound "u8")))
	(s_let (3:5-4:6)
		(p_assign (3:5-3:6)
			(pid 77)
			(ident "y"))
		(e_binop (3:9-4:6)
			"add"
			(e_lookup (3:9-3:10) (pid 72))
			(e_int (3:13-3:14)
				(int_var 80)
				(precision_var 79)
				(literal "1")
				(value "TODO")
				(bound "u8"))))
	(e_binop (4:5-5:2)
		"mul"
		(e_lookup (4:5-4:6) (pid 77))
		(e_int (4:9-4:10)
			(int_var 86)
			(precision_var 85)
			(literal "2")
			(value "TODO")
			(bound "u8"))))
~~~
# TYPES
~~~clojure
(expr 89 (type "*"))
~~~