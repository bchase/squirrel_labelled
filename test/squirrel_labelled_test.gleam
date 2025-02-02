import gleam/io
import gleam/string
import gleeunit
import gleeunit/should
import squirrel_labelled as sl

pub fn main() {
  gleeunit.main()
}

pub fn read_test() {
  sl.foo()

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

  let args = sl.parse(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "org_id"),
    sl.Arg(num: 2, label: "id"),
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

  let args = sl.parse(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "id"),
    sl.Arg(num: 2, label: "user_id"),
    sl.Arg(num: 3, label: "foo"),
    sl.Arg(num: 4, label: "bar"),
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

  let args = sl.parse(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "w_org_id"),
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

  let args = sl.parse(sql)

  args
  |> should.equal(Ok([]))
}

pub fn insert_test() {
  let sql = "
    INSERT INTO
      widgets
      (
        foo,
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

  let args = sl.parse(sql)

  args
  |> should.equal(Ok([
    sl.Arg(num: 1, label: "foo"),
    sl.Arg(num: 2, label: "baz"),
    sl.Arg(num: 3, label: "bar"),
  ]))
}


pub fn squirrel_src_parse_test() {
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

  let query = \"
    INSERT INTO
      users
      (
        name,
        email,
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

  pog.query(query)
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

  let query = \"
    SELECT
      user_id
    FROM
      user_tokens
    WHERE hashed_token = $1
    LIMIT 1
\"

  pog.query(query)
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
"
  |> string.trim

  True |> should.equal(True)
}
