import gleam/io
import gleam/string
import gleeunit
import gleeunit/should
import squirrel_labelled as sl

pub fn main() {
  gleeunit.main()
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

// pub fn insert_test() {
//   let sql = "
//     INSERT INTO
//       users
//       (
//         name,
//         email,
//         org_id
//       )
//     VALUES
//       (
//         $1,
//         $2,
//         $3
//       )
//     RETURNING
//       id,
//       name,
//       email,
//       org_id
// "

//   1
//   |> should.equal(1)
// }
