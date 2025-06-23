# META
~~~ini
description=Effectful function type with fat arrow syntax
type=file
~~~
# SOURCE
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

runEffect! : (a => b), a => b
runEffect! = |fn!, x| fn!(x)

main! = |_| {}
~~~
# PROBLEMS
**UNEXPECTED TOKEN IN EXPRESSION**
The token **, a** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**type_function_effectful.md:3:22:3:25:**
```roc
runEffect! : (a => b), a => b
```


**UNEXPECTED TOKEN IN EXPRESSION**
The token **=> b** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**type_function_effectful.md:3:26:3:30:**
```roc
runEffect! : (a => b), a => b
```


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
LowerIdent(3:1-3:11),OpColon(3:12-3:13),OpenRound(3:14-3:15),LowerIdent(3:15-3:16),OpFatArrow(3:17-3:19),LowerIdent(3:20-3:21),CloseRound(3:21-3:22),Comma(3:22-3:23),LowerIdent(3:24-3:25),OpFatArrow(3:26-3:28),LowerIdent(3:29-3:30),Newline(1:1-1:1),
LowerIdent(4:1-4:11),OpAssign(4:12-4:13),OpBar(4:14-4:15),LowerIdent(4:15-4:18),Comma(4:18-4:19),LowerIdent(4:20-4:21),OpBar(4:21-4:22),LowerIdent(4:23-4:26),NoSpaceOpenRound(4:26-4:27),LowerIdent(4:27-4:28),CloseRound(4:28-4:29),Newline(1:1-1:1),
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
		(type_anno (3:1-3:23)
			"runEffect!"
			(fn (3:15-3:21)
				(ty_var (3:15-3:16) "a")
				(ty_var (3:20-3:21) "b")))
		(malformed_expr (3:22-3:25) "expr_unexpected_token")
		(ident (3:24-3:25) "" "a")
		(malformed_expr (3:26-3:30) "expr_unexpected_token")
		(ident (3:29-3:30) "" "b")
		(decl (4:1-4:29)
			(ident (4:1-4:11) "runEffect!")
			(lambda (4:14-4:29)
				(args
					(ident (4:15-4:18) "fn!")
					(ident (4:20-4:21) "x"))
				(apply (4:23-4:29)
					(ident (4:23-4:26) "" "fn!")
					(ident (4:27-4:28) "" "x"))))
		(decl (6:1-6:15)
			(ident (6:1-6:6) "main!")
			(lambda (6:9-6:15)
				(args (underscore))
				(record (6:13-6:15))))))
~~~
# FORMATTED
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

runEffect! : (a => b)ab
runEffect! = |fn!, x| fn!(x)

main! = |_| {}
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (4:1-4:11)
				(pid 82)
				(ident "runEffect!")))
		(def_expr
			(e_lambda (4:14-4:29)
				(args
					(p_assign (4:15-4:18)
						(pid 83)
						(ident "fn!"))
					(p_assign (4:20-4:21)
						(pid 84)
						(ident "x")))
				(e_call (4:23-4:29)
					(e_lookup (4:23-4:26) (pid 83))
					(e_lookup (4:27-4:28) (pid 84)))))
		(annotation (4:1-4:11)
			(signature 94)
			(declared_type
				(parens (3:14-3:22)
					(fn (3:15-3:21)
						(ty_var (3:15-3:16) "a")
						(ty_var (3:20-3:21) "b")
						"true")))))
	(d_let
		(def_pattern
			(p_assign (6:1-6:6)
				(pid 97)
				(ident "main!")))
		(def_expr
			(e_lambda (6:9-6:15)
				(args (p_underscore (6:10-6:11) (pid 98)))
				(e_runtime_error (1:1-1:1) "not_implemented")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "runEffect!" 96 (type "*"))
		(def "main!" 102 (type "*")))
	(expressions
		(expr (4:14-4:29) 88 (type "*"))
		(expr (6:9-6:15) 101 (type "*"))))
~~~