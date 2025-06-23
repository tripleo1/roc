# META
~~~ini
description=if_then_else (15)
type=expr
~~~
# SOURCE
~~~roc
if # Comment after if
	bool # Comment after cond
		{ # Comment after then open
			1
		} # Comment after then close
			else # Comment after else
				{ # Comment else open
					2
				}
~~~
# PROBLEMS
**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize if_then_else expression

# TOKENS
~~~zig
KwIf(1:1-1:3),Newline(1:5-1:22),
LowerIdent(2:2-2:6),Newline(2:8-2:27),
OpenCurly(3:3-3:4),Newline(3:6-3:30),
Int(4:4-4:5),Newline(1:1-1:1),
CloseCurly(5:3-5:4),Newline(5:6-5:31),
KwElse(6:4-6:8),Newline(6:10-6:29),
OpenCurly(7:5-7:6),Newline(7:8-7:26),
Int(8:6-8:7),Newline(1:1-1:1),
CloseCurly(9:5-9:6),EndOfFile(9:6-9:6),
~~~
# PARSE
~~~clojure
(if_then_else (1:1-9:6)
	(ident (2:2-2:6) "" "bool")
	(block (3:3-5:4)
		(statements (int (4:4-4:5) "1")))
	(block (7:5-9:6)
		(statements (int (8:6-8:7) "2"))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_runtime_error (1:1-1:1) "not_implemented")
~~~
# TYPES
~~~clojure
(expr 73 (type "Error"))
~~~