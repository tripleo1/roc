# META
~~~ini
description=string_multiline_formatting_(due_to_templating_not_multiline_string_literal) (1)
type=expr
~~~
# SOURCE
~~~roc
"This is a string with ${some_func(a, #This is a comment
b)} lines of text due to the template parts"
~~~
# PROBLEMS
**UNDEFINED VARIABLE**
Nothing is named `some_func` in this scope.
Is there an `import` or `exposing` missing up-top?

**UNDEFINED VARIABLE**
Nothing is named `a` in this scope.
Is there an `import` or `exposing` missing up-top?

**UNDEFINED VARIABLE**
Nothing is named `b` in this scope.
Is there an `import` or `exposing` missing up-top?

# TOKENS
~~~zig
StringStart(1:1-1:2),StringPart(1:2-1:24),OpenStringInterpolation(1:24-1:26),LowerIdent(1:26-1:35),NoSpaceOpenRound(1:35-1:36),LowerIdent(1:36-1:37),Comma(1:37-1:38),Newline(1:40-1:57),
LowerIdent(2:1-2:2),CloseRound(2:2-2:3),CloseStringInterpolation(2:3-2:4),StringPart(2:4-2:44),StringEnd(2:44-2:45),EndOfFile(2:45-2:45),
~~~
# PARSE
~~~clojure
(string (1:1-2:45)
	(string_part (1:2-1:24) "This is a string with ")
	(apply (1:26-2:3)
		(ident (1:26-1:35) "" "some_func")
		(ident (1:36-1:37) "" "a")
		(ident (2:1-2:2) "" "b"))
	(string_part (2:4-2:44) " lines of text due to the template parts"))
~~~
# FORMATTED
~~~roc
"This is a string with ${
	some_func(
		a, # This is a comment
		b,
	)
} lines of text due to the template parts"
~~~
# CANONICALIZE
~~~clojure
(e_string (1:1-2:45)
	(e_literal (1:2-1:24) "This is a string with ")
	(e_call (1:26-2:3)
		(e_runtime_error (1:26-1:35) "ident_not_in_scope")
		(e_runtime_error (1:36-1:37) "ident_not_in_scope")
		(e_runtime_error (2:1-2:2) "ident_not_in_scope"))
	(e_literal (2:4-2:44) " lines of text due to the template parts"))
~~~
# TYPES
~~~clojure
(expr 81 (type "Str"))
~~~