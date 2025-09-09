import gleam/erlang/process
import gleam/otp/actor
import mist
import starfish
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() {
  let assert Ok(actor) =
    actor.new(starfish.new()) |> actor.on_message(handle_message) |> actor.start

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)
  let assert Ok(_) =
    handle_request(_, actor.data)
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start
  process.sleep_forever()
}

type Message {
  RecordMove(move: String)
  Inspect(respond_with: process.Subject(starfish.Game))
  SetFen(fen: String)
  SetGame(game: starfish.Game)
}

fn handle_message(
  game: starfish.Game,
  message: Message,
) -> actor.Next(starfish.Game, Message) {
  case message {
    RecordMove(move:) -> {
      let assert Ok(legal) = starfish.parse_move(move, game)
      let game = starfish.apply_move(game, legal)
      actor.continue(game)
    }
    SetFen(fen:) -> {
      let assert Ok(game) = starfish.try_from_fen(fen)
      actor.continue(game)
    }
    SetGame(game:) -> actor.continue(game)
    Inspect(respond_with:) -> {
      process.send(respond_with, game)
      actor.continue(game)
    }
  }
}

fn handle_request(request: Request, actor: process.Subject(Message)) -> Response {
  case wisp.path_segments(request) {
    ["move"] -> handle_move(request, actor)
    ["get_move"] -> handle_get_move(request, actor)
    ["fen"] -> handle_fen(request, actor)
    _ -> wisp.ok()
  }
}

fn handle_move(request: Request, actor: process.Subject(Message)) -> Response {
  use move <- wisp.require_string_body(request)
  process.send(actor, RecordMove(move:))
  wisp.ok()
}

fn handle_get_move(
  _request: Request,
  actor: process.Subject(Message),
) -> Response {
  let game = actor.call(actor, 100, Inspect)
  let move_result =
    starfish.search(game, until: starfish.Time(milliseconds: 1000))
  case move_result {
    Ok(move) -> {
      let game = starfish.apply_move(game, move)
      process.send(actor, SetGame(game:))
      wisp.ok()
      |> wisp.string_body(starfish.to_long_algebraic_notation(move))
      |> wisp.set_header("Access-Control-Allow-Origin", "*")
    }
    Error(Nil) ->
      wisp.internal_server_error()
      |> wisp.string_body("No moves found")
  }
}

fn handle_fen(request: Request, actor: process.Subject(Message)) -> Response {
  use fen <- wisp.require_string_body(request)
  process.send(actor, SetFen(fen:))
  wisp.ok()
}
