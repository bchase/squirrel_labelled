import gleam/option.{type Option, Some, None}
import gleam/string
import gleam/int
import gleam/result
import gleam/list
import gleam/io
import gleam/regexp.{Match}

pub fn suppress_io_warnings() { io.debug(Nil) }

pub fn suppress_option_warnings() -> List(Option(Nil)) { [None, Some(Nil)] }

pub type Arg {
  Arg(
    num: Int,
    label: String,
  )
}

pub fn parse(sql: String) -> Result(List(Arg), String) {
  sql
  |> parse_sql_numbered_args
  |> list.map(parse_arg(_, sql))
  |> result.all
}

fn parse_sql_numbered_args(sql: String) -> List(Int) {
  let assert Ok(sql_arg_re) =
    "[$](\\d+)"
    |> regexp.compile(regexp.Options(case_insensitive: False, multi_line: True))

  sql
  |> regexp.scan(sql_arg_re, _)
  |> list.filter_map(fn(m) {
    case m {
      Match(submatches: [Some(int_str)], ..) -> Ok(int_str)
      _ -> Error(Nil)
    }
  })
  |> list.map(int.parse)
  |> result.values
  |> list.sort(int.compare)
}

fn parse_arg(arg_num: Int, sql: String) -> Result(Arg, String) {
  let assert Ok(label_re) =
    { "((\\w+[.])?\\w+)\\s+[=]\\s+[$]" <> int.to_string(arg_num) }
    |> regexp.compile(regexp.Options(case_insensitive: False, multi_line: True))

  case regexp.scan(label_re, sql) {
    [Match(submatches: [Some(label), ..], ..)] -> {
      let label = string.replace(label, each: ".", with: "_")
      Ok(Arg(num: arg_num, label: label))
    }
    [] -> Error("No label match")
    _ ->  Error("Multiple label matches")
  }
}
