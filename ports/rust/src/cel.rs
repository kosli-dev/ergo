use cel::common::ast::{EntryExpr, Expr, IdedExpr};
use cel::objects::{Key, Map as CelMap};
use cel::{Context, ExecutionError, Program, Value as Cel};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;

const TYPES: [&str; 12] = ["bool", "bytes", "double", "duration", "dyn", "int", "list", "map", "null_type", "string", "timestamp", "uint"];

pub struct Body {
    program: Program,
}

pub enum Verdict {
    True,
    False,
    Failed,
}

pub fn compile(source: &str, params: &[String]) -> Result<Body, String> {
    let program = Program::compile(source).map_err(|e| format!("its passes isn't valid CEL: {e}"))?;
    let mut free = vec![];
    free_names(program.expression(), &mut vec![], &mut free);
    free.sort();
    free.dedup();
    if let Some(unknown) = free.into_iter().find(|n| !params.contains(n) && !TYPES.contains(&n.as_str())) {
        return Err(format!("its passes reads {unknown}, which isn't one of its params"));
    }
    Ok(Body { program })
}

fn free_names(e: &IdedExpr, bound: &mut Vec<String>, out: &mut Vec<String>) {
    match &e.expr {
        Expr::Ident(name) if !bound.contains(name) => out.push(name.clone()),
        Expr::Select(s) => free_names(&s.operand, bound, out),
        Expr::Call(c) => {
            match c.target.as_deref().map(|t| &t.expr) {
                Some(Expr::Ident(ns)) if ns == "ergo" => {}
                _ => {
                    if let Some(t) = &c.target {
                        free_names(t, bound, out);
                    }
                }
            }
            c.args.iter().for_each(|a| free_names(a, bound, out));
        }
        Expr::List(l) => l.elements.iter().for_each(|a| free_names(a, bound, out)),
        Expr::Map(m) => {
            for entry in &m.entries {
                if let EntryExpr::MapEntry(me) = &entry.expr {
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

fn to_cel(v: &Value) -> Cel {
    match v {
        Value::Null => Cel::Null,
        Value::Bool(b) => Cel::Bool(*b),
        Value::Number(n) => {
            let text = n.to_string();
            let whole = text.bytes().all(|b| b.is_ascii_digit() || b == b'-');
            match (whole, text.parse::<i64>(), text.parse::<u64>()) {
                (true, Ok(i), _) => Cel::Int(i),
                (true, _, Ok(u)) => Cel::UInt(u),
                _ => Cel::Float(n.as_f64().unwrap_or(f64::NAN)),
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
    let mut whole: i64 = 0;
    let mut fraction: f64 = 0.0;
    let mut any_double = false;
    for v in list.iter() {
        match v {
            Cel::Int(i) => whole = whole.checked_add(*i).ok_or_else(|| ExecutionError::function_error("ergo.sum", "overflow"))?,
            Cel::UInt(u) => {
                let i = i64::try_from(*u).map_err(|_| ExecutionError::function_error("ergo.sum", "overflow"))?;
                whole = whole.checked_add(i).ok_or_else(|| ExecutionError::function_error("ergo.sum", "overflow"))?
            }
            Cel::Float(f) => {
                fraction += f;
                any_double = true;
            }
            _ => return Err(ExecutionError::function_error("ergo.sum", "not a number")),
        }
    }
    Ok(if any_double { Cel::Float(fraction + whole as f64) } else { Cel::Int(whole) })
}

impl Body {
    pub fn run(&self, args: &[(String, Value)]) -> Verdict {
        let mut context = Context::default();
        if context.add_function("ergo.sum", sum).is_err() {
            return Verdict::Failed;
        }
        for (name, value) in args {
            context.add_variable_from_value(name.clone(), to_cel(value));
        }
        match self.program.execute(&context) {
            Ok(Cel::Bool(true)) => Verdict::True,
            Ok(Cel::Bool(false)) => Verdict::False,
            _ => Verdict::Failed,
        }
    }
}
