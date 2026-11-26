use serde_json::json;

fn policy() -> serde_json::Value {
    json!({
        "subjects": {
            "pull request": {"from": "prs", "identified_by": "number"},
            "commit": {"from": "every \"pull request\".commits", "identified_by": "sha"},
            "file": {"from": "every commit.files", "identified_by": "path"},
            "big file": {"from": "file whose size is at least 10"},
            "flat": {"from": "every prs.commits"}
        }
    })
}

#[test]
fn the_ancestors_of_a_subject_are_the_subjects_its_rows_name_under_in_parent_first() {
    let ancestors = |subject: &str| ergo_policy_engine::ancestors(&policy(), subject);
    assert_eq!(ancestors("file"), vec!["commit", "pull request"]);
    assert_eq!(ancestors("commit"), vec!["pull request"]);
    assert_eq!(ancestors("big file"), vec!["commit", "pull request"]);
    assert_eq!(ancestors("pull request"), Vec::<String>::new());
    assert_eq!(ancestors("flat"), Vec::<String>::new());
    assert_eq!(ancestors("nobody"), Vec::<String>::new());
}

#[test]
fn the_ancestors_follow_the_in_of_the_rows_of_the_report() {
    let mut policy = policy();
    policy["ergo_spec"] = json!(ergo_policy_engine::SPEC);
    policy["requirements"] = json!({"r": {"subject": "big file", "checks": {"c": "size exists"}}});
    let input = json!({"prs": [{"number": 7, "commits": [{"sha": "a1", "files": [{"path": "x", "size": 20}]}]}]});
    let report = ergo_policy_engine::report(&input, &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    assert_eq!(
        row["subject"]["in"],
        json!({"commit": "a1", "pull request": 7})
    );
    let parents = ergo_policy_engine::ancestors(&policy, "big file");
    let keys: Vec<&String> = row["subject"]["in"].as_object().unwrap().keys().collect();
    assert_eq!(keys.len(), parents.len());
    assert!(parents.iter().all(|p| keys.contains(&p)));
}
