# META
~~~ini
description=multiline_list_formatting (5)
type=expr
~~~
# SOURCE
~~~roc
[1, 2, # Foo
  3]
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
OpenSquare(1:1-1:2),Int(1:2-1:3),Comma(1:3-1:4),Int(1:5-1:6),Comma(1:6-1:7),Newline(1:9-1:13),
Int(2:3-2:4),CloseSquare(2:4-2:5),EndOfFile(2:5-2:5),
~~~
# PARSE
~~~clojure
(list (1:1-2:5)
	(int (1:2-1:3) "1")
	(int (1:5-1:6) "2")
	(int (2:3-2:4) "3"))
~~~
# FORMATTED
~~~roc
[
	1,
	2, # Foo
	3,
]
~~~
# CANONICALIZE
~~~clojure
(e_list (1:1-2:5)
	(elem_var 81)
	(elems
		(e_int (1:2-1:3)
			(int_var 73)
			(precision_var 72)
			(literal "1")
			(value "TODO")
			(bound "u8"))
		(e_int (1:5-1:6)
			(int_var 76)
			(precision_var 75)
			(literal "2")
			(value "TODO")
			(bound "u8"))
		(e_int (2:3-2:4)
			(int_var 79)
			(precision_var 78)
			(literal "3")
			(value "TODO")
			(bound "u8"))))
~~~
# TYPES
~~~clojure
(expr 82 (type "List(Num(Int(*)))"))
~~~