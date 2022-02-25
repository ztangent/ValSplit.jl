module Benchmarks

export soundof, soundof_switch, soundof_dict, soundof_little, soundof_dynamic

using ValSplit
using OrderedCollections: LittleDict

const SOUND_OF = Dict{Symbol,String}()
const SOUND_OF_LITTLE = LittleDict{Symbol,String}()

N_VALS = 10
animals = [QuoteNode(Symbol(:animal, i)) for i in 1:N_VALS]
sounds = ["sound $i" for i in 1:N_VALS]

# Generate method definitions and dictionary assignments
for (animal, sound) in zip(animals, sounds)
    @eval begin
        soundof(animal::Val{$animal}) = $sound
        SOUND_OF[$animal] = $sound
        SOUND_OF_LITTLE[$animal] = $sound
    end
end

# Generate manual switch statement
cond_exprs = [:(animal == $a) for a in animals]
branch_exprs = [:(soundof(Val{$a}())) for a in animals]
switch_expr = ValSplit.generate_switch_stmt(cond_exprs, branch_exprs)
@eval function soundof_switch(animal::Symbol)
    $switch_expr
end

soundof_dynamic(animal::Symbol) = soundof(Val(animal))
soundof_dict(animal::Symbol) = SOUND_OF[animal]
soundof_little(animal::Symbol) = SOUND_OF_LITTLE[animal]
@valsplit soundof(Val(animal::Symbol)) = nothing

end

using BenchmarkTools
using .Benchmarks

idxs = rand(1:10, 10000)
animals = [Symbol(:animal, i) for i in idxs]
function test(f, animals)
    for a in animals
        f(a)
    end
end

println("Manual switch statement:")
@btime test(soundof_switch, animals)
println("Global Dict{Symbol,String}:")
@btime test(soundof_dict, animals)
println("Global LittleDict{Symbol,String}:")
@btime test(soundof_little, animals)
println("Dynamic dispatch:")
@btime test(soundof_dynamic, animals)
println("Val-splitting with @valsplit:")
@btime test(soundof, animals)
