# META
~~~ini
description=multiline_binop (1)
type=expr
~~~
# SOURCE
~~~roc
1 # One
	+ # Plus

	# A comment in between

	2 # Two
		* # Times
		3
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
Int(1:1-1:2),Newline(1:4-1:8),
OpPlus(2:2-2:3),Newline(2:5-2:10),
Newline(1:1-1:1),
Newline(4:3-4:24),
Newline(1:1-1:1),
Int(6:2-6:3),Newline(6:5-6:9),
OpStar(7:3-7:4),Newline(7:6-7:12),
Int(8:3-8:4),EndOfFile(8:4-8:4),
~~~
# PARSE
~~~clojure
(binop (1:1-8:4)
	"+"
	(int (1:1-1:2) "1")
	(binop (6:2-8:4)
		"*"
		(int (6:2-6:3) "2")
		(int (8:3-8:4) "3")))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_binop (1:1-8:4)
	"add"
	(e_int (1:1-1:2)
		(int_var 73)
		(precision_var 72)
		(literal "1")
		(value "TODO")
		(bound "u8"))
	(e_binop (6:2-8:4)
		"mul"
		(e_int (6:2-6:3)
			(int_var 76)
			(precision_var 75)
			(literal "2")
			(value "TODO")
			(bound "u8"))
		(e_int (8:3-8:4)
			(int_var 79)
			(precision_var 78)
			(literal "3")
			(value "TODO")
			(bound "u8"))))
~~~
# TYPES
~~~clojure
(expr 82 (type "*"))
~~~