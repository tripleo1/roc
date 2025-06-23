# META
~~~ini
description=fuzz crash
type=file
~~~
# SOURCE
~~~roc
 f{o,
     ]

foo =

    "onmo %
~~~
# PROBLEMS
**MISMATCHED BRACE**
This brace does not match the corresponding opening brace.

**UNCLOSED STRING**
This string is missing a closing quote.

**MISSING HEADER**
Roc files must start with a module header.

For example:
        module [main]
or for an app:
        app [main!] { pf: platform "../basic-cli/platform.roc" }
Here is the problematic code:
**fuzz_crash_009.md:1:2:1:4:**
```roc
 f{o,
```


**INVALID STATEMENT**
The statement **expr** is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

# TOKENS
~~~zig
LowerIdent(1:2-1:3),OpenCurly(1:3-1:4),LowerIdent(1:4-1:5),Comma(1:5-1:6),Newline(1:1-1:1),
CloseCurly(2:6-2:7),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(4:1-4:4),OpAssign(4:5-4:6),Newline(1:1-1:1),
Newline(1:1-1:1),
StringStart(6:5-6:6),StringPart(6:6-6:12),EndOfFile(6:12-6:12),
~~~
# PARSE
~~~clojure
(file (1:2-6:12)
	(malformed_header (1:2-1:4) "missing_header")
	(statements
		(record (1:3-2:7) (field "o"))
		(decl (4:1-6:12)
			(ident (4:1-4:4) "foo")
			(string (6:5-6:12) (string_part (6:6-6:12) "onmo %")))))
~~~
# FORMATTED
~~~roc
{
	o,
}

foo = 

	"onmo %"
~~~
# CANONICALIZE
~~~clojure
(can_ir
	(d_let
		(def_pattern
			(p_assign (4:1-4:4)
				(pid 73)
				(ident "foo")))
		(def_expr
			(e_string (6:5-6:12) (e_literal (6:6-6:12) "onmo %")))))
~~~
# TYPES
~~~clojure
(inferred_types
	(defs
		(def "foo" 76 (type "Str")))
	(expressions
		(expr (6:5-6:12) 75 (type "Str"))))
~~~