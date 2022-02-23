"Returns type parameter for a `Val` type or instance."
val_param(::Val{T}) where {T} = T
val_param(::Type{Val{T}}) where {T} = T

"""
    args_tupletype_expr(arg_exprs, esc=identity)

Given `arg_exprs`, a list of positional argument expressions, such as
`[:(x::Int), :(y::Float64), :(z::T...)]`, return a `Tuple` type expression
whose parameters are the argument types, e.g. `Tuple{Int,Float64,Vararg{T}}`.
"""
function args_tupletype_expr(arg_exprs, esc=identity)
    ret = Expr(:curly)
    ret.args = map(arg_exprs) do arg
        # Detect splatting
        splatted = Meta.isexpr(arg, :(...), 1)
        if splatted
            arg = arg.args[1]
        end
        # Extract type expressions
        if Meta.isexpr(arg, :(::), 2)
            _, ty = arg.args
            ty = esc(ty)
        elseif arg isa Symbol
            ty = :Any
        else
            error("Unexpected form of argument: $arg")
        end
        # Wrap within Vararg if splatted
        if splatted
            ty = Expr(:curly, :Vararg, ty)
        end
        return ty
    end
    pushfirst!(ret.args, :Tuple)
    return ret
end
args_tupletype_expr(signature_def::Dict{Symbol}, esc=identity) =
    args_tupletype_expr(signature_def[:args], esc)

"""
    generate_switch_stmt(cond_exprs, branch_exprs, default_expr=:nothing)

Generates a switch expression using `if` and `elseif`, where `cond_exprs`
are the expressions for each branch condition, `branch_exprs` are the
expressions for statements to be executed within each branch, and `default_expr`
is the default statement if all conditions fail.
"""
function generate_switch_stmt(cond_exprs, branch_exprs, default_expr=:nothing)
    @assert length(cond_exprs) == length(branch_exprs)
    expr = default_expr
    for i in length(cond_exprs):-1:1
        head = i == 1 ? :if : :elseif
        expr = Expr(head, cond_exprs[i], branch_exprs[i], expr)
    end
    return expr
end
