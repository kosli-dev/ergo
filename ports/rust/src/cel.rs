use crate::path::Ctx;
use crate::value::{Cause, worst_or_value};
use cel::common::ast::{Expr, IdedExpr};
use cel::objects::{Key, Map as CelMap};
use cel::{Context, ExecutionError, Program, Value as Cel};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::Arc;

pub struct Expression {
    program: Program,
    pub reads: Vec<Value>,
}

pub fn problem(source: &str, given: &[String]) -> Option<String> {
    let Ok(program) = Program::compile(source) else { return Some("invalid expr".into()) };
    let known = |n: &str| n == "self" || n == "params" || n == "input" || given.iter().any(|g| g == n);
    let mut free = vec![];
    free_names(program.expression(), &mut vec![], &mut free);
    let mut unknown: Vec<String> = free.into_iter().filter(|v| !known(v) && !TYPES.contains(&v.as_str())).collect();
    unknown.sort();
    unknown.first().map(|u| format!("unknown name {u}"))
}

pub fn reads(source: &str) -> Vec<Value> {
    Program::compile(source).map(|p| reads_of(&p)).unwrap_or_default()
}

pub fn compile(source: &str, given: &[String]) -> Result<Expression, String> {
    if let Some(p) = problem(source, given) {
        return Err(p);
    }
    let program = Program::compile(source).map_err(|_| "invalid expr".to_string())?;
    let reads = reads_of(&program);
    Ok(Expression { program, reads })
}

fn reads_of(program: &Program) -> Vec<Value> {
    let mut reads = vec![];
    collect(program.expression(), &mut vec![], &mut reads);
    reads.sort_by(|a, b| a.to_string().cmp(&b.to_string()));
    reads.dedup();
    let longest: Vec<Value> = reads
        .iter()
        .filter(|p| !reads.iter().any(|q| q != *p && starts_with(q, p)))
        .cloned()
        .collect();
    longest
}

fn starts_with(longer: &Value, prefix: &Value) -> bool {
    match (longer.as_array(), prefix.as_array()) {
        (Some(l), Some(p)) => l.len() > p.len() && l[..p.len()] == p[..],
        _ => false,
    }
}

const TYPES: [&str; 12] = ["bool", "bytes", "double", "duration", "dyn", "int", "list", "map", "null_type", "string", "timestamp", "uint"];

fn free_names(e: &IdedExpr, bound: &mut Vec<String>, out: &mut Vec<String>) {
    match &e.expr {
        Expr::Ident(name) if !bound.contains(name) => out.push(name.clone()),
        Expr::Select(s) => free_names(&s.operand, bound, out),
        Expr::Call(c) => {
            if let Some(t) = &c.target {
                free_names(t, bound, out);
            }
            c.args.iter().for_each(|a| free_names(a, bound, out));
        }
        Expr::List(l) => l.elements.iter().for_each(|a| free_names(a, bound, out)),
        Expr::Map(m) => {
            for entry in &m.entries {
                if let cel::common::ast::EntryExpr::MapEntry(me) = &entry.expr {
                    free_names(&me.key, bound, out);
                    free_names(&me.value, bound, out);
                }
            }
        }
        Expr::Comprehension(c) => {
            free_names(&c.iter_range, bound, out);
            let before = bound.len();
            bound.push(c.iter_var.clone());
            if let Some(v) = &c.iter_var2 {
                bound.push(v.clone());
            }
            bound.push(c.accu_var.clone());
            free_names(&c.accu_init, bound, out);
            free_names(&c.loop_cond, bound, out);
            free_names(&c.loop_step, bound, out);
            free_names(&c.result, bound, out);
            bound.truncate(before);
        }
        _ => {}
    }
}

fn root(name: &str) -> Option<Value> {
    match name {
        "self" => None,
        "params" => Some(json!("$$params")),
        "input" => Some(json!("$$input")),
        n => Some(json!(format!("${n}"))),
    }
}

fn chain(e: &IdedExpr, bound: &[String]) -> Option<Vec<Value>> {
    match &e.expr {
        Expr::Ident(name) if !bound.contains(name) && !TYPES.contains(&name.as_str()) => Some(root(name).into_iter().collect()),
        Expr::Select(s) => {
            let mut p = chain(&s.operand, bound)?;
            p.push(json!(s.field));
            Some(p)
        }
        _ => None,
    }
}

fn collect(e: &IdedExpr, bound: &mut Vec<String>, out: &mut Vec<Value>) {
    if let Some(p) = chain(e, bound) {
        out.push(Value::Array(p));
        return;
    }
    match &e.expr {
        Expr::Select(s) => collect(&s.operand, bound, out),
        Expr::Call(c) => {
            if let Some(t) = &c.target {
                collect(t, bound, out);
            }
            c.args.iter().for_each(|a| collect(a, bound, out));
        }
        Expr::List(l) => l.elements.iter().for_each(|a| collect(a, bound, out)),
        Expr::Map(m) => {
            for entry in &m.entries {
                if let cel::common::ast::EntryExpr::MapEntry(me) = &entry.expr {
                    collect(&me.key, bound, out);
                    collect(&me.value, bound, out);
                }
            }
        }
        Expr::Comprehension(c) => {
            collect(&c.iter_range, bound, out);
            let before = bound.len();
            bound.push(c.iter_var.clone());
            if let Some(v) = &c.iter_var2 {
                bound.push(v.clone());
            }
            bound.push(c.accu_var.clone());
            collect(&c.accu_init, bound, out);
            collect(&c.loop_cond, bound, out);
            collect(&c.loop_step, bound, out);
            collect(&c.result, bound, out);
            bound.truncate(before);
        }
        _ => {}
    }
}

fn to_cel(v: &Value) -> Cel {
    match v {
        Value::Null => Cel::Null,
        Value::Bool(b) => Cel::Bool(*b),
        Value::Number(n) => {
            let text = n.to_string();
            if text.bytes().all(|b| b.is_ascii_digit() || b == b'-') {
                match (text.parse::<i64>(), text.parse::<u64>()) {
                    (Ok(i), _) => Cel::Int(i),
                    (_, Ok(u)) => Cel::UInt(u),
                    _ => Cel::Float(n.as_f64().unwrap_or(f64::NAN)),
                }
            } else {
                Cel::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        Value::String(s) => Cel::String(Arc::new(s.clone())),
        Value::Array(a) => Cel::List(Arc::new(a.iter().map(to_cel).collect())),
        Value::Object(m) => {
            let map: HashMap<Key, Cel> = m.iter().map(|(k, x)| (Key::String(Arc::new(k.clone())), to_cel(x))).collect();
            Cel::Map(CelMap { map: Arc::new(map) })
        }
    }
}

fn sum(list: Arc<Vec<Cel>>) -> Result<Cel, ExecutionError> {
    let mut ints: i64 = 0;
    let mut floats: f64 = 0.0;
    let mut any_float = false;
    for v in list.iter() {
        match v {
            Cel::Int(i) => ints = ints.checked_add(*i).ok_or_else(|| ExecutionError::function_error("sum", "overflow"))?,
            Cel::UInt(u) => ints = ints.checked_add(*u as i64).ok_or_else(|| ExecutionError::function_error("sum", "overflow"))?,
            Cel::Float(f) => {
                floats += f;
                any_float = true;
            }
            other => return Err(ExecutionError::function_error("sum", format!("not a number: {other:?}"))),
        }
    }
    Ok(if any_float { Cel::Float(floats + ints as f64) } else { Cel::Int(ints) })
}

pub enum Outcome {
    True,
    False,
    Failed(Cause),
}

impl Expression {
    pub fn evaluate<'a>(&self, subject: &'a Value, ctx: &Ctx<'a>) -> Outcome {
        let mut context = Context::default();
        context.add_function("sum", sum).expect("ergo registers sum");
        context.add_variable_from_value("self", to_cel(subject));
        context.add_variable_from_value("params", to_cel(ctx.params));
        context.add_variable_from_value("input", to_cel(ctx.doc));
        for (name, value) in &ctx.names {
            context.add_variable_from_value(name.clone(), to_cel(value));
        }
        let states = self.reads.iter().filter_map(|p| crate::render::read_raw(ctx, subject, p).problem());
        match self.program.execute(&context) {
            Ok(Cel::Bool(true)) => Outcome::True,
            Ok(Cel::Bool(false)) => Outcome::False,
            Ok(_) => Outcome::Failed(Cause::Unusable),
            Err(ExecutionError::NoSuchKey(_)) => Outcome::Failed(match worst_or_value(states) {
                Cause::Value => Cause::Absent,
                c => c,
            }),
            Err(_) => Outcome::Failed(match worst_or_value(states) {
                Cause::Value => Cause::Unusable,
                c => c,
            }),
        }
    }

    pub fn cause<'a>(&self, subject: &'a Value, ctx: &Ctx<'a>) -> Cause {
        match self.evaluate(subject, ctx) {
            Outcome::True => Cause::Satisfied,
            Outcome::False => worst_or_value(self.reads.iter().filter_map(|p| crate::render::read_raw(ctx, subject, p).problem())),
            Outcome::Failed(c) => c,
        }
    }
}
