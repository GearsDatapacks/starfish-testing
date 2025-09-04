import gleam/erlang/process
import mist
import starfish
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    handle_request
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

fn handle_request(request: Request) -> Response {
  case wisp.path_segments(request) {
    ["move"] -> handle_move(request)
    _ -> wisp.ok()
  }
}

fn handle_move(request: Request) -> Response {
  use fen <- wisp.require_string_body(request)
  let game = starfish.from_fen(fen)
  let move_result =
    starfish.search(game, until: starfish.Time(milliseconds: 1000))
  case move_result {
    Ok(move) ->
      wisp.ok()
      |> wisp.string_body(starfish.to_long_algebraic_notation(move))
      |> wisp.set_header("Access-Control-Allow-Origin", "*")
    Error(Nil) ->
      wisp.internal_server_error()
      |> wisp.string_body("No moves found")
  }
}
