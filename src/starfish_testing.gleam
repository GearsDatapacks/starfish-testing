import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile as file
import starfish.{type Move}
import starfish/internal/board

const fen_file = "silversuite.fen"

pub fn main() -> Nil {
  io.println("Loading games from file...")

  let assert Ok(games) =
    fen_file
    |> file.read
    as "Failed to read game file"

  let games =
    games
    |> string.split("\n")
    // Use `#` for comments in the file
    |> list.filter(fn(game) { game != "" && !string.starts_with(game, "#") })

  io.println("Loaded games.")

  let outcomes = list.index_map(games, run_game) |> list.flatten

  let #(wins, draws, losses) =
    list.fold(outcomes, #(0, 0, 0), fn(tuple, outcome) {
      let #(wins, draws, losses) = tuple
      case outcome {
        Updated -> #(wins + 1, draws, losses)
        Draw -> #(wins, draws + 1, losses)
        Original -> #(wins, draws, losses + 1)
      }
    })

  io.println(
    "Updated version won "
    <> int.to_string(wins)
    <> " times.\nThe bots drew "
    <> int.to_string(draws)
    <> " times.\nOriginal version won "
    <> int.to_string(losses)
    <> " times.",
  )

  Nil
}

type Outcome {
  Updated
  Original
  Draw
}

fn run_game(fen: String, i: Int) -> List(Outcome) {
  let assert Ok(game) = starfish.try_from_fen(fen)
    as "Failed to parse fen string"

  io.println("Running match " <> int.to_string(i) <> ", position " <> fen)

  let first_outcome = run_game_loop(game, UpdatedPlaysWhite)

  io.println("Finished first game of match, " <> print_outcome(first_outcome))

  io.println("Running again with reversed colours...")

  let second_outcome = run_game_loop(game, UpdatedPlaysBlack)

  io.println("Finished second game of match, " <> print_outcome(second_outcome))

  [first_outcome, second_outcome]
}

fn print_outcome(outcome: Outcome) -> String {
  case outcome {
    Draw -> "it was a draw."
    Original -> "original version won."
    Updated -> "updated version won."
  }
}

type Configuration {
  UpdatedPlaysWhite
  UpdatedPlaysBlack
}

fn run_game_loop(game: starfish.Game, configuration: Configuration) -> Outcome {
  case starfish.state(game), configuration {
    starfish.Draw(_), _ -> Draw
    starfish.BlackWin, UpdatedPlaysBlack | starfish.WhiteWin, UpdatedPlaysWhite ->
      Updated
    starfish.BlackWin, UpdatedPlaysWhite | starfish.WhiteWin, UpdatedPlaysBlack ->
      Original
    starfish.Continue, _ -> {
      let best_move = get_best_move(game, configuration)

      run_game_loop(starfish.apply_move(game, best_move), configuration)
    }
  }
}

fn get_best_move(game: starfish.Game, configuration: Configuration) -> Move {
  let url = case game.to_move, configuration {
    board.White, UpdatedPlaysWhite | board.Black, UpdatedPlaysBlack ->
      "http://0.0.0.0:8000/move"
    board.Black, UpdatedPlaysWhite | board.White, UpdatedPlaysBlack ->
      "http://0.0.0.0:8001/move"
  }

  let assert Ok(request) = request.to(url)
  let request =
    request
    |> request.set_body(starfish.to_fen(game))
    |> request.set_method(http.Post)
  let assert Ok(response) = httpc.send(request)

  let assert Ok(move) =
    starfish.parse_long_algebraic_notation(response.body, game)
  move
}
