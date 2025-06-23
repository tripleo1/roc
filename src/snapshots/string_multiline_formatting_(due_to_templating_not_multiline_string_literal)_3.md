# META
~~~ini
description=string_multiline_formatting_(due_to_templating_not_multiline_string_literal) (3)
type=expr
~~~
# SOURCE
~~~roc
"This is a string with ${
	some_func(
		a, # This is a comment
		b,
	)
} lines of text due to the template parts"
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
StringStart(1:1-1:2),StringPart(1:2-1:24),OpenStringInterpolation(1:24-1:26),Newline(1:1-1:1),
LowerIdent(2:2-2:11),NoSpaceOpenRound(2:11-2:12),Newline(1:1-1:1),
LowerIdent(3:3-3:4),Comma(3:4-3:5),Newline(3:7-3:25),
LowerIdent(4:3-4:4),Comma(4:4-4:5),Newline(1:1-1:1),
CloseRound(5:2-5:3),Newline(1:1-1:1),
CloseStringInterpolation(6:1-6:2),StringPart(6:2-6:42),StringEnd(6:42-6:43),EndOfFile(6:43-6:43),
~~~
# PARSE
~~~clojure
(string (1:1-6:43)
	(string_part (1:2-1:24) "This is a string with ")
	(apply (2:2-5:3)
		(ident (2:2-2:11) "" "some_func")
		(ident (3:3-3:4) "" "a")
		(ident (4:3-4:4) "" "b"))
	(string_part (6:2-6:42) " lines of text due to the template parts"))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_string (1:1-6:43)
	(e_literal (1:2-1:24) "This is a string with ")
	(e_call (2:2-5:3)
		(e_runtime_error (2:2-2:11) "ident_not_in_scope")
		(e_runtime_error (3:3-3:4) "ident_not_in_scope")
		(e_runtime_error (4:3-4:4) "ident_not_in_scope"))
	(e_literal (6:2-6:42) " lines of text due to the template parts"))
~~~
# TYPES
~~~clojure
(expr 81 (type "Str"))
~~~