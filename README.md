# ValSplit.jl

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ztangent/ValSplit.jl/CI.yml?branch=main)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/ztangent/ValSplit.jl)
![GitHub](https://img.shields.io/github/license/ztangent/ValSplit.jl?color=lightgrey)

Compile away dynamic dispatch over methods with `Val`-typed arguments by "`Val`-splitting" (similar to [union splitting](https://julialang.org/blog/2018/08/union-splitting/)) using the `@valsplit` macro. By annotating a function definition with `@valsplit` and choosing arguments to split upon, the resulting function will be a switch statement over all `Val` parameters associated with the chosen arguments. Requires Julia 1.3 and above.

## Installation

ValSplit.jl is a registered package. To install, press `]` at the Julia REPL to enter `Pkg` mode, then run:
```
add ValSplit
```

## Example

Suppose we have a function `soundof` that takes in a `Val`-typed argument,  and returns how an animal sounds:

```julia
soundof(animal::Val{:dog}) = "woof"
soundof(animal::Val{:cat}) = "nyan"
```

We might want a version of `soundof` that takes in `Symbol` values directly, and hence define:
```julia
soundof(animal::Symbol) = soundof(Val(animal))
```

However, when using `soundof(animal::Symbol)` in another function, dynamic dispatch might occur if Julia cannot infer the value of the argument `animal` at compile time, resulting in [considerable slowdowns](https://docs.julialang.org/en/v1/manual/performance-tips/#man-performance-value-type).


Using `@valsplit`, we can avoid this issue by *compiling away the dispatch logic as a switch statement*. We do this simply by annotating our method definition with `@valsplit`, and annotating each argument `x::T` we want to switch upon as `Val(x::T)`:
```julia
@valsplit function soundof(Val(animal::Symbol))
    error("Sound not defined for animal: \$animal")
end
```

The resulting function effectively compiles to the following switch statement,  where the original method body is used as the default branch:
```julia
function soundof(animal::Symbol)
    if animal == :dog
        return "woof"
    elseif animal == :cat
        return "nyan"
    else
        error("Sound not defined for animal: \$animal")
    end
end
```

However, unlike a manually-written switch statement, `@valsplit`-defined functions will automatically recompile when new methods are added. For example, if we add the method:
```julia
soundof(animal::Val{:human}) = "meh"
```

Then `soundof(animal::Symbol)` will recompile to a switch statement with an additional branch:
```julia
function soundof(animal::Symbol)
    if animal == :dog
        return "woof"
    elseif animal == :cat
        return "nyan"
    elseif animal == :human
        return "meh"
    else
        error("Sound not defined for animal: \$animal")
    end
end
```

As such, `@valsplit`-annotated functions preserve extensibility, while achieving the run-time performance of switch statements (or better, if constant propagation results in compile-time pruning of branches).

## Motivation

The `@valsplit` macro is intended to address the following two issues:
- Dynamic dispatch over `Val`-typed arguments is slow
- Alternative solutions such as manually-written switch statements and global dictionaries are often insufficient for the purposes of extensibility.

Note that dynamic dispatch does not always occur: When there are a small number of values to split on (less than 4, as of Julia 1.6), the Julia compiler automatically generates a switch statement:

```julia
soundof(animal::Val{:dog}) = "woof"
soundof(animal::Val{:cat}) = "nyan"
soundof(animal::Symbol) = soundof(Val(animal))

julia> @code_typed soundof(:cat)
CodeInfo(
1 ─ %1  = invoke Main.Val(_2::Symbol)::Val{_A} where _A
│   %2  = (isa)(%1, Val{:cat})::Bool
└──       goto #3 if not %2
2 ─       goto #6
3 ─ %5  = (isa)(%1, Val{:dog})::Bool
└──       goto #5 if not %5
4 ─       goto #6
5 ─ %8  = Main.soundof(%1)::String
└──       goto #6
6 ┄ %10 = φ (#2 => "nyan", #4 => "woof", #5 => %8)::String
└──       return %10
) => String
```

But once more methods are defined, the Julia compiler no longer performs this optimization:

```julia
for i in 1:4
    sound = "sound $i"
    eval(:(soundof(animal::Val{Symbol(:animal, $i)}) = $sound))
end
soundof(animal::Symbol) = soundof(Val(animal))

julia> @code_typed soundof(:animal1)
CodeInfo(
1 ─ %1 = invoke Main.Val(_2::Symbol)::Val{_A} where _A
│   %2 = Main.soundof(%1)::Any
└──      return %2
) => Any
```

To avoid dynamic dispatch, manually switching on a set of values is the fastest in terms of both compile-time and run-time, but the set of values to switch upon cannot be extended. Global dictionaries can partially address this problem by associating values with code:

```julia
const SOUND_OF = Dict{Symbol,Function}()

woof() = "woof"
SOUND_OF[:dog] = woof

nyan() = "nyan"
SOUND_OF[:cat] = nyan

soundof(animal::Symbol) = SOUND_OF[animal]()
```

However, dictionary lookup times [are usually slower](https://groups.google.com/g/julia-users/c/jUMu9A3QKQQ/m/qjgVWr7vAwAJ) compared to (small) switch statements. In addition, this approach [runs into issues with precompilation](https://docs.julialang.org/en/v1/manual/modules/#Module-initialization-and-precompilation), preventing a downstream module from adding new entries to a global dictionary defined in another module (except at run-time using the `__init__` function). In other words, global dictionaries are not extensible across module boundaries.

The `@valsplit` macro addresses this problem because new methods can always be introduced by downstream modules, resulting in recompilation of the `@valsplit` annotated function. It effectively uses Julia's method table as a global dictionary, but avoids the overhead of dynamic dispatch using the same `@generated` function tricks used to implement `static_hasmethod` in [`Tricks.jl`](https://github.com/oxinabox/Tricks.jl).

A small benchmark is [provided here](benchmarks/benchmarks.jl). With 10 values to branch on, running Julia 1.6.1 on a Windows machine, the results of the benchmark are as follows:

```julia
Manual switch statement:
  3.275 μs (0 allocations: 0 bytes)
Global Dict{Symbol,String}:
  78.800 μs (0 allocations: 0 bytes)
Global LittleDict{Symbol,String}:
  111.600 μs (0 allocations: 0 bytes)
Dynamic dispatch:
  2.300 ms (0 allocations: 0 bytes)
Val-splitting with @valsplit:
  3.275 μs (0 allocations: 0 bytes
```

## Utilities

ValSplit.jl provides a few other utility functions for determining whether a method with particular `Val`-typed argument exists.

To determine the set of all `Val` parameters associated with a particular argument of a particular function, use `valarg_params`:

>    `valarg_params(f, types::Type{<:Tuple}, idx::Int, ptype::Type=Any)`
>
> Given a method signature `(f, types)`, finds all matching methods with a concrete `Val`-typed argument in position `idx`, then returns all parameter values for the `Val`-typed argument as a tuple. Optionally, `ptype` can be specified to filter parameter values that are instances of `ptype`.
>
>This function is statically compiled, and will automatically be recompiled whenever a new method of `f` is defined.

To determine whether a particular argument of a particular function has a specific `Val` parameter, use `valarg_has_param`:

>    `valarg_has_param(f, types::Type{<:Tuple}, param, idx::Int, ptype::Type=Any)`
>
> Given a method signature `(f, types)`, returns `true` if there exists a matching method with a `Val`-typed argument in position `idx` with parameter `param` and parameter type `ptype`.
