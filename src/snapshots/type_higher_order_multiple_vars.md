# META
~~~ini
description=Higher-order function with multiple type variables
type=file
~~~
# SOURCE
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

compose : (b -> c), (a -> b) -> (a -> c)
compose = |f, g| |x| f(g(x))

main! = |_| {}
~~~
# PROBLEMS
**UNEXPECTED TOKEN IN EXPRESSION**
The token **, (** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**type_higher_order_multiple_vars.md:3:19:3:22:**
```roc
compose : (b -> c), (a -> b) -> (a -> c)
```


**PARSE ERROR**
A parsing error occurred: `expr_arrow_expects_ident`
This is an unexpected parsing error. Please check your syntax.
Here is the problematic code:
**type_higher_order_multiple_vars.md:3:33:3:35:**
```roc
compose : (b -> c), (a -> b) -> (a -> c)
```


**UNEXPECTED TOKEN IN EXPRESSION**
The token  is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize record expression

# TOKENS
~~~zig
KwApp(1:1-1:4),OpenSquare(1:5-1:6),LowerIdent(1:6-1:11),CloseSquare(1:11-1:12),OpenCurly(1:13-1:14),LowerIdent(1:15-1:17),OpColon(1:17-1:18),KwPlatform(1:19-1:27),StringStart(1:28-1:29),StringPart(1:29-1:50),StringEnd(1:50-1:51),CloseCurly(1:52-1:53),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(3:1-3:8),OpColon(3:9-3:10),OpenRound(3:11-3:12),LowerIdent(3:12-3:13),OpArrow(3:14-3:16),LowerIdent(3:17-3:18),CloseRound(3:18-3:19),Comma(3:19-3:20),OpenRound(3:21-3:22),LowerIdent(3:22-3:23),OpArrow(3:24-3:26),LowerIdent(3:27-3:28),CloseRound(3:28-3:29),OpArrow(3:30-3:32),OpenRound(3:33-3:34),LowerIdent(3:34-3:35),OpArrow(3:36-3:38),LowerIdent(3:39-3:40),CloseRound(3:40-3:41),Newline(1:1-1:1),
LowerIdent(4:1-4:8),OpAssign(4:9-4:10),OpBar(4:11-4:12),LowerIdent(4:12-4:13),Comma(4:13-4:14),LowerIdent(4:15-4:16),OpBar(4:16-4:17),OpBar(4:18-4:19),LowerIdent(4:19-4:20),OpBar(4:20-4:21),LowerIdent(4:22-4:23),NoSpaceOpenRound(4:23-4:24),LowerIdent(4:24-4:25),NoSpaceOpenRound(4:25-4:26),LowerIdent(4:26-4:27),CloseRound(4:27-4:28),CloseRound(4:28-4:29),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(6:1-6:6),OpAssign(6:7-6:8),OpBar(6:9-6:10),Underscore(6:10-6:11),OpBar(6:11-6:12),OpenCurly(6:13-6:14),CloseCurly(6:14-6:15),EndOfFile(6:15-6:15),
~~~
# PARSE
~~~clojure
(file (1:1-6:15)
	(app (1:1-1:53)
		(provides (1:6-1:12) (exposed_item (lower_ident "main!")))
		(record_field (1:15-1:53)
			"pf"
			(string (1:28-1:51) (string_part (1:29-1:50) "../basic-cli/main.roc")))
		(packages (1:13-1:53)
			(record_field (1:15-1:53)
				"pf"
				(string (1:28-1:51) (string_part (1:29-1:50) "../basic-cli/main.roc")))))
	(statements
		(type_anno (3:1-3:20)
			"compose"
			(fn (3:12-3:18)
				(ty_var (3:12-3:13) "b")
				(ty_var (3:17-3:18) "c")))
		(malformed_expr (3:19-3:22) "expr_unexpected_token")
		(malformed_expr (3:33-3:35) "expr_arrow_expects_ident")
		(local_dispatch (3:34-3:41)
			(ident (3:34-3:35) "" "a")
			(ident (3:39-3:40) "" "c"))
		(malformed_expr (1:1-1:1) "expr_unexpected_token")
		(decl (4:1-4:29)
			(ident (4:1-4:8) "compose")
			(lambda (4:11-4:29)
				(args
					(ident (4:12-4:13) "f")
					(ident (4:15-4:16) "g"))
				(lambda (4:18-4:29)
					(args (ident (4:19-4:20) "x"))
					(apply (4:22-4:29)
						(ident (4:22-4:23) "" "f")
						(apply (4:24-4:28)
							(ident (4:24-4:25) "" "g")
							(ident (4:26-4:27) "" "x"))))))
		(decl (6:1-6:15)
			(ident (6:1-6:6) "main!")
			(lambda (6:9-6:15)
				(args (underscore))
				(record (6:13-6:15))))))
~~~
# FORMATTED
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

compose : (b -> c)a->c
compose = |f, g| |x| f(g(x))

main! = |_| {}
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (4:1-4:8)
				(pid 82)
				(ident "compose")))
		(def_expr
			(e_lambda (4:11-4:29)
				(args
					(p_assign (4:12-4:13)
						(pid 83)
						(ident "f"))
					(p_assign (4:15-4:16)
						(pid 84)
						(ident "g")))
				(e_lambda (4:18-4:29)
					(args
						(p_assign (4:19-4:20)
							(pid 85)
							(ident "x")))
					(e_call (4:22-4:29)
						(e_lookup (4:22-4:23) (pid 83))
						(e_call (4:24-4:28)
							(e_lookup (4:24-4:25) (pid 84))
							(e_lookup (4:26-4:27) (pid 85)))))))
		(annotation (4:1-4:8)
			(signature 98)
			(declared_type
				(parens (3:11-3:19)
					(fn (3:12-3:18)
						(ty_var (3:12-3:13) "b")
						(ty_var (3:17-3:18) "c")
						"false")))))
	(d_let
		(def_pattern
			(p_assign (6:1-6:6)
				(pid 101)
				(ident "main!")))
		(def_expr
			(e_lambda (6:9-6:15)
				(args (p_underscore (6:10-6:11) (pid 102)))
				(e_runtime_error (1:1-1:1) "not_implemented")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "compose" 100 (type "*"))
		(def "main!" 106 (type "*")))
	(expressions
		(expr (4:11-4:29) 92 (type "*"))
		(expr (6:9-6:15) 105 (type "*"))))
~~~