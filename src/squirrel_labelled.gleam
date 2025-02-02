import gleam/io
import gleam/option.{Some, None}
import gleam/string
import gleam/int
import gleam/result
import gleam/list
import gleam/regexp.{type Regexp, type Match, Match}
import simplifile

pub type Arg {
  Arg(
    num: Int,
    label: String,
  )
}

pub fn parse_args(sql: String) -> Result(List(Arg), String) {
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

pub fn foo() -> Nil {
  let assert Ok(src) = simplifile.read("../kohort/src/kohort/sql.gleam")

  let _func_srcs = parse_func_srcs(src)

  Nil
}

pub type Func {
  Func(
    name: String,
    src: String,
    query: String,
    params: List(String),
    sql_args: List(Arg),
  )
}

pub fn parse_func_srcs(src: String) -> List(Func) {
  let assert Ok(func_name_re) = regexp.from_string("pub\\s+fn\\s+(\\w+)[(]([^)]+)[)]")

  {
    let init_acc = #([], [])
    use acc, line <- list.fold(string.split(src, "\n"), init_acc)
    let #(funcs, curr) = acc

    case curr, line {
      [], "pub fn " <> _ -> #(funcs, [line])

      [], _ -> acc

      lines, "}" -> {
        let func =
          ["}", ..lines]
          |> list.reverse
          |> string.join("\n")

        #([func, ..funcs], [])
      }

      lines, _ -> #(funcs, [line, ..lines])
    }
  }
  |> fn(x) {
    let #(func_srcs, last_func_src_lines) = x
    [string.join(last_func_src_lines, "\n"), ..func_srcs]
  }
  |> list.filter(fn(str) { str != "" })
  |> list.map(fn(src) {
    case regexp.scan(func_name_re, string.replace(src, each: "\n", with: " ")) {
      [Match(_, [Some(name), Some(params)])] -> {
        let params =
          params
          |> string.split(",")
          |> list.map(string.trim)

        let query = parse_query(src)
        let assert Ok(sql_args) = parse_args(query)

        Func(name:, src:, query:, params:, sql_args:)
      }

      _ -> {
        io.debug(src)
        panic as "Failed to parse func name from above source"
      }
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
}

fn parse_query(src: String) -> String {
  let assert Ok(query_start_re) = regexp.from_string("^\\s*let\\s*query\\s*=\\s*(\"(.*))?$")

  src
  |> string.split("\n")
  |> list.drop_while(fn(str) { !regexp.check(query_start_re, str) })
  |> fn(from_query_start) {
    case from_query_start {
      [let_query_str, ..rest] -> {
        case regexp.scan(query_start_re, let_query_str) {
          [Match(_, [_, sql])] -> #(sql, rest)
          [Match(_, [])] -> #(None, rest)

          [] -> {
            io.debug(src)
            panic as "missing lines after `let query` match"
          }

          _ -> {
            io.debug(src)
            panic as "match of `let query` has an unexpected pattern of `submatches`"
          }
        }
      }

      _ -> {
        io.debug(src)
        panic as "failed to match `let query`"
      }
    }
    |> fn(x) {
      let assert Ok(lone_double_quote_re) = regexp.from_string("^\\s*\"\\s*$")

      let #(sql, rest) = x

      let line = option.unwrap(sql, "")

      let first_line_is_lone_double_quotes =
        rest
        |> list.first
        |> result.map(regexp.check(lone_double_quote_re, _))
        |> result.unwrap(False)

      let lines =
        case first_line_is_lone_double_quotes {
          False -> rest
          True -> list.drop(rest, 1)
        }
        |> list.take_while(fn(str) { !regexp.check(lone_double_quote_re, str)})

      [line, ..lines]
      |> string.join("\n")
      |> string.trim
    }
  }
}
