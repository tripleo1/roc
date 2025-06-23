# META
~~~ini
description=Test crash and ellipsis canonicalization
type=file
~~~
# SOURCE
~~~roc
app [main!] { pf: platform "../basic-cli/platform.roc" }

# Test ellipsis placeholder
testEllipsis : U64 -> U64
testEllipsis = |_| ...

# Test crash statement
testCrash : U64 -> U64
testCrash = |_| crash "This is a crash message"

# Test crash with different message
testCrashSimple : U64 -> U64
testCrashSimple = |_| crash "oops"

main! = |_|
    result1 = testEllipsis(42)
    result2 = testCrash(42)
    result3 = testCrashSimple(42)
    []
~~~
# PROBLEMS
**UNEXPECTED TOKEN IN EXPRESSION**
The token **crash "** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**crash_and_ellipsis_test.md:9:17:9:24:**
```roc
testCrash = |_| crash "This is a crash message"
```


**UNEXPECTED TOKEN IN EXPRESSION**
The token **crash "** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**crash_and_ellipsis_test.md:13:23:13:30:**
```roc
testCrashSimple = |_| crash "oops"
```


**UNEXPECTED TOKEN IN EXPRESSION**
The token **= testEllipsis** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.
Here is the problematic code:
**crash_and_ellipsis_test.md:16:13:16:27:**
```roc
    result1 = testEllipsis(42)
```


**NOT IMPLEMENTED**
This feature is not yet implemented: ...

**INVALID LAMBDA**
The body of this lambda expression is not valid.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID LAMBDA**
The body of this lambda expression is not valid.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**UNDEFINED VARIABLE**
Nothing is named `result1` in this scope.
Is there an `import` or `exposing` missing up-top?

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

# TOKENS
~~~zig
KwApp(1:1-1:4),OpenSquare(1:5-1:6),LowerIdent(1:6-1:11),CloseSquare(1:11-1:12),OpenCurly(1:13-1:14),LowerIdent(1:15-1:17),OpColon(1:17-1:18),KwPlatform(1:19-1:27),StringStart(1:28-1:29),StringPart(1:29-1:54),StringEnd(1:54-1:55),CloseCurly(1:56-1:57),Newline(1:1-1:1),
Newline(1:1-1:1),
Newline(3:2-3:28),
LowerIdent(4:1-4:13),OpColon(4:14-4:15),UpperIdent(4:16-4:19),OpArrow(4:20-4:22),UpperIdent(4:23-4:26),Newline(1:1-1:1),
LowerIdent(5:1-5:13),OpAssign(5:14-5:15),OpBar(5:16-5:17),Underscore(5:17-5:18),OpBar(5:18-5:19),TripleDot(5:20-5:23),Newline(1:1-1:1),
Newline(1:1-1:1),
Newline(7:2-7:23),
LowerIdent(8:1-8:10),OpColon(8:11-8:12),UpperIdent(8:13-8:16),OpArrow(8:17-8:19),UpperIdent(8:20-8:23),Newline(1:1-1:1),
LowerIdent(9:1-9:10),OpAssign(9:11-9:12),OpBar(9:13-9:14),Underscore(9:14-9:15),OpBar(9:15-9:16),KwCrash(9:17-9:22),StringStart(9:23-9:24),StringPart(9:24-9:47),StringEnd(9:47-9:48),Newline(1:1-1:1),
Newline(1:1-1:1),
Newline(11:2-11:36),
LowerIdent(12:1-12:16),OpColon(12:17-12:18),UpperIdent(12:19-12:22),OpArrow(12:23-12:25),UpperIdent(12:26-12:29),Newline(1:1-1:1),
LowerIdent(13:1-13:16),OpAssign(13:17-13:18),OpBar(13:19-13:20),Underscore(13:20-13:21),OpBar(13:21-13:22),KwCrash(13:23-13:28),StringStart(13:29-13:30),StringPart(13:30-13:34),StringEnd(13:34-13:35),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(15:1-15:6),OpAssign(15:7-15:8),OpBar(15:9-15:10),Underscore(15:10-15:11),OpBar(15:11-15:12),Newline(1:1-1:1),
LowerIdent(16:5-16:12),OpAssign(16:13-16:14),LowerIdent(16:15-16:27),NoSpaceOpenRound(16:27-16:28),Int(16:28-16:30),CloseRound(16:30-16:31),Newline(1:1-1:1),
LowerIdent(17:5-17:12),OpAssign(17:13-17:14),LowerIdent(17:15-17:24),NoSpaceOpenRound(17:24-17:25),Int(17:25-17:27),CloseRound(17:27-17:28),Newline(1:1-1:1),
LowerIdent(18:5-18:12),OpAssign(18:13-18:14),LowerIdent(18:15-18:30),NoSpaceOpenRound(18:30-18:31),Int(18:31-18:33),CloseRound(18:33-18:34),Newline(1:1-1:1),
OpenSquare(19:5-19:6),CloseSquare(19:6-19:7),EndOfFile(19:7-19:7),
~~~
# PARSE
~~~clojure
(file (1:1-19:7)
	(app (1:1-1:57)
		(provides (1:6-1:12) (exposed_item (lower_ident "main!")))
		(record_field (1:15-1:57)
			"pf"
			(string (1:28-1:55) (string_part (1:29-1:54) "../basic-cli/platform.roc")))
		(packages (1:13-1:57)
			(record_field (1:15-1:57)
				"pf"
				(string (1:28-1:55) (string_part (1:29-1:54) "../basic-cli/platform.roc")))))
	(statements
		(type_anno (4:1-5:13)
			"testEllipsis"
			(fn (4:16-4:26)
				(ty "U64")
				(ty "U64")))
		(decl (5:1-5:23)
			(ident (5:1-5:13) "testEllipsis")
			(lambda (5:16-5:23) (args (underscore)) (ellipsis)))
		(type_anno (8:1-9:10)
			"testCrash"
			(fn (8:13-8:23)
				(ty "U64")
				(ty "U64")))
		(decl (9:1-9:24)
			(ident (9:1-9:10) "testCrash")
			(lambda (9:13-9:24)
				(args (underscore))
				(malformed_expr (9:17-9:24) "expr_unexpected_token")))
		(string (9:23-9:48) (string_part (9:24-9:47) "This is a crash message"))
		(type_anno (12:1-13:16)
			"testCrashSimple"
			(fn (12:19-12:29)
				(ty "U64")
				(ty "U64")))
		(decl (13:1-13:30)
			(ident (13:1-13:16) "testCrashSimple")
			(lambda (13:19-13:30)
				(args (underscore))
				(malformed_expr (13:23-13:30) "expr_unexpected_token")))
		(string (13:29-13:35) (string_part (13:30-13:34) "oops"))
		(decl (15:1-16:12)
			(ident (15:1-15:6) "main!")
			(lambda (15:9-16:12)
				(args (underscore))
				(ident (16:5-16:12) "" "result1")))
		(malformed_expr (16:13-16:27) "expr_unexpected_token")
		(apply (16:15-16:31)
			(ident (16:15-16:27) "" "testEllipsis")
			(int (16:28-16:30) "42"))
		(decl (17:5-17:28)
			(ident (17:5-17:12) "result2")
			(apply (17:15-17:28)
				(ident (17:15-17:24) "" "testCrash")
				(int (17:25-17:27) "42")))
		(decl (18:5-18:34)
			(ident (18:5-18:12) "result3")
			(apply (18:15-18:34)
				(ident (18:15-18:30) "" "testCrashSimple")
				(int (18:31-18:33) "42")))
		(list (19:5-19:7))))
~~~
# FORMATTED
~~~roc
app [main!] { pf: platform "../basic-cli/platform.roc" }

# Test ellipsis placeholder
testEllipsis : U64 -> U64
testEllipsis = |_| ...

# Test crash statement
testCrash : U64 -> U64
testCrash = |_| "This is a crash message"

# Test crash with different message
testCrashSimple : U64 -> U64
testCrashSimple = |_| "oops"

main! = |_|
	result1testEllipsis(42)
result2 = testCrash(42)
result3 = testCrashSimple(42)
[]
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (5:1-5:13)
				(pid 75)
				(ident "testEllipsis")))
		(def_expr
			(e_lambda (5:16-5:23)
				(args (p_underscore (5:17-5:18) (pid 76)))
				(e_runtime_error (5:20-5:23) "not_implemented")))
		(annotation (5:1-5:13)
			(signature 83)
			(declared_type
				(fn (4:16-4:26)
					(ty (4:16-4:19) "U64")
					(ty (4:23-4:26) "U64")
					"false"))))
	(d_let
		(def_pattern
			(p_assign (9:1-9:10)
				(pid 89)
				(ident "testCrash")))
		(def_expr
			(e_lambda (9:13-9:24)
				(args (p_underscore (9:14-9:15) (pid 90)))
				(e_runtime_error (9:17-9:24) "lambda_body_not_canonicalized")))
		(annotation (9:1-9:10)
			(signature 97)
			(declared_type
				(fn (8:13-8:23)
					(ty (8:13-8:16) "U64")
					(ty (8:20-8:23) "U64")
					"false"))))
	(d_let
		(def_pattern
			(p_assign (13:1-13:16)
				(pid 104)
				(ident "testCrashSimple")))
		(def_expr
			(e_lambda (13:19-13:30)
				(args (p_underscore (13:20-13:21) (pid 105)))
				(e_runtime_error (13:23-13:30) "lambda_body_not_canonicalized")))
		(annotation (13:1-13:16)
			(signature 112)
			(declared_type
				(fn (12:19-12:29)
					(ty (12:19-12:22) "U64")
					(ty (12:26-12:29) "U64")
					"false"))))
	(d_let
		(def_pattern
			(p_assign (15:1-15:6)
				(pid 116)
				(ident "main!")))
		(def_expr
			(e_lambda (15:9-16:12)
				(args (p_underscore (15:10-15:11) (pid 117)))
				(e_runtime_error (16:5-16:12) "ident_not_in_scope"))))
	(d_let
		(def_pattern
			(p_assign (17:5-17:12)
				(pid 124)
				(ident "result2")))
		(def_expr
			(e_call (17:15-17:28)
				(e_lookup (17:15-17:24) (pid 89))
				(e_int (17:25-17:27)
					(int_var 127)
					(precision_var 126)
					(literal "42")
					(value "TODO")
					(bound "u8")))))
	(d_let
		(def_pattern
			(p_assign (18:5-18:12)
				(pid 131)
				(ident "result3")))
		(def_expr
			(e_call (18:15-18:34)
				(e_lookup (18:15-18:30) (pid 104))
				(e_int (18:31-18:33)
					(int_var 134)
					(precision_var 133)
					(literal "42")
					(value "TODO")
					(bound "u8"))))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "testEllipsis" 85 (type "*"))
		(def "testCrash" 99 (type "*"))
		(def "testCrashSimple" 114 (type "*"))
		(def "main!" 121 (type "*"))
		(def "result2" 130 (type "*"))
		(def "result3" 137 (type "*")))
	(expressions
		(expr (5:16-5:23) 79 (type "*"))
		(expr (9:13-9:24) 93 (type "*"))
		(expr (13:19-13:30) 108 (type "*"))
		(expr (15:9-16:12) 120 (type "*"))
		(expr (17:15-17:28) 129 (type "*"))
		(expr (18:15-18:34) 136 (type "*"))))
~~~