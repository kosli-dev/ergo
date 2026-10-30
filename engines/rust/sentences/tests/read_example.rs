#[path = "../examples/read.rs"]
mod read;

use serde_json::{Value, json};

fn kinds() -> Value {
    json!(["check", "for-line", "from-line"])
}

#[test]
fn a_row_gets_one_answer_per_kind_in_order() {
    let rows = json!({"rows": [{"kinds": kinds(), "text": "x is 1"}]});
    let read = read::read_rows(&rows);
    assert_eq!(
        read,
        json!([[
            {"kind": "check", "syntax": [], "problems": []},
            {"kind": "for-line", "syntax": [r#"an item starts with "every", "some" or a position, like "last of""#], "problems": [r#"an item starts with "every", "some" or a position, like "last of""#]},
            {"kind": "from-line", "syntax": ["doesn't parse"], "problems": ["doesn't parse"]}
        ]])
    );
}

#[test]
fn a_sentence_that_reads_but_is_written_wrong_has_no_syntax_errors_and_lists_its_problems() {
    let rows = json!({"rows": [{"kinds": ["check"], "text": "x is not null"}]});
    assert_eq!(
        read::read_rows(&rows),
        json!([[{"kind": "check", "syntax": [], "problems": [r#""is not null" is written "exists""#]}]])
    );
}

#[test]
fn each_kind_uses_its_own_reader() {
    let rows = json!({"rows": [
        {"kinds": ["check"], "text": "every xs as x"},
        {"kinds": ["for-line"], "text": "every xs as x"},
        {"kinds": ["from-line"], "text": "xs whose y is 1"}
    ]});
    let read = read::read_rows(&rows);
    assert_eq!(read[0][0]["problems"].as_array().unwrap().len(), 1);
    assert_eq!(read[1][0]["problems"], json!([]));
    assert_eq!(read[2][0]["problems"], json!([]));
}

#[test]
fn an_error_gives_every_message_of_the_reader() {
    let rows = json!({"rows": [{"kinds": ["check"], "text": "empty is \"a"}]});
    let read = read::read_rows(&rows);
    assert_eq!(
        read[0][0]["problems"],
        json!(["unclosed quote at column 10"])
    );
}

#[test]
fn rows_come_back_in_the_order_they_went_in() {
    let rows = json!({"rows": [
        {"kinds": ["check"], "text": "x is 1"},
        {"kinds": ["check"], "text": "x is"},
        {"kinds": ["check"], "text": "y exists"}
    ]});
    let read = read::read_rows(&rows);
    let empties: Vec<bool> = read
        .as_array()
        .unwrap()
        .iter()
        .map(|row| row[0]["problems"].as_array().unwrap().is_empty())
        .collect();
    assert_eq!(empties, vec![true, false, true]);
}

#[test]
fn an_unknown_kind_is_a_problem_not_a_crash() {
    let rows = json!({"rows": [{"kinds": ["other"], "text": "x is 1"}]});
    let read = read::read_rows(&rows);
    assert_eq!(read[0][0]["problems"], json!(["unknown kind other"]));
}

#[test]
fn no_rows_is_an_empty_answer() {
    assert_eq!(read::read_rows(&json!({"rows": []})), json!([]));
    assert_eq!(read::read_rows(&json!({})), json!([]));
}

#[test]
fn text_with_characters_outside_ascii_is_read() {
    let rows = json!({"rows": [{"kinds": ["check"], "text": "\"é日😀\" is 1"}]});
    let read = read::read_rows(&rows);
    assert_eq!(read[0][0]["problems"], json!([]));
}
