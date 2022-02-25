using ValSplit, Test

## Test basic functionality

# Define soundof(::Val) methods for :dog and :cat
soundof(animal::Val{:dog}) = "woof"
soundof(animal::Val{:cat}) = "nyan"

# Test first version of macro
@valsplit function soundof(Val(animal::Symbol))
    error("Sound not defined for animal: $animal")
end

@test soundof(:dog) == "woof"
@test soundof(:cat) == "nyan"

# soundof(::Symbol) should error for values without corresponding methods
@test_throws ErrorException soundof(:human) == "meh"

# soundof(::Symbol) should recompile after new methods are defined
soundof(animal::Val{:human}) = "meh"
@test soundof(:human) == "meh"

# Test macro with index argument
@valsplit 1 function soundof(animal::Symbol)
    return "???"
end

@test soundof(:unknown) == "???"

## Test splitting on multiple arguments

# Define soundof(animal::Val, lang::Val) methods
soundof(animal::Val{:cat}, lang::Val{:japanese}) = "nyan"
soundof(animal::Val{:cat}, lang::Val{:indonesian}) = "meong"

soundof(animal::Val{:frog}, lang::Val{:korean}) = "gaegul"
soundof(animal::Val{:frog}, lang::Val{:hindi}) = "tarr"
soundof(animal::Val{:frog}, lang::Val{:english}) = "ribbit"

@valsplit function soundof(Val(animal::Symbol), Val(lang::Symbol))
    error("Sound not defined.")
end

@test soundof(:cat, :japanese) == "nyan"
@test soundof(:cat, :indonesian) == "meong"

@test soundof(:frog, :korean) == "gaegul"
@test soundof(:frog, :hindi) == "tarr"
@test soundof(:frog, :english) == "ribbit"

@test_throws ErrorException soundof(:cat, :english) == "meow"
@test_throws ErrorException soundof(:dog, :english) == "woof"

soundof(::Val{:cat}, ::Val{:english}) = "meow"
soundof(::Val{:dog}, ::Val{:english}) = "woof"

@test soundof(:cat, :english) == "meow"
@test soundof(:dog, :english) == "woof"

## Test non-symbol method signatures

@valsplit function spelling(Val(n::T)) where {T <: Real}
    error("Unknown number.")
end

spelling(::Val{1}) = "one"
spelling(::Val{2}) = "two"
spelling(::Val{1.0}) = "one point zero"

@test spelling(1) == "one"
@test spelling(2) == "two"
@test spelling(1.0) == "one point zero"

@test_throws ErrorException spelling(π) == "pi"
@test_throws ErrorException spelling(ℯ) == "euler's number"

spelling(::Val{π}) = "pi"
spelling(::Val{ℯ}) = "euler's number"

@test spelling(π) == "pi"
@test spelling(ℯ) == "euler's number"

## Test that we can extend functions defined in another module

module Animals
    using ValSplit
    soundof(animal::Val{:dog}) = "woof"
    soundof(animal::Val{:cat}) = "nyan"
    @valsplit function soundof(Val(animal::Symbol))
        error("Sound not defined for animal: $animal")
    end
end

using .Animals

@test Animals.soundof(:dog) == "woof"
@test Animals.soundof(:cat) == "nyan"
@test_throws ErrorException Animals.soundof(:human) == "meh"

Animals.soundof(animal::Val{:human}) = "meh"

@test Animals.soundof(:human) == "meh"
