using ValSplit, Test

## Basic test ##

soundof(animal::Val{:dog}) = "woof"
soundof(animal::Val{:cat}) = "nyan"

@valsplit function soundof(Val(animal::Symbol))
    error("Sound not defined for animal: \$animal")
end

@test soundof(:dog) == "woof"
@test soundof(:cat) == "nyan"
@test_throws ErrorException soundof(:human) == "meh"

soundof(animal::Val{:human}) = "meh"

@test soundof(:human) == "meh"

## Test that we can extend functions defined in another module ##

module Animals
    using ValSplit
    soundof(animal::Val{:dog}) = "woof"
    soundof(animal::Val{:cat}) = "nyan"
    @valsplit function soundof(Val(animal::Symbol))
        error("Sound not defined for animal: \$animal")
    end
end

using .Animals

@test Animals.soundof(:dog) == "woof"
@test Animals.soundof(:cat) == "nyan"
@test_throws ErrorException Animals.soundof(:human) == "meh"

Animals.soundof(animal::Val{:human}) = "meh"

@test Animals.soundof(:human) == "meh"
