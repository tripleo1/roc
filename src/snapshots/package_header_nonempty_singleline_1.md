# META
~~~ini
description=package_header_nonempty_singleline (1)
type=file
~~~
# SOURCE
~~~roc
package [something, SomeType] { somePkg: "../main.roc", other: "../../other/main.roc" }
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwPackage(1:1-1:8),OpenSquare(1:9-1:10),LowerIdent(1:10-1:19),Comma(1:19-1:20),UpperIdent(1:21-1:29),CloseSquare(1:29-1:30),OpenCurly(1:31-1:32),LowerIdent(1:33-1:40),OpColon(1:40-1:41),StringStart(1:42-1:43),StringPart(1:43-1:54),StringEnd(1:54-1:55),Comma(1:55-1:56),LowerIdent(1:57-1:62),OpColon(1:62-1:63),StringStart(1:64-1:65),StringPart(1:65-1:85),StringEnd(1:85-1:86),CloseCurly(1:87-1:88),EndOfFile(1:88-1:88),
~~~
# PARSE
~~~clojure
(file (1:1-1:88)
	(package (1:1-1:88)
		(exposes (1:9-1:30)
			(exposed_item (lower_ident "something"))
			(exposed_item (upper_ident "SomeType")))
		(packages (1:31-1:88)
			(record_field (1:33-1:56)
				"somePkg"
				(string (1:42-1:55) (string_part (1:43-1:54) "../main.roc")))
			(record_field (1:57-1:88)
				"other"
				(string (1:64-1:86) (string_part (1:65-1:85) "../../other/main.roc")))))
	(statements))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(can_ir "empty")
~~~
# TYPES
~~~clojure
(inferred_types (defs) (expressions))
~~~