# META
~~~ini
description=record_access_multiline_formatting (4)
type=expr
~~~
# SOURCE
~~~roc
some_fn(arg1)? # Comment 1
	.static_dispatch_method()? # Comment 2
	.next_static_dispatch_method()? # Comment 3
	.record_field?
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize suffix_single_question expression

# TOKENS
~~~zig
LowerIdent(1:1-1:8),NoSpaceOpenRound(1:8-1:9),LowerIdent(1:9-1:13),CloseRound(1:13-1:14),NoSpaceOpQuestion(1:14-1:15),Newline(1:17-1:27),
DotLowerIdent(2:2-2:25),NoSpaceOpenRound(2:25-2:26),CloseRound(2:26-2:27),NoSpaceOpQuestion(2:27-2:28),Newline(2:30-2:40),
DotLowerIdent(3:2-3:30),NoSpaceOpenRound(3:30-3:31),CloseRound(3:31-3:32),NoSpaceOpQuestion(3:32-3:33),Newline(3:35-3:45),
DotLowerIdent(4:2-4:15),NoSpaceOpQuestion(4:15-4:16),EndOfFile(4:16-4:16),
~~~
# PARSE
~~~clojure
(field_access (1:1-4:16)
	(binop (1:1-4:16)
		"some_fn"
		(field_access (1:1-4:15)
			(binop (1:1-4:15)
				"some_fn"
				(field_access (1:1-3:30)
					(binop (1:1-3:30)
						"some_fn"
						(suffix_single_question (1:1-1:15)
							(apply (1:1-1:14)
								(ident (1:1-1:8) "" "some_fn")
								(ident (1:9-1:13) "" "arg1")))
						(suffix_single_question (2:2-2:28)
							(apply (2:2-2:27)
								(ident (2:2-2:25) "" ".static_dispatch_method")))))
				(suffix_single_question (3:2-3:33)
					(apply (3:2-3:32)
						(ident (3:2-3:30) "" ".next_static_dispatch_method")))))
		(suffix_single_question (4:2-4:16)
			(ident (4:2-4:15) "" ".record_field"))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_dot_access (1:1-4:16)
	(e_dot_access (1:1-4:15)
		(e_dot_access (1:1-3:30)
			(e_runtime_error (1:1-1:1) "not_implemented")
			"unknown")
		"unknown")
	"unknown")
~~~
# TYPES
~~~clojure
(expr 76 (type "*"))
~~~