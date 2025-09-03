import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile as file
import starfish
import starfish/internal/board
import starfish/internal/move.{type Legal, type Move}

const fen_file = "silversuite.fen"

pub fn main() -> Nil {
  io.println("Loading games from file...")

  let assert Ok(games) =
    fen_file
    |> file.read
    |> result.map(string.split(_, "\n"))
    as "Failed to read game file"

  io.println("Loaded games. Running game 0...")

  let outcomes =
    list.index_map(games, fn(game, i) {
      let outcome = run_game(game)
      io.println(
        "Finished game "
        <> int.to_string(i)
        <> ", outcome "
        <> string.inspect(outcome),
      )
      io.println("Running game " <> int.to_string(i + 1) <> "...")
      outcome
    })

  let #(wins, draws, losses) =
    list.fold(outcomes, #(0, 0, 0), fn(tuple, outcome) {
      let #(wins, draws, losses) = tuple
      case outcome {
        White -> #(wins + 1, draws, losses)
        Draw -> #(wins, draws + 1, losses)
        Black -> #(wins, draws, losses + 1)
      }
    })

  io.println(
    "Wins: "
    <> int.to_string(wins)
    <> "\nDraws: "
    <> int.to_string(draws)
    <> "\nLosses: "
    <> int.to_string(losses),
  )

  Nil
}

type Outcome {
  White
  Black
  Draw
}

fn run_game(fen: String) -> Outcome {
  let assert Ok(game) = starfish.try_from_fen(fen)
    as "Failed to parse fen string"
  run_game_loop(game)
}

fn run_game_loop(game: starfish.Game) -> Outcome {
  case starfish.state(game) {
    starfish.BlackWin -> Black
    starfish.Draw(_) -> Draw
    starfish.WhiteWin -> White
    starfish.Continue -> {
      let best_move = get_best_move(game)

      run_game_loop(starfish.apply_move(game, best_move))
    }
  }
}

fn get_best_move(game: starfish.Game) -> Move(Legal) {
  let url = case game.to_move {
    board.White -> "http://0.0.0.0:8000/move"
    board.Black -> "http://0.0.0.0:8001/move"
  }

  let assert Ok(request) = request.to(url)
  let request =
    request
    |> request.set_body(starfish.to_fen(game))
    |> request.set_method(http.Post)
  let assert Ok(response) = httpc.send(request)

  let assert Ok(move) = starfish.parse_long_algebraic_notation(response.body)
  coerce_move(move)
}

fn coerce_move(move: Move(move.Valid)) -> Move(Legal) {
  case move {
    move.Capture(from:, to:) -> move.Capture(from:, to:)
    move.Castle(from:, to:) -> move.Castle(from:, to:)
    move.EnPassant(from:, to:) -> move.EnPassant(from:, to:)
    move.Move(from:, to:) -> move.Move(from:, to:)
    move.Promotion(from:, to:, piece:) -> move.Promotion(from:, to:, piece:)
  }
}
