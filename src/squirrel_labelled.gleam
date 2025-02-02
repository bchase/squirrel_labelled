import gleam/option.{Some}
import gleam/string
import gleam/int
import gleam/result
import gleam/list
import gleam/regexp.{type Regexp, type Match, Match}

pub type Arg {
  Arg(
    num: Int,
    label: String,
  )
}

pub fn parse(sql: String) -> Result(List(Arg), String) {
  case detect_query_type(sql) {
    Select | Update | Delete -> parse_select_update_delete_syntax(sql)
    Insert -> parse_insert_syntax(sql)
    Unknown | NoQuery -> Error("Query type could not be detected")
  }
}

type QueryType {
  Select
  Update
  Delete
  Insert
  Unknown
  NoQuery
}

fn detect_query_type(sql: String) -> QueryType {
  let assert Ok(whitespace_re) = regexp.from_string("\\s+")
  sql
  |> string.trim
  |> regexp.split(whitespace_re, _)
  |> fn(strs) {
    case strs {
      [] -> NoQuery
      [first_str, ..] ->
        case string.lowercase(first_str) {
          "select" -> Select
          "update" -> Update
          "delete" -> Delete
          "insert" -> Insert
          _ -> Unknown
        }
    }
  }
}

pub fn parse_insert_syntax(sql: String) -> Result(List(Arg), String) {
  let assert Ok(insert_re) =
    "INSERT\\s+INTO\\s+\\w+\\s+[(](.+)[)]\\s+VALUES\\s+[(](.+)[)]"
    |> regexp.from_string

  let assert Ok(label_re) =
    "^(\\w+)"
    |> regexp.from_string

  let assert Ok(arg_num_re) =
    "^[$](\\d+)"
    |> regexp.from_string

  sql
  |> string.replace(each: "\n", with: " ")
  |> regexp.scan(insert_re, _)
  |> fn(m) {
    case m {
      [Match(_, [Some(cols), Some(vals)])] -> {
        let cols =
          cols
          |> string.split(",")
          |> list.map(string.trim)

        let vals =
          vals
          |> string.split(",")
          |> list.map(string.trim)

        case list.length(cols) == list.length(vals) {
          False -> Error("Length mismatch for columns and values in `INSERT` statement")
          True ->
            list.zip(cols, vals)
            |> list.map(fn(x) {
              let #(col, val) = x

              let label = single_match_first_group(label_re, col)
              let arg_num =
                single_match_first_group(arg_num_re, val)
                |> result.then(int.parse)

              case label, arg_num {
                Ok(label), Ok(num) -> Ok(Arg(num:, label:))
                _, _ -> Error("Unable to match label or arg num")
              }
            })
            |> result.all
            |> result.map(fn(args) {
              args
              |> list.sort(fn(a, b) {
                int.compare(a.num, b.num)
              })
            })
        }
      }

      _ ->
        Error("Failed to match `INSERT` columns and values")
    }
  }
}

fn single_match_first_group(re: Regexp, str: String) -> Result(String, Nil) {
  case regexp.scan(re, str) {
    [Match(_, [Some(x), ..])] -> Ok(x)
    _ -> Error(Nil)
  }
}

pub fn parse_select_update_delete_syntax(sql: String) -> Result(List(Arg), String) {
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
