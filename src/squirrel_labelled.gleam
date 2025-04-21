import gleam/io
import gleam/dict
import gleam/set.{type Set}
import gleam/option.{type Option, Some, None}
import gleam/string
import gleam/int
import gleam/result
import gleam/list
import gleam/regexp.{type Regexp, type Match, Match}
import simplifile
import tom

pub type Arg {
  Arg(
    num: Int,
    label: String,
    opts: List(Opt),
  )
}

pub type Opt = List(String)

fn parse_opts(magic_comment: Option(String)) -> List(Opt) {
  let assert Ok(ws_re) =
    "\\s+"
    |> regexp.from_string

  let assert Ok(opt_raw_re) =
    "^squirrel (.+)$"
    |> regexp.from_string

  magic_comment
  |> option.map(fn(magic_comment) {
    magic_comment
    |> string.split(",")
    |> list.map(string.trim)
    |> list.map(fn(str) {
      case regexp.scan(opt_raw_re, str) {
        [Match(_, [Some(opt_raw)])] ->
          opt_raw
          |> regexp.split(ws_re, _)
          |> Some

        _ ->
          None
      }
    })
    |> option.values
  })
  |> option.unwrap([])
}

pub fn main() {
  let squirrel_sql = "src/" <> project_name() <> "/sql.gleam"
  let assert Ok(src) = simplifile.read(squirrel_sql)

  write_squirrel_wrapper_funcs_with_labelled_params(src)

  Nil
}

fn project_name() -> String {
  let assert Ok(output) = simplifile.read("gleam.toml")
  let assert Ok(config) = tom.parse(output)

  case tom.get_string(config, ["name"]) {
    Error(_) -> panic as "Cannot determine project name from `gleam.toml`"
    Ok(name) -> name
  }
}

pub fn write_squirrel_wrapper_funcs_with_labelled_params(src: String) -> Nil {
  let project_name = project_name()
  let file = "src/" <> project_name <> "/labelled_sql.gleam"

  let funcs = parse_func_srcs(src)

  let funcs_src =
    funcs
    |> list.map(fn(func) {
      let params = labelled_params_for(func)
      wrapper_func_src(func, params)
    })
    |> string.join("\n\n")

  let output =
    case contains_copied_squirrel_src(funcs) {
      True ->
        [
          [
            ["import " <> project_name <> "/sql"],
            imports(),
          ]
          |> list.flatten
          |> string.join("\n")
          ,
          uuid_decoder_func_src(),
          nullable_uuid_func_src(),
          funcs_src,
        ]
        |> string.join("\n\n")

      False ->
        [
          "import " <> project_name <> "/sql",
          funcs_src,
        ]
        |> string.join("\n\n")
    }


  let assert Ok(_) = simplifile.write(file, output)

  Nil
}

fn contains_copied_squirrel_src(funcs: List(Func)) -> Bool {
  list.any(funcs, fn(func) { list.any(func.sql_args, has_nullable_opt) })
}

fn imports() -> List(String) {
  [
    "import gleam/option.{type Option, Some, None}",
    "import gleam/dynamic/decode",
    "import youid/uuid.{type Uuid}",
    "import pog",
  ]
}

fn uuid_decoder_func_src() -> String {
"
pub fn uuid_decoder() {
  use bit_array <- decode.then(decode.bit_array)
  case uuid.from_bit_array(bit_array) {
    Ok(uuid) -> decode.success(uuid)
    Error(_) -> decode.failure(uuid.v7(), \"uuid\")
  }
}
"
  |> string.trim
}

fn nullable_uuid_func_src() -> String {
"
pub fn nullable_uuid(
  opt: Option(Uuid),
) -> pog.Value {
  case opt {
    None ->
      pog.null()

    Some(uuid) ->
      uuid
      |> uuid.to_string
      |> pog.text
  }
}
"
  |> string.trim
}

pub fn parse_args_(sql: String) -> Result(List(Arg), String) {
  case detect_query_type(sql) {
    Select | Update | Delete -> parse_select_update_delete_syntax(sql)
    Insert -> parse_insert_syntax(sql)
    Unknown | NoQuery -> {

      io.debug(sql)
      Error("Query type could not be detected")
    }
  }
  |> result.map(disambiguate_sql_keyword_args)
  |> result.map(adjust_gleam_keyword_labelled_args)
  |> result.map(list.unique)
}

pub fn parse_args(sql: String) -> Result(List(Arg), String) {
  let query = parse_cte_queries(sql, [])

  [query.sql, ..query.ctes]
  |> list.map(parse_args_)
  |> result.all
  |> result.map(list.flatten)
  |> result.map(fn(args) {
    args
    |> list.group(fn(arg) { arg.num })
    |> dict.map_values(fn(_num, args) {
      let opts =
        args
        |> list.flat_map(fn(arg) { arg.opts })
        |> list.unique

      case args {
        [] -> None
        [Arg(num:, label:, ..), ..] -> Some(Arg(num:, label:, opts:))
      }
    })
    |> dict.values
    |> option.values
  })
}

type QueryType {
  Select
  Update
  Delete
  Insert
  Unknown
  NoQuery
}

type Query {
  Query(
    sql: String,
    ctes: List(String),
  )
}

fn parse_cte_queries(sql: String, ctes: List(String)) -> Query {
  let assert Ok(comma_start) =
    "^\\s*[,]\\s*"
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: True))

  let assert Ok(cte_start) =
    "^(\\s*WITH)?\\s*[a-z]\\w*\\s*AS\\s*"
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: True))

  let sql =
    sql
    |> regexp.replace(comma_start, _, "")
    |> regexp.replace(cte_start, _,  "")

  case consume_all_within_parens(sql) {
    #("", sql) ->
      Query(sql:, ctes:)

    #(cte, rest) ->
      parse_cte_queries(rest, list.append(ctes, [cte]))
  }
}

fn consume_all_within_parens(str: String) -> #(String, String) {
  case string.starts_with(str, "(") {
    False -> #("", str)
    True ->
      str
      |> string.to_graphemes
      |> list.fold(#("", "", 0), fn(x, char) {
        let #(in_parens, after_parens, parens) = x

        case parens, char {
          0, "(" -> #(in_parens, after_parens, parens)
          0, _ -> #(in_parens, after_parens <> char, parens)
          _, "(" -> #(in_parens <> char, after_parens, parens + 1)
          _, ")" -> #(in_parens <> char, after_parens, parens - 1)
          _, _ -> #(in_parens <> char, after_parens, parens)
        }
      })
      |> fn(x) {
        let #(in, after, _) = x

        let in =
          in
          |> string.drop_start(1)
          |> string.drop_end(1)

        #(in, after)
      }
  }
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
    "INSERT\\s+INTO\\s+\\w+\\s+(as\\s+\\w+\\s+)?[(](.+)[)]\\s+VALUES\\s+[(](.+)[)]"
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: False))

  let assert Ok(label_re) =
    "^(\\w+)"
    |> regexp.from_string

  let assert Ok(arg_num_re) =
    "^[$](\\d+)"
    |> regexp.from_string

  sql
  |> string.replace(each: "\n", with: "\t")
  |> regexp.scan(insert_re, _)
  |> fn(m) {
    let assert Ok(empty_or_whitespace_re) = regexp.from_string("^\\s*$")
    let assert Ok(line_re) =
      //              1                       2      3         4
      "^\\s*[\\]?[\"]?(\\w+)[\\]?[\"]?[,]?\\s*([-]{2}([$])?\\s*(.+))?$"
      |> regexp.from_string

    case m {
      [Match(_, [_, Some(cols), Some(vals)])] -> {
        let cols =
          cols
          |> string.split("\t")
          |> list.filter(fn(str) {
            !regexp.check(empty_or_whitespace_re, str)
          })
          |> list.map(fn(str) {
            let str =
              str
              |> string.replace(each: "\\", with: "")
              |> string.replace(each: "\"", with: "")

            case regexp.scan(line_re, str) {
              [Match(_, [Some(val), _, Some(_), comment])] ->  {
                #(
                  val |> string.trim,
                  comment |> option.map(string.trim),
                )
              }

              [Match(_, [Some(val), ..])] ->{
                #(
                  val |> string.trim,
                  None,
                )
              }

              _ -> {
                io.debug(str)
                panic as "could not find `INSERT` value"
              }
            }
          })

        let vals =
          vals
          |> string.split(",")
          |> list.map(string.trim)
          |> list.map(single_match_first_group(arg_num_re, _))
          |> result.values
          |> list.map(int.parse)

        case list.length(cols) == list.length(vals) {
          False -> Error("Length mismatch for columns and values in `INSERT` statement")
          True ->
            list.zip(cols, vals)
            |> list.map(fn(x) {
              let #(col, arg_num) = x

              let #(col, comment) = col
              let label = single_match_first_group(label_re, col)
              let opts = parse_opts(comment)

              case label, arg_num {
                Ok(label), Ok(num) -> Ok(Arg(num:, label:, opts:))
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
  parse_column_arg(arg_num, sql)
  |> result.lazy_or(fn() { parse_any_arg(arg_num, sql)} )
  |> result.lazy_or(fn() { parse_non_column_arg(arg_num, sql)} )
}

pub type SqlKeyword {
  Limit
  Offset
  OrderBy
}

fn parse_non_column_arg_(arg_num: Int, sql: String) -> Result(#(SqlKeyword, Option(String)), String) {
  let assert Ok(order_by_re) =
    { "ORDER\\s+BY\\s+[$]" <> int.to_string(arg_num) <> "(\\s*[-][-][$]\\s*(.+))?" }
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: True))

  let assert Ok(limit_re) =
    { "LIMIT\\s+[$]" <> int.to_string(arg_num) <> "(\\s*[-][-][$]\\s*(.+))?" }
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: True))

  let assert Ok(offset_re) =
    { "OFFSET\\s+[$]" <> int.to_string(arg_num) <> "(\\s*[-][-][$]\\s*(.+))?" }
    |> regexp.compile(regexp.Options(case_insensitive: True, multi_line: True))

  [
    #(order_by_re, OrderBy),
    #(limit_re, Limit),
    #(offset_re, Offset),
  ]
  |> list.find_map(fn(x) {
    let #(re, sk) = x

    case regexp.scan(re, sql) {
      [] -> Error(Nil)

      [Match(submatches: [_, comment], ..)] ->
        Ok(#(sk, comment))

      _ ->
        Ok(#(sk, None))

    }
  })
  |> result.replace_error("No `SqlKeyword` match")
}

fn sql_keyword_to_str(sk: SqlKeyword) -> String {
  case sk {
    Limit -> "limit"
    OrderBy -> "order_by"
    Offset -> "offset"
  }
}

fn all_sql_keywords() -> Set(SqlKeyword) {
  let _totality_check =
    fn(sk) {
      case sk {
        Limit -> Nil
        OrderBy -> Nil
        Offset -> Nil
      }
    }

  [
    Limit,
    OrderBy,
    Offset,
  ]
  |> set.from_list
}

fn parse_non_column_arg(num: Int, sql: String) -> Result(Arg, String) {
  case parse_non_column_arg_(num, sql) {
    Error(err) -> Error(err)
    Ok(x) ->
      {
        let #(sk, comment_str) = x
        let label = sql_keyword_to_str(sk)

        let opts =
          comment_str
          |> parse_opts
          |> list.append([["_squirrel_sql_keyword"]])

        Arg(label:, num:, opts:)
      }
      |> Ok
  }
}

const gleam_keywords = [
  "type",
]

fn adjust_gleam_keyword_labelled_args(args: List(Arg)) -> List(Arg) {
  args
  |> list.map(fn(arg) {
    case arg.label |> list.contains(gleam_keywords, _) {
      False -> arg
      True -> Arg(..arg, label: arg.label <> "_", opts: list.append(arg.opts, [
        [ "_squirrel_gleam_keyword" ]
      ]))
    }
  })
}

fn disambiguate_sql_keyword_args(args: List(Arg)) -> List(Arg) {
  all_sql_keywords()
  |> set.to_list
  |> list.fold(args, fn(acc, sk) {
    acc
    |> disambiguate_sql_keyword_arg(sk, _)
  })
  // list.map(args, disambiguate_sql_keyword_arg())
}

fn disambiguate_sql_keyword_arg(sk: SqlKeyword, args: List(Arg)) -> List(Arg) {
  let sk = sql_keyword_to_str(sk)

  let count =
    args
    |> list.filter(fn(arg) { arg.label == sk })
    |> list.length

  case count > 1 {
    False -> args
    True ->
      args
      |> list.map(fn(arg) {
        case arg.label == sk && is_sql_keyword_arg(arg) {
          False -> arg
          True -> Arg(..arg, label: arg.label <> "_")
        }
      })
  }
}

fn is_sql_keyword_arg(arg: Arg) -> Bool {
  list.any(arg.opts, fn(opt) { opt == [ "_squirrel_sql_keyword" ] })
}

fn parse_column_arg(arg_num: Int, sql: String) -> Result(Arg, String) {
  let assert Ok(label_re) =
    // TODO https://www.postgresql.org/docs/current/functions-comparison.html
    { "((\\w+[.])?\\w+)\\s+(=|>=|<=|>|<|IS|IS NOT)\\s+[$]" <> int.to_string(arg_num) <> "\\b\\s*([-][-][$]\\s*([^\\n]+))?" }
    // 12                  3                                                                    4             5
    |> regexp.compile(regexp.Options(case_insensitive: False, multi_line: True))

  case regexp.scan(label_re, sql) {
    [Match(submatches: [Some(label), Some(_prefix), _, _, comment], ..), ..] |
    [Match(submatches: [Some(label), _, _, _, comment], ..), ..] -> {
      let label = string.replace(label, each: ".", with: "_")
      let comment = comment |> option.map(string.trim)
      let opts = parse_opts(comment)
      Ok(Arg(num: arg_num, label: label, opts: opts))
    }

    [Match(submatches: [Some(label), ..], ..), ..] -> {
      let label = string.replace(label, each: ".", with: "_")
      Ok(Arg(num: arg_num, label: label, opts: []))
    }

    [] -> Error("No label match")

    _ ->  Error("Multiple label matches")
  }
}


fn parse_any_arg(arg_num: Int, sql: String) -> Result(Arg, String) {
  let assert Ok(label_re) =
    { "((\\w+[.])?\\w+)\\s*[=]\\s*ANY[(][$]" <> int.to_string(arg_num) <> "[)]\\s*([-][-][$]\\s*([^\\n]+))?" }
    // 12                                                                         3             4
    |> regexp.compile(regexp.Options(case_insensitive: False, multi_line: True))

  case regexp.scan(label_re, sql) {
    [Match(submatches: [Some(label), Some(_prefix), _, comment], ..), ..] |
    [Match(submatches: [Some(label), _, comment], ..), ..] -> {
      let label = string.replace(label, each: ".", with: "_")
      let comment = comment |> option.map(string.trim)
      let opts = parse_opts(comment)
      Ok(Arg(num: arg_num, label: label, opts: [["_squirrel_sql_any"], ..opts]))
    }

    [Match(submatches: [Some(label), ..], ..), ..] -> {
      let label = string.replace(label, each: ".", with: "_")
      Ok(Arg(num: arg_num, label: label, opts: [["_squirrel_sql_any"]]))
    }

    [] -> Error("`parse_any_arg` No label match")

    _ ->  Error("`parse_any_arg` Multiple label matches")
  }
}

pub fn parse_kohort() -> Nil {
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

// pub type LabelledWrapperFunc {
//   LabelledWrapperFunc(
//     func: Func,
//     params:
//   )
// }

pub type LabelledParam {
  LabelledParam(
    name: String,
    label: String,
  )
}

pub fn labelled_params_for(func: Func) -> List(LabelledParam) {
  func.sql_args
  |> list.map(fn(arg) {
    let label = arg_label(arg)

    LabelledParam(
      name: "arg_" <> int.to_string(arg.num),
      label:,
    )
  })
  |> fn(params) {
    [LabelledParam(name: "db", label: "db"), ..params]
  }
}

fn get_label_override(
  arg: Arg,
) -> Option(String) {
  arg.opts
  |> list.filter_map(fn(strs) {
    case strs {
      [key, val] if key == "label" -> Ok(val)
      _ -> Error(Nil)
    }
  })
  |> list.last
  |> option.from_result
}

fn has_nullable_opt(
  arg: Arg,
) -> Bool {
  arg.opts
  |> list.any(fn(strs) {
    case strs {
      ["nullable"] -> True
      _ -> False
    }
  })
}

fn arg_label(arg: Arg) -> String {
  case get_label_override(arg) {
    None -> arg.label
    Some(override) -> override
  }
}

pub fn wrapper_func_src(func: Func, params: List(LabelledParam)) -> String {
  case list.any(func.sql_args, has_nullable_opt) {
    True -> adjust_squirrel_func_src(func.src, func.sql_args)
    False -> build_wrapper_func_src(func, params)
  }
}

pub fn build_wrapper_func_src(func: Func, params: List(LabelledParam)) -> String {
  let params =
    params
    |> list.map(fn(param) {
      "  " <> param.label <> " " <> param.name <> ","
    })

  let body =
    func.params
    |> string.join(", ")
    |> fn(ps) {
      "  sql." <> func.name <> "(" <> ps <> ")"
    }

  [
    ["pub fn " <> func.name <> "("],
    params,
    [") {"],
    [body],
    ["}"],
  ]
  |> list.flatten
  |> string.join("\n")
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
        case string.ends_with(name, "_encoder") {
          True -> Error(Nil)
          False -> {
            let params =
              params
              |> string.split(",")
              |> list.map(string.trim)

            let query = parse_query(src)
            let sql_args =
              case parse_args(query) {
                Error(err) -> {
                  io.debug(err)
                  io.debug(src)
                  panic as "`parse_args` failed"
                }

                Ok(x) -> x
              }

            Ok(Func(name:, src:, query:, params:, sql_args:))
          }
        }
      }

      _ -> {
        io.debug(src)
        panic as "Failed to parse func name from above source"
      }
    }
  })
  |> result.values
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
}

fn parse_query(src: String) -> String {
  // let assert Ok(query_start_re) = regexp.from_string("^\\s*let\\s*query\\s*=\\s*(\"(.*))?$")
  let assert Ok(query_start_re) =
    "^\\s*[\"]\\s*$"
    |> regexp.from_string

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

// TODO not `pub`
pub fn adjust_squirrel_func_src(
  src: String,
  args: List(Arg),
) -> String {
  let assert [params, ..rest] =
    src
    |> string.split(")")

  let params =
    params
    |> list.fold(args, _, fn(acc: String, arg) {
      let assert Ok(arg_re) =
        { "(arg_" <> int.to_string(arg.num) <> ")\\b" }
        |> regexp.from_string

      let label = arg_label(arg)

      regexp.replace(each: arg_re, in: acc, with: label <> " \\1")
    })

  let nullable_args =
    args
    |> list.filter(has_nullable_opt)
    |> list.map(fn(arg) { arg.num })
    |> set.from_list

  let rest =
    rest
    |> string.join(")")
    |> string.split("\n")
    |> list.map(fn(line) {
      line
      // |> io.debug
      |> make_parameter_nullable_on_line(nullable_args)
      |> qualify_sql_type_constructor
      |> qualify_sql_encoder_funcs
    })
    |> string.join("\n")

  [params, ..[ rest ]]
  |> string.join(")")
}

pub fn make_parameter_nullable_on_line(
  line: String,
  arg_nums: Set(Int),
) -> String {
  // "|> pog.parameter(pog.text(arg_1))"
  // "|> pog.parameter(pog.nullable(pog.text, arg_1))"

  arg_nums
  |> set.to_list
  |> list.find_map(fn(arg_num) {
    let arg_name = "arg_" <> int.to_string(arg_num)

    let assert Ok(re) =
      { "^(\\s+)[|][>]\\s*pog.parameter[(]pog.(\\w+)[(](uuid.to_string[(])?" <> arg_name <> "[)]?[)][)]\\s*$" }
      |> regexp.from_string

    case regexp.scan(re, line) {
      [Match(_, [Some(ws), Some(_func_name), Some(_uuid_to_string)])] ->
        // Ok(ws <> "|> pog.parameter(pog.nullable(pog." <> func_name <> ", uuid.to_string(" <> arg_name <> ")))")
        Ok(ws <> "|> pog.parameter(nullable_uuid(" <> arg_name <> "))")

      [Match(_, [Some(ws), Some(func_name), ..])] ->
        Ok(ws <> "|> pog.parameter(pog.nullable(pog." <> func_name <> ", " <> arg_name <> "))")

      _ ->
        Error(Nil)
    }
  })
  |> result.unwrap(line)
}

pub fn qualify_sql_type_constructor(
  line: String,
) -> String {
  line
  |> qualify_sql_type_in_decode_success_call
  |> qualify_sql_type_at_beginning_of_line
}

pub fn qualify_sql_type_in_decode_success_call(
  line: String,
) -> String {
  // "decode.success(GetSomeRow(id:))"
  // "decode.success(sql.GetSomeRow(id:))"

  let assert Ok(re) =
    { "^(\\s+)decode[.]success[(]\\n*\\s*([A-Z]\\w+)(.+)$" }
    |> regexp.from_string

  case regexp.scan(re, line) {
    [Match(_, [Some(ws), Some(type_name), Some(rest)])] ->
      ws <> "decode.success(sql." <> type_name <> rest

    _ ->
      line
  }
}

pub fn qualify_sql_type_at_beginning_of_line(
  line: String,
) -> String {
  let assert Ok(re) =
    { "^(\\s*)([A-Z]\\w+)([(].*)$" }
    |> regexp.from_string

  case regexp.scan(re, line) {
    [Match(_, [Some(ws), Some(type_name), Some(rest)])] ->
      ws <> "sql." <> type_name <> rest

    _ ->
      line
  }
}

fn qualify_sql_encoder_funcs(
  line: String,
) -> String {
  let assert Ok(re) =
    { "([a-z0-9_]\\w+[_]encoder[(])" }
    |> regexp.from_string

  regexp.replace(re, line, "sql.\\1")
}
