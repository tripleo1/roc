# META
~~~ini
description=Type application with variables in function annotation
type=file
~~~
# SOURCE
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

mapList : List(a), (a -> b) -> List(b)
mapList = |list, fn| list.map(fn)

main! = |_| mapList([1,2,3,4,5])
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwApp(1:1-1:4),OpenSquare(1:5-1:6),LowerIdent(1:6-1:11),CloseSquare(1:11-1:12),OpenCurly(1:13-1:14),LowerIdent(1:15-1:17),OpColon(1:17-1:18),KwPlatform(1:19-1:27),StringStart(1:28-1:29),StringPart(1:29-1:50),StringEnd(1:50-1:51),CloseCurly(1:52-1:53),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(3:1-3:8),OpColon(3:9-3:10),UpperIdent(3:11-3:15),NoSpaceOpenRound(3:15-3:16),LowerIdent(3:16-3:17),CloseRound(3:17-3:18),Comma(3:18-3:19),OpenRound(3:20-3:21),LowerIdent(3:21-3:22),OpArrow(3:23-3:25),LowerIdent(3:26-3:27),CloseRound(3:27-3:28),OpArrow(3:29-3:31),UpperIdent(3:32-3:36),NoSpaceOpenRound(3:36-3:37),LowerIdent(3:37-3:38),CloseRound(3:38-3:39),Newline(1:1-1:1),
LowerIdent(4:1-4:8),OpAssign(4:9-4:10),OpBar(4:11-4:12),LowerIdent(4:12-4:16),Comma(4:16-4:17),LowerIdent(4:18-4:20),OpBar(4:20-4:21),LowerIdent(4:22-4:26),NoSpaceDotLowerIdent(4:26-4:30),NoSpaceOpenRound(4:30-4:31),LowerIdent(4:31-4:33),CloseRound(4:33-4:34),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(6:1-6:6),OpAssign(6:7-6:8),OpBar(6:9-6:10),Underscore(6:10-6:11),OpBar(6:11-6:12),LowerIdent(6:13-6:20),NoSpaceOpenRound(6:20-6:21),OpenSquare(6:21-6:22),Int(6:22-6:23),Comma(6:23-6:24),Int(6:24-6:25),Comma(6:25-6:26),Int(6:26-6:27),Comma(6:27-6:28),Int(6:28-6:29),Comma(6:29-6:30),Int(6:30-6:31),CloseSquare(6:31-6:32),CloseRound(6:32-6:33),EndOfFile(6:33-6:33),
~~~
# PARSE
~~~clojure
(file (1:1-6:33)
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
		(type_anno (3:1-4:8)
			"mapList"
			(fn (3:11-3:39)
				(apply (3:11-3:18)
					(ty "List")
					(ty_var (3:16-3:17) "a"))
				(fn (3:21-3:27)
					(ty_var (3:21-3:22) "a")
					(ty_var (3:26-3:27) "b"))
				(apply (3:32-3:39)
					(ty "List")
					(ty_var (3:37-3:38) "b"))))
		(decl (4:1-6:6)
			(ident (4:1-4:8) "mapList")
			(lambda (4:11-6:6)
				(args
					(ident (4:12-4:16) "list")
					(ident (4:18-4:20) "fn"))
				(field_access (4:22-6:6)
					(binop (4:22-6:6)
						"app"
						(ident (4:22-4:26) "" "list")
						(apply (4:26-4:34)
							(ident (4:26-4:30) "" ".map")
							(ident (4:31-4:33) "" "fn"))))))
		(decl (6:1-6:33)
			(ident (6:1-6:6) "main!")
			(lambda (6:9-6:33)
				(args (underscore))
				(apply (6:13-6:33)
					(ident (6:13-6:20) "" "mapList")
					(list (6:21-6:32)
						(int (6:22-6:23) "1")
						(int (6:24-6:25) "2")
						(int (6:26-6:27) "3")
						(int (6:28-6:29) "4")
						(int (6:30-6:31) "5")))))))
~~~
# FORMATTED
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

mapList : List(a), (a -> b) -> List(b)
mapList = |list, fn| list.map(fn)

main! = |_| mapList([1, 2, 3, 4, 5])
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (4:1-4:8)
				(pid 85)
				(ident "mapList")))
		(def_expr
			(e_lambda (4:11-6:6)
				(args
					(p_assign (4:12-4:16)
						(pid 86)
						(ident "list"))
					(p_assign (4:18-4:20)
						(pid 87)
						(ident "fn")))
				(e_dot_access (4:22-6:6)
					(e_lookup (4:22-4:26) (pid 86))
					"map"
					(e_lookup (4:31-4:33) (pid 87)))))
		(annotation (4:1-4:8)
			(signature 100)
			(declared_type
				(fn (3:11-3:39)
					(apply (3:11-3:18)
						"List"
						(ty_var (3:16-3:17) "a"))
					(parens (3:20-3:28)
						(fn (3:21-3:27)
							(ty_var (3:21-3:22) "a")
							(ty_var (3:26-3:27) "b")
							"false"))
					(apply (3:32-3:39)
						"List"
						(ty_var (3:37-3:38) "b"))
					"false"))))
	(d_let
		(def_pattern
			(p_assign (6:1-6:6)
				(pid 103)
				(ident "main!")))
		(def_expr
			(e_lambda (6:9-6:33)
				(args (p_underscore (6:10-6:11) (pid 104)))
				(e_call (6:13-6:33)
					(e_lookup (6:13-6:20) (pid 85))
					(e_list (6:21-6:32)
						(elem_var 121)
						(elems
							(e_int (6:22-6:23)
								(int_var 107)
								(precision_var 106)
								(literal "1")
								(value "TODO")
								(bound "u8"))
							(e_int (6:24-6:25)
								(int_var 110)
								(precision_var 109)
								(literal "2")
								(value "TODO")
								(bound "u8"))
							(e_int (6:26-6:27)
								(int_var 113)
								(precision_var 112)
								(literal "3")
								(value "TODO")
								(bound "u8"))
							(e_int (6:28-6:29)
								(int_var 116)
								(precision_var 115)
								(literal "4")
								(value "TODO")
								(bound "u8"))
							(e_int (6:30-6:31)
								(int_var 119)
								(precision_var 118)
								(literal "5")
								(value "TODO")
								(bound "u8")))))))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "mapList" 102 (type "*"))
		(def "main!" 125 (type "*")))
	(expressions
		(expr (4:11-6:6) 91 (type "*"))
		(expr (6:9-6:33) 124 (type "*"))))
~~~