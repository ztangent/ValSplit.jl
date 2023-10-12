module ValSplit

using ExprTools, Tricks

export @valsplit, valarg_params, valarg_has_param

include("utils.jl")

"""
    valarg_params(f, types::Type{<:Tuple}, idx::Int, ptype::Type=Any)
    valarg_params(f, idx::Int, ptypes::Type=Any)

Given a method signature `(f, types=Tuple{Vararg{Any}})`, finds all matching
methods with a concrete `Val`-typed argument in position `idx`, then returns
all parameter values for the `Val`-typed argument as a tuple. Optionally,
`ptype` can be specified to filter parameters that are instances of `ptype`.

    valarg_params(f, types::Type{<:Tuple}, idxs::Tuple, ptypes::Type)
    valarg_params(f, idxs::Tuple, ptypes::Type)

To find parameter values for multiple argument indices, `idxs` can also be
specified as a `Tuple`. To filter each argument separately, `ptypes` should be
specified as a `Tuple` type.

This function is statically compiled, and will automatically be recompiled
whenever a new method of `f` is defined.
"""
valarg_params

if VERSION >= v"1.10.0-DEV.609"
    function _valarg_params(world, source, T, N, P, self, f, types, idx, ptype)
        @nospecialize
        # Check if N and P are single values or tuples
        multi_idx = N isa Tuple
        if multi_idx
            idxs = collect(Int, N)
            P = P <: Tuple ? P : Tuple{fill(P, length(idxs))...}
        else
            idxs = [N]
        end
        # Extract parameters of Val-typed argument from matching methods
        vparams = Vector{P}()
        for m in Tricks._methods(f, T, nothing, world)
            argtypes = fieldtypes(m.sig)[2:end]
            all(idxs .<= length(argtypes)) || continue
            types = argtypes[idxs]
            all(ty <: Val && isconcretetype(ty) for ty in types) || continue
            ps = multi_idx ? Tuple(val_param.(types)) : val_param(types[1])
            ps isa P || continue
            push!(vparams, ps)
        end
        unique!(vparams)
        vparams = Tuple(vparams)
        # Create CodeInfo and add edges so if a method is defined this recompiles
        ci = Tricks.create_codeinfo_with_returnvalue(
            [Symbol("#self#"), :f, :types, :idx, :ptype],
            [:T, :N, :P], (:T, :N, :P), :($vparams))
        ci.edges = Tricks._method_table_all_edges_all_methods(f, T, world)
        return ci
    end
    @eval function valarg_params(
        @nospecialize(f) , @nospecialize(types::Type{T}),
        @nospecialize(idx::Val{N}), @nospecialize(ptype::Type{P}=Any)
    ) where {T <: Tuple, N, P}
        $(Expr(:meta, :generated, _valarg_params))
        $(Expr(:meta, :generated_only))
    end
else
    @generated function valarg_params(
        @nospecialize(f) , @nospecialize(types::Type{T}),
        @nospecialize(idx::Val{N}), @nospecialize(ptype::Type{P}=Any)
    ) where {T <: Tuple, N, P}
        # Check if N and P are single values or tuples
        multi_idx = N isa Tuple
        if multi_idx
            idxs = collect(Int, N)
            P = P <: Tuple ? P : Tuple{fill(P, length(idxs))...}
        else
            idxs = [N]
        end
        # Extract parameters of Val-typed argument from matching methods
        vparams = Vector{P}()
        for m in Tricks._methods(f, T)
            argtypes = fieldtypes(m.sig)[2:end]
            all(idxs .<= length(argtypes)) || continue
            types = argtypes[idxs]
            all(ty <: Val && isconcretetype(ty) for ty in types) || continue
            ps = multi_idx ? Tuple(val_param.(types)) : val_param(types[1])
            ps isa P || continue
            push!(vparams, ps)
        end
        unique!(vparams)
        vparams = Tuple(vparams)
        # Create CodeInfo and add edges so if a method is defined this recompiles
        ci = Tricks.create_codeinfo_with_returnvalue(
            [Symbol("#self#"), :f, :types, :idx, :ptype],
            [:T, :N, :P], (:T, :N, :P), :($vparams))
        ci.edges = Tricks._method_table_all_edges_all_methods(f, T)
        return ci
    end
end
valarg_params(f, types::Type{<:Tuple}, idx::Union{Int,Tuple}, ptype::Type=Any) =
    valarg_params(f, types, Val(idx), ptype)
valarg_params(f, idx::Val{N}, ptype::Type=Any) where {N} =
    valarg_params(f, Tuple{Vararg{Any}}, idx, ptype)
valarg_params(f, idx::Union{Int,Tuple}, ptype::Type=Any) =
    valarg_params(f, Tuple{Vararg{Any}}, Val(idx), ptype)

"""
    valarg_has_param(param, f, types::Type{<:Tuple}, idx::Int, ptype::Type=Any)
    valarg_has_param(param, f, idx::Int, ptype::Type=Any)

Given a method signature `(f, types)`, returns `true` if there exists a
matching method with a `Val`-typed argument in position `idx` with parameter
`param` and parameter type `ptype`.

    valarg_has_param(params, f, types::Type{<:Tuple}, idxs::Tuple, ptypes::Type)
    valarg_has_param(params, f, idxs::Tuple, ptypes::Type)

To check parameter values for multiple argument indices, `idxs` can also be
specified as a `Tuple`. To filter each argument separately, `ptypes` should be
specified as a `Tuple` type.
"""
valarg_has_param(param::P, f, types::Type{<:Tuple}, idx, ptype::Type{P}=Any) where {P} =
    param in valarg_params(f, types, idx, ptype)
valarg_has_param(param::P, f, idx, ptype::Type{P}=Any) where {P} =
    param in valarg_params(f, Tuple{Vararg{Any}}, idx, ptype)

"""
    _valswitch(::Val{Vs}, ::Val{I}, f, default_f, args...) where {Vs, I}

Generates a switch statement with `args[N] == v` where `v` ∈ `Vs` as the
branch conditions. Each branch with value `v` calls `f(args...)`, with
`args[idx]` replaced by `Val(v)`. If all branch conditions fail, `default_f`
is called with with no arguments.
"""
@generated function _valswitch(
    vals::Val{Vs}, idx::Val{I}, f, default_f, args::Vararg{Any,N}
) where {Vs, I, N}
    vals = map(QuoteNode, Vs)
    cond_exprs = [Expr(:call, :(==), :(args[$I]), v) for v in vals]
    branch_exprs = map(vals) do v
        args = [i == I ? :(Val($v)) : :(args[$i]) for i in 1:N]
        return Expr(:call, :f, args...)
    end
    default_expr = :(default_f())
    return generate_switch_stmt(cond_exprs, branch_exprs, default_expr)
end

"""
    _valsplit(expr, idx::Int, val_idxs=[idx])

Generates function expression(s) returned by `@valsplit` macro. `idx` is the
index of the argument to split on. `val_idxs` are the indices of all arguments
that are `Val`-typed, defining the set of matching methods to switch over.
"""
function _valsplit(def::Dict{Symbol}, idx::Int, val_idxs=[idx])
    if !haskey(def, :args) || length(def[:args]) < idx
        error("Function has less than $idx arguments")
    end
    # Fill-in unnamed functions and arguments
    def[:name] = fill_unnamed(get(gensym, def, :name))
    def[:args] = map(fill_unnamed, def[:args])
    # Extract function name, signature, and argument expressions
    fname = rm_type_annotation(def[:name])
    types = args_tupletype_expr(def[:args], esc)
    argnames = collect(args_tuple_expr(def[:args]).args)
    # Extract type of argument to split on
    ptype = types.args[idx + 1]
    types.args[val_idxs .+ 1] .= :Val
    if is_vararg_expr(ptype)
        error("Cannot split Vararg arguments.")
    end
    # Escape function name and arguments
    def[:name] = esc(def[:name])
    def[:args] = map(esc, def[:args])
    if haskey(def, :whereparams)
        def[:whereparams] = map(esc, def[:whereparams])
    end
    # Generate the function body
    def[:body] = quote
        # Look up the parameters for the Val-typed argument in position idx
        vals = valarg_params($(esc(fname)), $types, $idx, $ptype)
        # Default function returns the original function body
        function default_f() $(esc(def[:body])) end
        # Generate a switch expression over the Val-type parameters
        return _valswitch(Val(vals), Val($idx), $(esc(fname)), default_f,
                          $(map(esc, argnames)...))
    end
    # Return recombined function expression
    return combinedef(def)
end
_valsplit(expr::Expr, idx::Int, val_idxs=[idx]) =
    _valsplit(splitdef(expr), idx, val_idxs)

"""
    @valsplit f
    @valsplit idx::Int f

Given a function definition `f`, the `@valsplit` macro compiles away dynamic
dispatch over methods of `f` with `Val`-typed arguments at the specified
indices (i.e., it "splits" on `Val`-typed arguments, similar to union
splitting). The resulting method is automatically recompiled whenever a new
method of `f` is defined.

Using the first form of `@valsplit`, each argument `x::T` to split on
should be annotated as `Val(x::T)`. Alternatively, an argument index `idx` can
be manually specified using the second form of the macro.

# Example

Suppose we have a function `soundof` that returns how an animal sounds:

```julia
soundof(animal::Val{:dog}) = "woof"
soundof(animal::Val{:cat}) = "nyan"
```

Using `@valsplit`, we can define a new method for `soundof` that accepts a
`Symbol` argument, and branches to each instance of `soundof(::Val{T})`
(where `T` is a `Symbol`) defaulting to the function body otherwise:

```julia
@valsplit function soundof(Val(animal::Symbol))
    error("Sound not defined for animal: \$animal")
end
```

The resulting method is equivalent in behavior to the following:
```julia
function soundof(animal::Symbol)
    if animal == :dog
        return soundof(Val{:dog}())
    elseif animal == :cat
        return soundof(Val{:cat}())
    else
        error("Sound not defined for animal: \$animal")
    end
end
```

To split on multiple arguments at once, simply annotate each argument with
`Val` and use the first form of `@valsplit`:

```julia
soundof(animal::Val{:cat}, lang::Val{:japanese}) = "nyan"
```

The resulting method will be equivalent to a nested if statement.
"""
macro valsplit(expr)
    def = splitdef(expr)
    # Fill-in unnamed functions and arguments
    def[:name] = fill_unnamed(get(gensym, def, :name))
    def[:args] = map(fill_unnamed, def[:args])
    # Find arguments to split by value (notated by Val(arg::T))
    split_idxs = Int[]
    unwrapped_args = []
    for (i, arg) in enumerate(get(def, :args, []))
        if Meta.isexpr(arg, :call, 2) && arg.args[1] == :Val
            push!(split_idxs, i)
            push!(unwrapped_args, arg.args[2])
        else
            push!(unwrapped_args, arg)
        end
    end
    argnames = collect(args_tuple_expr(unwrapped_args).args)
    # Generate function definition for each argument to split on
    i_def = copy(def)
    i_def[:args] = unwrapped_args
    f_exprs = Expr[]
    while !isempty(split_idxs)
        idx = first(split_idxs)
        push!(f_exprs, _valsplit(copy(i_def), idx, split_idxs))
        popfirst!(split_idxs)
        # Adjust function signature for next definition
        V_typevar = gensym(:V)
        i_def[:args][idx] = Expr(:(::), argnames[idx], V_typevar)
        push!(get!(i_def, :whereparams, []), :($V_typevar <: $(QuoteNode(Val))))
    end
    # Add @__doc__ to first function definition
    f_exprs[1] = quote
        Core.@__doc__ $(f_exprs[1])
    end
    return Expr(:block, f_exprs...)
end

macro valsplit(idx::Int, expr)
    return _valsplit(expr, idx)
end

end
