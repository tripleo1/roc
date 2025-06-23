# META
~~~ini
description=A simple module with no blanks
type=file
~~~
# SOURCE
~~~roc
module [hello!, world]
import pf.Stdout
hello! = Stdout.line!("Hello")
world = "World"
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented: top-level import

**UNDEFINED VARIABLE**
Nothing is named `line!` in this scope.
Is there an `import` or `exposing` missing up-top?

# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:15),Comma(1:15-1:16),LowerIdent(1:17-1:22),CloseSquare(1:22-1:23),Newline(1:1-1:1),
KwImport(2:1-2:7),LowerIdent(2:8-2:10),NoSpaceDotUpperIdent(2:10-2:17),Newline(1:1-1:1),
LowerIdent(3:1-3:7),OpAssign(3:8-3:9),UpperIdent(3:10-3:16),NoSpaceDotLowerIdent(3:16-3:22),NoSpaceOpenRound(3:22-3:23),StringStart(3:23-3:24),StringPart(3:24-3:29),StringEnd(3:29-3:30),CloseRound(3:30-3:31),Newline(1:1-1:1),
LowerIdent(4:1-4:6),OpAssign(4:7-4:8),StringStart(4:9-4:10),StringPart(4:10-4:15),StringEnd(4:15-4:16),EndOfFile(4:16-4:16),
~~~
# PARSE
~~~clojure
(file (1:1-4:16)
	(module (1:1-1:23)
		(exposes (1:8-1:23)
			(exposed_item (lower_ident "hello!"))
			(exposed_item (lower_ident "world"))))
	(statements
		(import (2:1-2:17) ".Stdout" (qualifier "pf"))
		(decl (3:1-3:31)
			(ident (3:1-3:7) "hello!")
			(apply (3:10-3:31)
				(ident (3:10-3:22) "Stdout" ".line!")
				(string (3:23-3:30) (string_part (3:24-3:29) "Hello"))))
		(decl (4:1-4:16)
			(ident (4:1-4:6) "world")
			(string (4:9-4:16) (string_part (4:10-4:15) "World")))))
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
			(p_assign (3:1-3:7)
				(pid 73)
				(ident "hello!")))
		(def_expr
			(e_call (3:10-3:31)
				(e_runtime_error (3:10-3:22) "ident_not_in_scope")
				(e_string (3:23-3:30) (e_literal (3:24-3:29) "Hello")))))
	(d_let
		(def_pattern
			(p_assign (4:1-4:6)
				(pid 80)
				(ident "world")))
		(def_expr
			(e_string (4:9-4:16) (e_literal (4:10-4:15) "World")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "hello!" 79 (type "*"))
		(def "world" 83 (type "Str")))
	(expressions
		(expr (3:10-3:31) 78 (type "*"))
		(expr (4:9-4:16) 82 (type "Str"))))
~~~