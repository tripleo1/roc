# META
~~~ini
description=Dot access super test
type=expr
~~~
# SOURCE
~~~roc
some_fn(arg1)?.static_dispatch_method()?.next_static_dispatch_method()?.record_field?
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize suffix_single_question expression

# TOKENS
~~~zig
LowerIdent(1:1-1:8),NoSpaceOpenRound(1:8-1:9),LowerIdent(1:9-1:13),CloseRound(1:13-1:14),NoSpaceOpQuestion(1:14-1:15),NoSpaceDotLowerIdent(1:15-1:38),NoSpaceOpenRound(1:38-1:39),CloseRound(1:39-1:40),NoSpaceOpQuestion(1:40-1:41),NoSpaceDotLowerIdent(1:41-1:69),NoSpaceOpenRound(1:69-1:70),CloseRound(1:70-1:71),NoSpaceOpQuestion(1:71-1:72),NoSpaceDotLowerIdent(1:72-1:85),NoSpaceOpQuestion(1:85-1:86),EndOfFile(1:86-1:86),
~~~
# PARSE
~~~clojure
(field_access (1:1-1:86)
	(binop (1:1-1:86)
		"some_fn"
		(field_access (1:1-1:85)
			(binop (1:1-1:85)
				"some_fn"
				(field_access (1:1-1:69)
					(binop (1:1-1:69)
						"some_fn"
						(suffix_single_question (1:1-1:15)
							(apply (1:1-1:14)
								(ident (1:1-1:8) "" "some_fn")
								(ident (1:9-1:13) "" "arg1")))
						(suffix_single_question (1:15-1:41)
							(apply (1:15-1:40)
								(ident (1:15-1:38) "" ".static_dispatch_method")))))
				(suffix_single_question (1:41-1:72)
					(apply (1:41-1:71)
						(ident (1:41-1:69) "" ".next_static_dispatch_method")))))
		(suffix_single_question (1:72-1:86)
			(ident (1:72-1:85) "" ".record_field"))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_dot_access (1:1-1:86)
	(e_dot_access (1:1-1:85)
		(e_dot_access (1:1-1:69)
			(e_runtime_error (1:1-1:1) "not_implemented")
			"unknown")
		"unknown")
	"unknown")
~~~
# TYPES
~~~clojure
(expr 76 (type "*"))
~~~