import gleam/io
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import squirrel_labelled as sl

pub fn main() {
  gleeunit.main()
}

pub fn read_test() {
  // sl.parse_kohort()

  True |> should.equal(True)
}

pub fn delete_test() {
  let sql = "
    DELETE FROM
      widgets
    WHERE id = $2
      AND org_id = $1
"
  |> string.trim

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "org_id", opts: []),
    sl.Arg(num: 2, label: "id", opts: []),
  ]))
}

pub fn update_test() {
  let sql = "
    UPDATE
      widgets
    SET
      foo = $3,
      bar = $4
    WHERE id = $1
      AND user_id = $2
    RETURNING
      id,
      foo,
      bar
"
  |> string.trim

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "id", opts: []),
    sl.Arg(num: 2, label: "user_id", opts: []),
    sl.Arg(num: 3, label: "foo", opts: []),
    sl.Arg(num: 4, label: "bar", opts: []),
  ]))
}

pub fn select_test() {
  let sql = "
    SELECT
      w.id,
      w.org_id,
      w.foo,
      w.bar
    FROM
      widgets as w
    JOIN orgs as o ON w.org_id = o.id
    WHERE w.org_id = $1
"
  |> string.trim

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "w_org_id", opts: []),
  ]))
}

pub fn select_no_args_test() {
  let sql = "
    SELECT
      w.id,
      w.foo,
      w.bar
    FROM
      widgets as w
"
  |> string.trim

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([]))
}

pub fn insert_test() {
  let sql = "
    INSERT INTO
      widgets
      (
        foo, -- foo
        bar,
        baz
      )
    VALUES
      (
        $1,
        $3,
        $2
      )
    RETURNING
      id,
      foo,
      bar,
      baz
"

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "foo", opts: []),
    sl.Arg(num: 2, label: "baz", opts: []),
    sl.Arg(num: 3, label: "bar", opts: []),
  ]))
}

pub fn insert_label_override_test() {
  let sql = "
    INSERT INTO
      widgets
      (
        foo,
        bar, --$ squirrel label foobar
        baz  --$ squirrel label hoge
      )
    VALUES
      (
        $1,
        $3,
        $2
      )
    RETURNING
      id,
      foo,
      bar,
      baz
"

  let args = sl.parse_args(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "foo", opts: []),
    sl.Arg(num: 2, label: "baz", opts: [["label", "hoge"]]),
    sl.Arg(num: 3, label: "bar", opts: [["label", "foobar"]]),
  ]))
}

pub fn squirrel_parse_and_labelled_func_gen_test() {
  let src = "
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import pog
import youid/uuid.{type Uuid}

/// A row you get from running the `insert_user` query
/// defined in `./src/kohort/sql/insert_user.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertUserRow {
  InsertUserRow(id: Uuid, name: String, email: String, org_id: Uuid)
}

/// Runs the `insert_user` query
/// defined in `./src/kohort/sql/insert_user.sql`.
///
/// > 🐿️ This function was generated automatically using v3.0.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_user(db, arg_1, arg_2, arg_3) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    use email <- decode.field(2, decode.string)
    use org_id <- decode.field(3, uuid_decoder())
    decode.success(InsertUserRow(id:, name:, email:, org_id:))
  }

  \"
    INSERT INTO
      users
      (
        name,
        email, --$ squirrel label skip, squirrel label email_address
        org_id
      )
    VALUES
      (
        $1,
        $2,
        $3
      )
    RETURNING
      id,
      name,
      email,
      org_id
\"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(uuid.to_string(arg_3)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_user_token` query
/// defined in `./src/kohort/sql/get_user_token.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetUserTokenRow {
  GetUserTokenRow(user_id: Uuid)
}

/// Runs the `get_user_token` query
/// defined in `./src/kohort/sql/get_user_token.sql`.
///
/// > 🐿️ This function was generated automatically using v3.0.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_user_token(db, arg_1) {
  let decoder = {
    use user_id <- decode.field(0, uuid_decoder())
    decode.success(GetUserTokenRow(user_id:))
  }

  \"
    SELECT
      user_id
    FROM
      user_tokens
    WHERE hashed_token = $1
    LIMIT 1
\"
  |> pog.query(query)
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
"
  |> string.trim

  let assert [func1, func2] as funcs = sl.parse_func_srcs(src)

  func1.name |> should.equal("get_user_token")
  func1.params |> should.equal(["db", "arg_1"])
  func1.sql_args |> should.equal([
    sl.Arg(num: 1, label: "hashed_token", opts: []),
  ])

  func2.name |> should.equal("insert_user")
  func2.params |> should.equal(["db", "arg_1", "arg_2", "arg_3"])
  func2.sql_args |> should.equal([
    sl.Arg(num: 1, label: "name", opts: []),
    sl.Arg(num: 2, label: "email", opts: [["label", "skip"], ["label", "email_address"]]),
    sl.Arg(num: 3, label: "org_id", opts: []),
  ])

  let assert [_, p2] =
    funcs
    |> list.map(sl.labelled_params_for)

  should.equal(p2, [
    sl.LabelledParam(name: "db", label: "db"),
    sl.LabelledParam(name: "arg_1", label: "name"),
    sl.LabelledParam(name: "arg_2", label: "email_address"),
    sl.LabelledParam(name: "arg_3", label: "org_id"),
  ])

  let expected_wrapper_func_src = "
pub fn insert_user(
  db db,
  name arg_1,
  email_address arg_2,
  org_id arg_3,
) {
  sql.insert_user(db, arg_1, arg_2, arg_3)
}
"
  |> string.trim

  sl.wrapper_func_src(func2, p2)
  |> should.equal(expected_wrapper_func_src)
}

pub fn squirrel_copy_and_nullify_test() {
  let src = "
pub fn insert_user(db, arg_1, arg_2, arg_3) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    use email <- decode.field(2, decode.string)
    use org_id <- decode.field(3, uuid_decoder())
    use some_enum <- decode.field(4, uuid_decoder())
    decode.success(InsertUserRow(id:, name:, email:, org_id:, some_enum:))
  }

  \"
    INSERT INTO
      users
      (
        name,   --$ squirrel nullable
        email,  --$ squirrel label skip, squirrel label email_address
        org_id, --$ squirrel nullable
        some_enum
      )
    VALUES
      (
        $1,
        $2,
        $3,
        $4
      )
    RETURNING
      id,
      name,
      email,
      org_id,
      some_enum
\"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(uuid.to_string(arg_3)))
  |> pog.parameter(some_enum_encoder(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
"

  let assert [func] = sl.parse_func_srcs(src)

  let expected = "
pub fn insert_user(db, name arg_1, email_address arg_2, org_id arg_3) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    use email <- decode.field(2, decode.string)
    use org_id <- decode.field(3, uuid_decoder())
    use some_enum <- decode.field(4, uuid_decoder())
    decode.success(sql.InsertUserRow(id:, name:, email:, org_id:, some_enum:))
  }

  \"
    INSERT INTO
      users
      (
        name,   --$ squirrel nullable
        email,  --$ squirrel label skip, squirrel label email_address
        org_id, --$ squirrel nullable
        some_enum
      )
    VALUES
      (
        $1,
        $2,
        $3,
        $4
      )
    RETURNING
      id,
      name,
      email,
      org_id,
      some_enum
\"
  |> pog.query
  |> pog.parameter(pog.nullable(pog.text, arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(nullable_uuid(arg_3))
  |> pog.parameter(sql.some_enum_encoder(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
"

  src
  |> string.trim
  |> sl.adjust_squirrel_func_src(func.sql_args)
  // |> sl.adjust_squirrel_func_src([
  //   sl.Arg(num: 1, label: "name", opts: [["nullable"]]),
  //   sl.Arg(num: 2, label: "email", opts: [["label", "email_address"]]),
  //   sl.Arg(num: 3, label: "org_id", opts: [["nullable"]]),
  // ])
  |> should.equal(expected |> string.trim)
}

pub fn non_colum_args_test() {
  let query = string.trim("
    SELECT
      id,
    FROM
      hoges
    WHERE
      org_id = $1
    ORDER BY $2
    LIMIT $3
    OFFSET $4
  ")

  sl.parse_args(query)
  |> should.be_ok
  |> should.equal( [
    sl.Arg(1, "org_id", []),
    sl.Arg(2, "order_by", [["_squirrel_sql_keyword"]]),
    sl.Arg(3, "limit", [["_squirrel_sql_keyword"]]),
    sl.Arg(4, "offset", [["_squirrel_sql_keyword"]]),
  ])

  //
  //

  let query = string.trim("
    SELECT
      id,
    FROM
      hoges
    WHERE
      org_id = $1
      limit = $2
    LIMIT $3
  ")

  sl.parse_args(query)
  |> should.be_ok
  |> should.equal([
    sl.Arg(1, "org_id", []),
    sl.Arg(2, "limit", []),
    sl.Arg(3, "limit_", [["_squirrel_sql_keyword"]]),
  ])
}

pub fn any_args_test() {
  let query = string.trim("
    SELECT
      id,
    FROM
      hoges
    WHERE
      id = ANY($1)
    ORDER BY $2
    LIMIT $3
    OFFSET $4
  ")

  sl.parse_args(query)
  |> should.be_ok
  |> should.equal( [
    sl.Arg(1, "id", [["_squirrel_sql_any"]]),
    sl.Arg(2, "order_by", [["_squirrel_sql_keyword"]]),
    sl.Arg(3, "limit", [["_squirrel_sql_keyword"]]),
    sl.Arg(4, "offset", [["_squirrel_sql_keyword"]]),
  ])
}

pub fn gleam_keywords_test() {
  let query = string.trim("
    SELECT
      id,
    FROM
      hoges
    WHERE org_id = $1
      AND type = $2 --$ squirrel nullable
  ")

  sl.parse_args(query)
  |> should.be_ok
  |> should.equal( [
    sl.Arg(1, "org_id", []),
    sl.Arg(2, "type_", [ ["nullable"], ["_squirrel_gleam_keyword"] ]),
  ])
}

pub fn upsert_table_alias_test() {
  let query = string.trim("
    INSERT INTO
      hubspot_companies as hsc
      (
        org_id,
        ext_id,
        ext_created_at,
        ext_updated_at,
        name --$ squirrel nullable
      )
    VALUES ( $1, $2, $3, $4, $5 )
    ON CONFLICT (ext_id)
    DO UPDATE SET
      ext_updated_at = $4
    WHERE hsc.org_id = $1
    RETURNING
      id,
      name,
      ext_id
  ")

  sl.parse_args(query)
  |> should.be_ok
}
