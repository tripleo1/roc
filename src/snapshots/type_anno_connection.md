# META
~~~ini
description=Type annotation connection to definitions
type=file
~~~
# SOURCE
~~~roc
module [add_one, my_number]

add_one : U64 -> U64
add_one = |x| x + 1

my_number : U64
my_number = add_one(42)
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:16),Comma(1:16-1:17),LowerIdent(1:18-1:27),CloseSquare(1:27-1:28),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(3:1-3:8),OpColon(3:9-3:10),UpperIdent(3:11-3:14),OpArrow(3:15-3:17),UpperIdent(3:18-3:21),Newline(1:1-1:1),
LowerIdent(4:1-4:8),OpAssign(4:9-4:10),OpBar(4:11-4:12),LowerIdent(4:12-4:13),OpBar(4:13-4:14),LowerIdent(4:15-4:16),OpPlus(4:17-4:18),Int(4:19-4:20),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(6:1-6:10),OpColon(6:11-6:12),UpperIdent(6:13-6:16),Newline(1:1-1:1),
LowerIdent(7:1-7:10),OpAssign(7:11-7:12),LowerIdent(7:13-7:20),NoSpaceOpenRound(7:20-7:21),Int(7:21-7:23),CloseRound(7:23-7:24),EndOfFile(7:24-7:24),
~~~
# PARSE
~~~clojure
(file (1:1-7:24)
	(module (1:1-1:28)
		(exposes (1:8-1:28)
			(exposed_item (lower_ident "add_one"))
			(exposed_item (lower_ident "my_number"))))
	(statements
		(type_anno (3:1-4:8)
			"add_one"
			(fn (3:11-3:21)
				(ty "U64")
				(ty "U64")))
		(decl (4:1-6:10)
			(ident (4:1-4:8) "add_one")
			(lambda (4:11-6:10)
				(args (ident (4:12-4:13) "x"))
				(binop (4:15-6:10)
					"+"
					(ident (4:15-4:16) "" "x")
					(int (4:19-4:20) "1"))))
		(type_anno (6:1-7:10) "my_number" (ty "U64"))
		(decl (7:1-7:24)
			(ident (7:1-7:10) "my_number")
			(apply (7:13-7:24)
				(ident (7:13-7:20) "" "add_one")
				(int (7:21-7:23) "42")))))
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
			(p_assign (4:1-4:8)
				(pid 75)
				(ident "add_one")))
		(def_expr
			(e_lambda (4:11-6:10)
				(args
					(p_assign (4:12-4:13)
						(pid 76)
						(ident "x")))
				(e_binop (4:15-6:10)
					"add"
					(e_lookup (4:15-4:16) (pid 76))
					(e_int (4:19-4:20)
						(int_var 79)
						(precision_var 78)
						(literal "1")
						(value "TODO")
						(bound "u8")))))
		(annotation (4:1-4:8)
			(signature 86)
			(declared_type
				(fn (3:11-3:21)
					(ty (3:11-3:14) "U64")
					(ty (3:18-3:21) "U64")
					"false"))))
	(d_let
		(def_pattern
			(p_assign (7:1-7:10)
				(pid 90)
				(ident "my_number")))
		(def_expr
			(e_call (7:13-7:24)
				(e_lookup (7:13-7:20) (pid 75))
				(e_int (7:21-7:23)
					(int_var 93)
					(precision_var 92)
					(literal "42")
					(value "TODO")
					(bound "u8"))))
		(annotation (7:1-7:10)
			(signature 97)
			(declared_type (ty (6:13-6:16) "U64")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "add_one" 88 (type "*"))
		(def "my_number" 99 (type "*")))
	(expressions
		(expr (4:11-6:10) 82 (type "*"))
		(expr (7:13-7:24) 95 (type "*"))))
~~~