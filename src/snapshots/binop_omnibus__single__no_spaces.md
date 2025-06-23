# META
~~~ini
description=Binop omnibus - singleline - no spaces
type=expr
~~~
# SOURCE
~~~roc
Err(foo)??12>5*5 or 13+2<5 and 10-1>=16 or 12<=3/5
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
UpperIdent(1:1-1:4),NoSpaceOpenRound(1:4-1:5),LowerIdent(1:5-1:8),CloseRound(1:8-1:9),OpDoubleQuestion(1:9-1:11),Int(1:11-1:13),OpGreaterThan(1:13-1:14),Int(1:14-1:15),OpStar(1:15-1:16),Int(1:16-1:17),OpOr(1:18-1:20),Int(1:21-1:23),OpPlus(1:23-1:24),Int(1:24-1:25),OpLessThan(1:25-1:26),Int(1:26-1:27),OpAnd(1:28-1:31),Int(1:32-1:34),OpBinaryMinus(1:34-1:35),Int(1:35-1:36),OpGreaterThanOrEq(1:36-1:38),Int(1:38-1:40),OpOr(1:41-1:43),Int(1:44-1:46),OpLessThanOrEq(1:46-1:48),Int(1:48-1:49),OpSlash(1:49-1:50),Int(1:50-1:51),EndOfFile(1:51-1:51),
~~~
# PARSE
~~~clojure
(binop (1:1-1:51)
	"or"
	(binop (1:1-1:43)
		"or"
		(binop (1:1-1:20)
			">"
			(binop (1:1-1:14)
				"??"
				(apply (1:1-1:9)
					(tag (1:1-1:4) "Err")
					(ident (1:5-1:8) "" "foo"))
				(int (1:11-1:13) "12"))
			(binop (1:14-1:20)
				"*"
				(int (1:14-1:15) "5")
				(int (1:16-1:17) "5")))
		(binop (1:21-1:43)
			"and"
			(binop (1:21-1:31)
				"<"
				(binop (1:21-1:26)
					"+"
					(int (1:21-1:23) "13")
					(int (1:24-1:25) "2"))
				(int (1:26-1:27) "5"))
			(binop (1:32-1:43)
				">="
				(binop (1:32-1:38)
					"-"
					(int (1:32-1:34) "10")
					(int (1:35-1:36) "1"))
				(int (1:38-1:40) "16"))))
	(binop (1:44-1:51)
		"<="
		(int (1:44-1:46) "12")
		(binop (1:48-1:51)
			"/"
			(int (1:48-1:49) "3")
			(int (1:50-1:51) "5"))))
~~~
# FORMATTED
~~~roc
Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
~~~
# CANONICALIZE
~~~clojure
(e_runtime_error (1:1-1:51) "not_implemented")
~~~
# TYPES
~~~clojure
(expr 133 (type "Error"))
~~~