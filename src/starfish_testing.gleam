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
        Draw(_) -> #(wins, draws + 1, losses)
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
  Draw(starfish.DrawReason)
}

fn run_game(fen: String, i: Int) -> List(Outcome) {
  let assert Ok(game) = starfish.try_from_fen(fen)
    as "Failed to parse fen string"

  io.println("Running match " <> int.to_string(i + 1) <> ", position " <> fen)

  update_fen(fen)

  let first_outcome = run_game_loop(game, UpdatedPlaysWhite)

  io.println("Finished first game of match, " <> print_outcome(first_outcome))

  io.println("Running again with reversed colours...")

  update_fen(fen)

  let second_outcome = run_game_loop(game, UpdatedPlaysBlack)

  io.println("Finished second game of match, " <> print_outcome(second_outcome))

  [first_outcome, second_outcome]
}

fn print_outcome(outcome: Outcome) -> String {
  case outcome {
    Original -> "original version won."
    Updated -> "updated version won."
    Draw(starfish.FiftyMoves) -> "fifty quiet moves occurred"
    Draw(starfish.InsufficientMaterial) -> "there was insufficient material"
    Draw(starfish.Stalemate) -> "it was stalemate"
    Draw(starfish.ThreefoldRepetition) -> "the position was repeated 3 times"
  }
}

type Configuration {
  UpdatedPlaysWhite
  UpdatedPlaysBlack
}

fn run_game_loop(game: starfish.Game, configuration: Configuration) -> Outcome {
  case starfish.state(game), configuration {
    starfish.Draw(reason), _ -> Draw(reason)
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

fn update_fen(fen: String) -> Nil {
  let assert Ok(original_req) = request.to(original_url <> "/fen")

  let assert Ok(response) =
    httpc.send(
      original_req |> request.set_body(fen) |> request.set_method(http.Post),
    )
  assert response.status == 200

  let assert Ok(updated_req) = request.to(updated_url <> "/fen")

  let assert Ok(response) =
    httpc.send(
      updated_req |> request.set_body(fen) |> request.set_method(http.Post),
    )
  assert response.status == 200

  Nil
}

const updated_url = "http://0.0.0.0:8000"

const original_url = "http://0.0.0.0:8001"

fn get_best_move(game: starfish.Game, configuration: Configuration) -> Move {
  let #(url, opposing_url) = case game.to_move, configuration {
    board.White, UpdatedPlaysWhite | board.Black, UpdatedPlaysBlack -> #(
      updated_url,
      original_url,
    )
    board.Black, UpdatedPlaysWhite | board.White, UpdatedPlaysBlack -> #(
      original_url,
      updated_url,
    )
  }

  let assert Ok(request) = request.to(url <> "/get_move")
  let assert Ok(response) = httpc.send(request)
  assert response.status == 200

  let assert Ok(move) = starfish.parse_move(response.body, game)

  let assert Ok(request) = request.to(opposing_url <> "/move")
  let assert Ok(response) =
    httpc.send(
      request
      |> request.set_body(response.body)
      |> request.set_method(http.Post),
    )
  assert response.status == 200

  move
}
