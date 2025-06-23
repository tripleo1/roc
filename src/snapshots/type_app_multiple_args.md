# META
~~~ini
description=Multiple type arguments application in function annotation
type=file
~~~
# SOURCE
~~~roc
app [main!] { pf: platform "../basic-cli/main.roc" }

processDict : Dict(Str, U64) -> List(Str)
processDict = |_dict| []

main! = |_| processDict(Dict.empty().insert("one", 1))
~~~
# PROBLEMS
**UNDEFINED VARIABLE**
Nothing is named `empty` in this scope.
Is there an `import` or `exposing` missing up-top?

# TOKENS
~~~zig
KwApp(1:1-1:4),OpenSquare(1:5-1:6),LowerIdent(1:6-1:11),CloseSquare(1:11-1:12),OpenCurly(1:13-1:14),LowerIdent(1:15-1:17),OpColon(1:17-1:18),KwPlatform(1:19-1:27),StringStart(1:28-1:29),StringPart(1:29-1:50),StringEnd(1:50-1:51),CloseCurly(1:52-1:53),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(3:1-3:12),OpColon(3:13-3:14),UpperIdent(3:15-3:19),NoSpaceOpenRound(3:19-3:20),UpperIdent(3:20-3:23),Comma(3:23-3:24),UpperIdent(3:25-3:28),CloseRound(3:28-3:29),OpArrow(3:30-3:32),UpperIdent(3:33-3:37),NoSpaceOpenRound(3:37-3:38),UpperIdent(3:38-3:41),CloseRound(3:41-3:42),Newline(1:1-1:1),
LowerIdent(4:1-4:12),OpAssign(4:13-4:14),OpBar(4:15-4:16),NamedUnderscore(4:16-4:21),OpBar(4:21-4:22),OpenSquare(4:23-4:24),CloseSquare(4:24-4:25),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(6:1-6:6),OpAssign(6:7-6:8),OpBar(6:9-6:10),Underscore(6:10-6:11),OpBar(6:11-6:12),LowerIdent(6:13-6:24),NoSpaceOpenRound(6:24-6:25),UpperIdent(6:25-6:29),NoSpaceDotLowerIdent(6:29-6:35),NoSpaceOpenRound(6:35-6:36),CloseRound(6:36-6:37),NoSpaceDotLowerIdent(6:37-6:44),NoSpaceOpenRound(6:44-6:45),StringStart(6:45-6:46),StringPart(6:46-6:49),StringEnd(6:49-6:50),Comma(6:50-6:51),Int(6:52-6:53),CloseRound(6:53-6:54),CloseRound(6:54-6:55),EndOfFile(6:55-6:55),
~~~
# PARSE
~~~clojure
(file (1:1-6:55)
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
		(type_anno (3:1-4:12)
			"processDict"
			(fn (3:15-3:42)
				(apply (3:15-3:29)
					(ty "Dict")
					(ty "Str")
					(ty "U64"))
				(apply (3:33-3:42)
					(ty "List")
					(ty "Str"))))
		(decl (4:1-4:25)
			(ident (4:1-4:12) "processDict")
			(lambda (4:15-4:25)
				(args (ident (4:16-4:21) "_dict"))
				(list (4:23-4:25))))
		(decl (6:1-6:55)
			(ident (6:1-6:6) "main!")
			(lambda (6:9-6:55)
				(args (underscore))
				(apply (6:13-6:55)
					(ident (6:13-6:24) "" "processDict")
					(field_access (6:25-6:55)
						(binop (6:25-6:55)
							"app"
							(apply (6:25-6:37)
								(ident (6:25-6:35) "Dict" ".empty"))
							(apply (6:37-6:54)
								(ident (6:37-6:44) "" ".insert")
								(string (6:45-6:50) (string_part (6:46-6:49) "one"))
								(int (6:52-6:53) "1")))))))))
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
			(p_assign (4:1-4:12)
				(pid 78)
				(ident "processDict")))
		(def_expr
			(e_lambda (4:15-4:25)
				(args
					(p_assign (4:16-4:21)
						(pid 79)
						(ident "_dict")))
				(e_list (4:23-4:25) (elem_var 80) (elems))))
		(annotation (4:1-4:12)
			(signature 86)
			(declared_type
				(fn (3:15-3:42)
					(apply (3:15-3:29)
						"Dict"
						(ty (3:20-3:23) "Str")
						(ty (3:25-3:28) "U64"))
					(apply (3:33-3:42)
						"List"
						(ty (3:38-3:41) "Str"))
					"false"))))
	(d_let
		(def_pattern
			(p_assign (6:1-6:6)
				(pid 89)
				(ident "main!")))
		(def_expr
			(e_lambda (6:9-6:55)
				(args (p_underscore (6:10-6:11) (pid 90)))
				(e_call (6:13-6:55)
					(e_lookup (6:13-6:24) (pid 78))
					(e_dot_access (6:25-6:55)
						(e_call (6:25-6:37) (e_runtime_error (6:25-6:35) "ident_not_in_scope"))
						"insert"
						(e_string (6:45-6:50) (e_literal (6:46-6:49) "one"))
						(e_int (6:52-6:53)
							(int_var 98)
							(precision_var 97)
							(literal "1")
							(value "TODO")
							(bound "u8"))))))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "processDict" 88 (type "*"))
		(def "main!" 103 (type "*")))
	(expressions
		(expr (4:15-4:25) 82 (type "*"))
		(expr (6:9-6:55) 102 (type "*"))))
~~~