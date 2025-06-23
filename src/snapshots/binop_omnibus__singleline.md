# META
~~~ini
description=Binop omnibus - singleline
type=expr
~~~
# SOURCE
~~~roc
Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
~~~
# PROBLEMS
**UNDEFINED VARIABLE**
Nothing is named `foo` in this scope.
Is there an `import` or `exposing` missing up-top?

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

**NOT IMPLEMENTED**
This feature is not yet implemented: binop

# TOKENS
~~~zig
UpperIdent(1:1-1:4),NoSpaceOpenRound(1:4-1:5),LowerIdent(1:5-1:8),CloseRound(1:8-1:9),OpDoubleQuestion(1:10-1:12),Int(1:13-1:15),OpGreaterThan(1:16-1:17),Int(1:18-1:19),OpStar(1:20-1:21),Int(1:22-1:23),OpOr(1:24-1:26),Int(1:27-1:29),OpPlus(1:30-1:31),Int(1:32-1:33),OpLessThan(1:34-1:35),Int(1:36-1:37),OpAnd(1:38-1:41),Int(1:42-1:44),OpBinaryMinus(1:45-1:46),Int(1:47-1:48),OpGreaterThanOrEq(1:49-1:51),Int(1:52-1:54),OpOr(1:55-1:57),Int(1:58-1:60),OpLessThanOrEq(1:61-1:63),Int(1:64-1:65),OpSlash(1:66-1:67),Int(1:68-1:69),EndOfFile(1:69-1:69),
~~~
# PARSE
~~~clojure
(binop (1:1-1:69)
	"or"
	(binop (1:1-1:57)
		"or"
		(binop (1:1-1:26)
			">"
			(binop (1:1-1:17)
				"??"
				(apply (1:1-1:9)
					(tag (1:1-1:4) "Err")
					(ident (1:5-1:8) "" "foo"))
				(int (1:13-1:15) "12"))
			(binop (1:18-1:26)
				"*"
				(int (1:18-1:19) "5")
				(int (1:22-1:23) "5")))
		(binop (1:27-1:57)
			"and"
			(binop (1:27-1:41)
				"<"
				(binop (1:27-1:35)
					"+"
					(int (1:27-1:29) "13")
					(int (1:32-1:33) "2"))
				(int (1:36-1:37) "5"))
			(binop (1:42-1:57)
				">="
				(binop (1:42-1:51)
					"-"
					(int (1:42-1:44) "10")
					(int (1:47-1:48) "1"))
				(int (1:52-1:54) "16"))))
	(binop (1:58-1:69)
		"<="
		(int (1:58-1:60) "12")
		(binop (1:64-1:69)
			"/"
			(int (1:64-1:65) "3")
			(int (1:68-1:69) "5"))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e_runtime_error (1:1-1:69) "not_implemented")
~~~
# TYPES
~~~clojure
(expr 133 (type "Error"))
~~~