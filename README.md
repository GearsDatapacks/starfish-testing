# Starfish testing

A project used for testing [starfish](https://github.com/GearsDatapacks/starfish),
although it could be pretty easily adapted to work with other chess engines instead.

## The test

Two versions of starfish play against each other: The stable version from the git
repository vs the new updated version that needs to be benchmarked. They play 102
games, one from each position in `silversuite.fen`, taken from the [Silver Suite](
https://en.chessbase.com/post/test-your-engines-the-silver-openings-suite). For
each position, each bot plays white and black to ensure a fair game. After all
games have been played, the program prints out a summary of the games. This can
be used to check whether the newer version is better than the previous version.

## How it works

Since we can't have two different versions of the same package (or even module)
in a Gleam project, we can't just pull in the two versions as two different
dependencies. What we do instead is have two additional projects: `starfish_original`,
which depends on `starfish` via git dependency, and `starfish_updated`, which
uses path dependencies to refer to the latest updated version. Each project starts
an HTTP server using `wisp`, and the main process asks each version in turn to
decide which move to play, and keeps track of the board state.

To run this you need to have the version of `starfish` you want to test in a
directory adjacent to this one, in order for the path dependencies to work
correctly. The use `run.sh` or run each project manually.
