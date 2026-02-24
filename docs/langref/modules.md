# Modules

Every .roc file specifies a _module_. Modules have two purposes:

- Namespacing 
- Hiding 

Roc has several different categories of modules, and they each hide different things:

- [Type modules](#type-modules) expose a single [type](types) and hide its behind-the-scenes implementation details such as private helper functions.
- [Package modules](#package-modules) expose one or more [type modules](#type-modules) and hide private modules that are only used behind the scenes.
- [Application modules](#app-modules) expose the entrypoints (e.g. `main`) required by the platform, and hide the implementation details which go into building those entrypoints.
- [Platform modules](#platform-modules) expose the [type modules](#type-modules) that application authors can import from the platform, and hide the configuration it uses to communicate with its lower-level [host](platforms#host) implementation.

## Type Modules

Type modules are specified by a .roc file with a capitalized name, such as `Url.roc`. 

The file must contain a top-level [nominal type](types#nominal-types) 
(which can be [opaque](types#opaque-types)) whose name is the same as the filename without
the `.roc` extension. So if a type module has a filename of `Url.roc`, then it must have  something like `Url :=` or `Url ::` defined at the top level. 

We call that "the module's type." So for the `Url.roc` module, its type is `Url`. 

### Hiding implementation details

While modules can import the `Url` type from `Url.roc`, they can't see anything else 
defined in the top level of `Url.roc`. So if `Url` defines a separate top-level nominal
type of `Foo :=` then that `Foo` type will only be visible inside `Url.roc`. Other 
modules won't be able to access it. Similarly, if it defines a function or constant 
named `blah =` at the top level, other modules won't be able to see that either.

The way to expose other nominal types, functions, and constants is to make them be
associated items on the `Url` type itself. For example:

```roc
Url :: { self : Str }.{
	# Other modules can access as Url.ParseErr
	ParseErr := … 
	
	# Other modules can access as Url.from_str
	from_str : … 
}
```

In this example, since `Url.ParseErr` is itself a type, you can nest other types inside it
to get something like `Url.ParseErr.Foo.blah`. The nesting can go as deep as you like, and
other modules can flatten out the nesting using `import` with the [`as` keyword](#import-as).

### Alias modules

If you want to make these nested modules easier to import, you can make an "alias module" whose
type is an alias of another type. For example, you could make `ParseErr.roc` and have its
type be a type alias of `Url.ParseErr` like so:

```roc
# ParseErr.roc

import Url

ParseErr : Url.ParseErr 
```

Now you could import `ParseErr` directly. This isn't commonly done for things like error types,
though, because having it qualified as `Url.ParseErr` is useful; it tells you that it's 
specifically a URL parsing error, which is more informative than a generic name like `ParseErr`.

Alias modules are more useful when exporting [mutually recursive types](#mutually-recursive-type-modules).

### Void modules

Although it is most common to organize modules around a single type, sometimes you just
want a collection of functions or constants. A classic example of this would be something like
`Util.roc`, which is a pattern that can be found in countless programming languages.

This is easy to do in Roc: expose a type which has no data inside it.

```roc
# Util.roc

Util :: [].{
	public_utility_function : …
	
	another_public_function : …
}

private_helper_fn : …
```

This is known as a _void module_ because it contains a type (namely, `[]`, which is
the [empty tag union type](tag-unions#void); the empty tag union type is known as "void" for short) that not only contains no information, but it can't even be instantiated. 

`Util` is [opaque](types#opaque-types), which prevents other modules from instantiating it,
and its backing type is `[]`, which means it can't even be instantiated inside `Util.roc`
itself. Choosing `[]` over `{}` for the backing type makes it clear that the `Util` type's
purpose is just to be a namespace, not to be a value that ever gets passed anywhere.

### Design Notes on Type Modules

Roc's "type modules" design is informed by the experiences of using modules in Elm and Rust.

#### Elm

In Elm, modules are formally decoupled from types, but there is a strong cultural norm of
coupling them whenever possible. 

For example, `Url.elm` defines the `Url` type and lists it among its publicly exposed items,
along with the public functions which operate on `Url`. Private helpers are not listed as 
exposed, and consumers of this module typically write  `import Url exposing (Url)` to bring
the `Url` type into scope. 

In Elm, when you call a  function like `Url.parse`, the capitalized `Url` refers to the
_module_ `Url`, not the type. But in a type annotation, like `Url -> Bool`, the capitalized
`Url` refers to the _type_ `Url` that was imported from the `Url` module. If `Url.elm` exposes
a `ParseError` type, you might refer to it as `Url.ParseError` in type annotations, where 
`Url` is the module name and `ParseError` is the type.

If you have a module like `Util.elm`, you still capitalize it, and still use `Util.foo`
to call a `foo` function it exposes, but you don't have to define a "void" `Util` type like
you would in Roc. The case of mutually recursive types (discussed [below](#mutually-recursive-types)) is similar to how it works in Roc; you'd define `FooBar.elm` which exposes the mutually recursive types `Foo` and `Bar`, and then import them using something like `import FooBar exposing (Foo, Bar)`.

Comparing Roc and Elm, the `Util` case is nicer in Elm (you don't the void `Util` type),
and it's more obvious how to organize mutually recursive types (in Elm, you're already doing
`import ____ exposing ____` as a matter of course). 

Roc optimizes for the common case at the expense of these less-common ones. You can 
`import Url` instead of `import Url exposing (Url)`, you don't need to list the type(s) 
and/or function(s) that `Url.roc` exposes (it's always just the type `Url` based on the
filename, and only that type's associated items are exposed), and both `Url.foo` and 
`Url -> Bool` refer to the _type_ `Url`. Similarly, `Url.ParseErr` refers to a `ParseErr` 
type associated with a `Url` type.

#### Rust

In Rust, it would be common to name the file `url.rs` and then import the `Url` type with 
`use crate::url::Url;`. Inside `url.rs` you'd find a definition of the `Url` type, along with
`impl Url { … }` where its associated items would be found. When you call a function like
`Url::parse` in Rust, the `Url` is referring to the _type_, because the `url` _module_ is
commonly lowercase in Rust.

As with Elm, it's common to have 

#### Roc

Both Elm and Roc do module-level caching, and disallow cyclic imports as a natural consequence. 
Rust allows cyclic module imports because it caches at the package ("crate" in Rust parlance)
level rather than the module level. (As a similar consequence, Rust disallows packages from
cyclically depending on one another, as do Elm and Roc.) Cyclic module imports can be
convenient in Rust, but Rust's lack of module-level caching is a significant contributing
factor to Elm and Roc being generally being known for much faster build times than Rust.

## `import` Statements

### Importing type modules

Roc's `import` statement lets you import [type modules](#type-modules) (and _only_ 
type modules; it doesn't let you import any other category of module).

### Renaming imported modules with `as`

### Importing constants

### Importing mutually recursive types

Occasionally, you may want to define two types in terms of each other. For example:

```roc
Foo := [BarVal(Bar), Nothing]

Bar := [FooVal(Foo), Nothing]
```

These [mutually recursive types](types#mutually-recursive) do not come up often, but when
they do, there's a helpful technique you can use to make them easier to import.

Since type modules expose a single type, you can't expose both `Foo` and `Bar` from the 
same `.roc` file. However, you can wrap them both in a [void module](#void-module) named something like `FooBar.roc`:

```roc
FooBar :: {}.{
	Foo := [BarVal(Bar), Nothing]
  
	Bar := [FooVal(Foo), Nothing]
}
```

At this point you can `import FooBar` and then reference `FooBar.Foo` and `FooBar.Bar`, 
or you could `import FooBar.Foo` and `import FooBar.Bar` to bring `Foo` and `Bar` into
scope unqualified.

You could also make separate [alias modules](#alias-modules) for `Foo` and `Bar`:

```roc
# Foo.roc

Foo : FooBar.Foo
```

```roc
# Bar.roc

Bar : FooBar.Bar
```

This would let you `import Foo` and `import Bar` even though they were defined in a single
module for purposes of referencing each other. This technique can be especially useful in 
[package modules](#package-modules), which can choose to expose `Foo` and `Bar` but not
`FooBar`, such that end users don't even see the `FooBar` wrapper type.

### Design Notes on Imports

Obviously, mutually recursive types take more effort to work with than other types. 

This was an intentional design decision based on how rarely mutually recursive types
come up in practice. The cost of making the rare case nicer was making the common case more
complex, which seemed like the wrong tradeoff to make. As such, the rare case (mutually
recursive types) is now more work, which is the accepted drawback of this design.

Another important factor in this choice was build times. Roc is designed to make each
individual module cacheable, so that the compiler doesn't need to redo work when there
are no relevant changes to modules. 

Some languages allow modules to import each other, forming _import cycles_. When module
imports form a cycle, then changing one module requires all the others in the cycle to be
rebuilt too. This makes cyclic imports a footgun for build times; it becomes very easy to
accidentally create a cycle, get no feedback that you have done this, and silently lose a
huge amount of caching. Worse, you can do this when a code base is small and not notice that
the compiler's ability to cache things has been decimated because even scratch-builds are
fast when a code base is small.

Roc intentionally disallows import cycles in order to prevent this from happening. If you
want to have modules reference each other, you have to put them in the same `.roc` file. This
adds friction (imports get more verbose, and the antidote for that is to create alias modules,
which is also extra effort), and that friction is the language naturally pushes back on a code
organization strategy which unavoidably harms build times. 

Having a large module cycle is easy to do by accident when cyclic imports are allowed, 
but it is very difficult to do accidentally when doing so requires putting everything in one
giant `.roc` file. Putting things into one file also makes it more obvious that the compiler
can't benefit from module-level caching when doing this, since everything is in one big file.

In summary, mutually recursive types (and module cycles) inherently slow down builds by
precluding caching. Roc's design naturally leads to faster builds by disallowing cyclic 
imports in favor of putting everything involved in a cycle into a single module, which makes
the unavoidable build time cost of doing so more obvious.

## Module Headers

[Type modules](#type-modules) specify which type they expose by choosing a filename that 
matches it.

## Package Modules

## Platform Modules

## Application Modules

### Headerless Application Modules
