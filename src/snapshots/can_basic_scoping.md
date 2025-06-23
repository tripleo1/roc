# META
~~~ini
description=Basic variable scoping behavior
type=file
~~~
# SOURCE
~~~roc
module []

# Top-level variables
x = 5
y = 10

# Function that shadows outer variable
outerFunc = |_| {
    x = 20  # Should shadow top-level x
    innerResult = {
        # Block scope
        z = x + y  # x should resolve to 20, y to 10
        z + 1
    }
    innerResult
}
~~~
# PROBLEMS
**DUPLICATE DEFINITION**
The name `x` is being redeclared in this scope.

The redeclaration is here:
**can_basic_scoping.md:9:5:9:6:**
```roc
    x = 20  # Should shadow top-level x
```

But `x` was already defined here:
**can_basic_scoping.md:4:1:4:2:**
```roc
x = 5
```


# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),CloseSquare(1:9-1:10),Newline(1:1-1:1),
Newline(1:1-1:1),
Newline(3:2-3:22),
LowerIdent(4:1-4:2),OpAssign(4:3-4:4),Int(4:5-4:6),Newline(1:1-1:1),
LowerIdent(5:1-5:2),OpAssign(5:3-5:4),Int(5:5-5:7),Newline(1:1-1:1),
Newline(1:1-1:1),
Newline(7:2-7:39),
LowerIdent(8:1-8:10),OpAssign(8:11-8:12),OpBar(8:13-8:14),Underscore(8:14-8:15),OpBar(8:15-8:16),OpenCurly(8:17-8:18),Newline(1:1-1:1),
LowerIdent(9:5-9:6),OpAssign(9:7-9:8),Int(9:9-9:11),Newline(9:14-9:40),
LowerIdent(10:5-10:16),OpAssign(10:17-10:18),OpenCurly(10:19-10:20),Newline(1:1-1:1),
Newline(11:10-11:22),
LowerIdent(12:9-12:10),OpAssign(12:11-12:12),LowerIdent(12:13-12:14),OpPlus(12:15-12:16),LowerIdent(12:17-12:18),Newline(12:21-12:53),
LowerIdent(13:9-13:10),OpPlus(13:11-13:12),Int(13:13-13:14),Newline(1:1-1:1),
CloseCurly(14:5-14:6),Newline(1:1-1:1),
LowerIdent(15:5-15:16),Newline(1:1-1:1),
CloseCurly(16:1-16:2),EndOfFile(16:2-16:2),
~~~
# PARSE
~~~clojure
(file (1:1-16:2)
	(module (1:1-1:10) (exposes (1:8-1:10)))
	(statements
		(decl (4:1-4:6)
			(ident (4:1-4:2) "x")
			(int (4:5-4:6) "5"))
		(decl (5:1-5:7)
			(ident (5:1-5:2) "y")
			(int (5:5-5:7) "10"))
		(decl (8:1-16:2)
			(ident (8:1-8:10) "outerFunc")
			(lambda (8:13-16:2)
				(args (underscore))
				(block (8:17-16:2)
					(statements
						(decl (9:5-9:11)
							(ident (9:5-9:6) "x")
							(int (9:9-9:11) "20"))
						(decl (10:5-14:6)
							(ident (10:5-10:16) "innerResult")
							(block (10:19-14:6)
								(statements
									(decl (12:9-13:10)
										(ident (12:9-12:10) "z")
										(binop (12:13-13:10)
											"+"
											(ident (12:13-12:14) "" "x")
											(ident (12:17-12:18) "" "y")))
									(binop (13:9-14:6)
										"+"
										(ident (13:9-13:10) "" "z")
										(int (13:13-13:14) "1")))))
						(ident (15:5-15:16) "" "innerResult")))))))
~~~
# FORMATTED
~~~roc
module []

# Top-level variables
x = 5
y = 10

# Function that shadows outer variable
outerFunc = |_| {
	x = 20 # Should shadow top-level x
	innerResult = {
		# Block scope
		z = x + y # x should resolve to 20, y to 10
		z + 1
	}
	innerResult
}
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (4:1-4:2)
				(pid 72)
				(ident "x")))
		(def_expr
			(e_int (4:5-4:6)
				(int_var 74)
				(precision_var 73)
				(literal "5")
				(value "TODO")
				(bound "u8"))))
	(d_let
		(def_pattern
			(p_assign (5:1-5:2)
				(pid 77)
				(ident "y")))
		(def_expr
			(e_int (5:5-5:7)
				(int_var 79)
				(precision_var 78)
				(literal "10")
				(value "TODO")
				(bound "u8"))))
	(d_let
		(def_pattern
			(p_assign (8:1-8:10)
				(pid 82)
				(ident "outerFunc")))
		(def_expr
			(e_lambda (8:13-16:2)
				(args (p_underscore (8:14-8:15) (pid 83)))
				(e_block (8:17-16:2)
					(s_let (9:5-9:11)
						(p_assign (9:5-9:6)
							(pid 84)
							(ident "x"))
						(e_int (9:9-9:11)
							(int_var 87)
							(precision_var 86)
							(literal "20")
							(value "TODO")
							(bound "u8")))
					(s_let (10:5-14:6)
						(p_assign (10:5-10:16)
							(pid 90)
							(ident "innerResult"))
						(e_block (10:19-14:6)
							(s_let (12:9-13:10)
								(p_assign (12:9-12:10)
									(pid 91)
									(ident "z"))
								(e_binop (12:13-13:10)
									"add"
									(e_lookup (12:13-12:14) (pid 84))
									(e_lookup (12:17-12:18) (pid 77))))
							(e_binop (13:9-14:6)
								"add"
								(e_lookup (13:9-13:10) (pid 91))
								(e_int (13:13-13:14)
									(int_var 98)
									(precision_var 97)
									(literal "1")
									(value "TODO")
									(bound "u8")))))
					(e_lookup (15:5-15:16) (pid 90)))))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "x" 76 (type "Num(Int(*))"))
		(def "y" 81 (type "Num(Int(*))"))
		(def "outerFunc" 106 (type "*")))
	(expressions
		(expr (4:5-4:6) 75 (type "Num(Int(*))"))
		(expr (5:5-5:7) 80 (type "Num(Int(*))"))
		(expr (8:13-16:2) 105 (type "*"))))
~~~