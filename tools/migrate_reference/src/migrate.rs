//! Terraform → PetCow migration (Phase 6 / FR-10).
//!
//! Parses HCL (`.tf`) and translates `resource` blocks of supported types into a
//! PetCow YAML document. Terraform references like `aws_vpc.main.id` become
//! `${resources.main.id}`. Anything that can't be translated faithfully (unknown
//! resource types, variables/modules/data sources, nested blocks, complex
//! expressions) is **reported as a warning rather than silently dropped**
//! (FR-12).

use crate::error::{PetcowError, Result};
use hcl::expr::{Expression, ObjectKey, TraversalOperator};
use hcl::structure::{BlockLabel, Structure};
use hcl::template::{Element, Template};
use serde_yaml::{Mapping, Value};
use std::collections::BTreeMap;

/// The outcome of a migration.
pub struct Migration {
    /// The generated PetCow YAML.
    pub yaml: String,
    /// Number of resources translated.
    pub migrated: usize,
    /// Things that couldn't be translated faithfully.
    pub warnings: Vec<String>,
}

/// Map a Terraform resource type to a PetCow type. `None` → unsupported.
fn map_type(tf_type: &str) -> Option<&'static str> {
    Some(match tf_type {
        "aws_s3_bucket" => "aws.s3",
        "aws_vpc" => "aws.vpc",
        "aws_subnet" => "aws.subnet",
        "aws_internet_gateway" => "aws.internet_gateway",
        "aws_route_table" => "aws.route_table",
        "aws_security_group" => "aws.security_group",
        "aws_instance" => "aws.ec2_instance",
        "aws_eip" => "aws.elastic_ip",
        "aws_ebs_volume" => "aws.ebs_volume",
        "aws_iam_role" => "aws.iam_role",
        _ => return None,
    })
}

/// Sections accumulated while translating an HCL body.
#[derive(Default)]
struct Sections {
    variables: Mapping,
    locals: Mapping,
    data: Mapping,
    outputs: Mapping,
    providers: Mapping,
    modules: Mapping,
    resources: Mapping,
    protected: Vec<Value>,
}

/// Translate HCL source into a PetCow document.
pub fn migrate_hcl(src: &str, project: &str) -> Result<Migration> {
    let body = hcl::parse(src).map_err(|e| PetcowError::document(format!("parsing HCL: {e}")))?;
    let mut sec = Sections::default();
    let mut warnings = Vec::new();
    let mut migrated = 0;

    for structure in body {
        match structure {
            Structure::Attribute(a) => {
                warnings.push(format!("skipped top-level attribute '{}'", a.key.as_str()));
            }
            Structure::Block(b) => match b.identifier.as_str() {
                "resource" => {
                    if migrate_resource(&b, &mut sec, &mut warnings) {
                        migrated += 1;
                    }
                }
                "variable" => migrate_variable(&b, &mut sec, &mut warnings),
                "locals" => migrate_locals(&b, &mut sec, &mut warnings),
                "data" => {
                    if migrate_data(&b, &mut sec, &mut warnings) {
                        migrated += 1;
                    }
                }
                "output" => migrate_output(&b, &mut sec, &mut warnings),
                "provider" => migrate_provider(&b, &mut sec, &mut warnings),
                "module" => migrate_module(&b, &mut sec, &mut warnings),
                other => warnings.push(format!("skipped unsupported block '{other}'")),
            },
        }
    }

    let mut doc = Mapping::new();
    doc.insert(
        Value::String("project".into()),
        Value::String(project.to_string()),
    );
    let mut put = |k: &str, m: Mapping| {
        if !m.is_empty() {
            doc.insert(Value::String(k.into()), Value::Mapping(m));
        }
    };
    put("variables", sec.variables);
    put("locals", sec.locals);
    put("data", sec.data);
    put("outputs", sec.outputs);
    put("providers", sec.providers);
    put("modules", sec.modules);
    if !sec.protected.is_empty() {
        doc.insert(
            Value::String("protected".into()),
            Value::Sequence(sec.protected),
        );
    }
    doc.insert(
        Value::String("resources".into()),
        Value::Mapping(sec.resources),
    );
    let yaml = serde_yaml::to_string(&Value::Mapping(doc))
        .map_err(|e| PetcowError::document(format!("serializing: {e}")))?;

    Ok(Migration {
        yaml,
        migrated,
        warnings,
    })
}

/// Translate one `resource` block; returns true if migrated.
fn migrate_resource(
    b: &hcl::structure::Block,
    sec: &mut Sections,
    warnings: &mut Vec<String>,
) -> bool {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    if labels.len() != 2 {
        warnings.push("skipped malformed resource block (expected type + name)".into());
        return false;
    }
    let (tf_type, name) = (&labels[0], &labels[1]);
    let Some(petcow_type) = map_type(tf_type) else {
        warnings.push(format!(
            "resource '{tf_type}.{name}': type not supported, skipped"
        ));
        return false;
    };

    let mut body_map = Mapping::new();
    body_map.insert(
        Value::String("type".into()),
        Value::String(petcow_type.into()),
    );
    for s in &b.body {
        match s {
            Structure::Attribute(a) => {
                let key = a.key.as_str();
                let ctx = format!("{tf_type}.{name}.{key}");
                match key {
                    // Meta-arguments translate directly.
                    "count" | "for_each" => {
                        if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                            body_map.insert(Value::String(key.into()), v);
                        }
                    }
                    "depends_on" => {
                        if let Some(v) = depends_on_to_value(&a.expr, &ctx, warnings) {
                            body_map.insert(Value::String("depends_on".into()), v);
                        }
                    }
                    "provider" => warnings.push(format!(
                        "{ctx}: TF 'provider' meta-arg not auto-translated — declare a providers: alias and set provider:"
                    )),
                    _ => {
                        if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                            body_map.insert(Value::String(key.into()), v);
                        }
                    }
                }
            }
            Structure::Block(nb) if nb.identifier.as_str() == "lifecycle" => {
                migrate_lifecycle(nb, name, &mut body_map, sec, warnings);
            }
            Structure::Block(nb) if nb.identifier.as_str() == "dynamic" => {
                if let Some((attr, value)) = migrate_dynamic(nb, name, warnings) {
                    body_map.insert(Value::String(attr), value);
                }
            }
            Structure::Block(nb) => {
                warnings.push(format!(
                    "resource '{tf_type}.{name}': nested block '{}' not translated (declare it as a list attribute in PetCow)",
                    nb.identifier.as_str()
                ));
            }
        }
    }
    sec.resources
        .insert(Value::String(name.clone()), Value::Mapping(body_map));
    true
}

/// Translate a `variable` block into a `variables:` entry.
fn migrate_variable(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    let Some(name) = labels.first() else {
        warnings.push("skipped variable block without a name".into());
        return;
    };
    let mut decl = Mapping::new();
    for s in &b.body {
        match s {
            Structure::Attribute(a) => {
                let key = a.key.as_str();
                let ctx = format!("variable {name}.{key}");
                match key {
                    "type" => {
                        decl.insert(Value::String("type".into()), Value::String(tf_type_to_vartype(&a.expr)));
                    }
                    "default" => {
                        if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                            decl.insert(Value::String("default".into()), v);
                        }
                    }
                    "description" => {
                        if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                            decl.insert(Value::String("description".into()), v);
                        }
                    }
                    "sensitive" => {
                        if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                            decl.insert(Value::String("sensitive".into()), v);
                        }
                    }
                    other => warnings.push(format!("variable '{name}': attribute '{other}' not translated")),
                }
            }
            Structure::Block(nb) => warnings.push(format!(
                "variable '{name}': '{}' block not translated (PetCow validation uses ${{...}} conditions)",
                nb.identifier.as_str()
            )),
        }
    }
    sec.variables
        .insert(Value::String(name.clone()), Value::Mapping(decl));
}

/// Translate a `locals` block into `locals:` entries.
fn migrate_locals(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) {
    for s in &b.body {
        match s {
            Structure::Attribute(a) => {
                let key = a.key.as_str();
                let ctx = format!("local.{key}");
                if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                    sec.locals.insert(Value::String(key.into()), v);
                }
            }
            Structure::Block(nb) => warnings.push(format!(
                "locals: nested block '{}' skipped",
                nb.identifier.as_str()
            )),
        }
    }
}

/// Translate an `output "name" { value = … }` block into an `outputs:` entry.
/// PetCow auto-derives output sensitivity from value taint, so `sensitive` is
/// dropped with a note; `description` has no PetCow field.
fn migrate_output(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    if labels.len() != 1 {
        warnings.push("skipped malformed output block (expected a name)".into());
        return;
    }
    let name = &labels[0];
    let ctx = format!("output.{name}");
    let mut value = None;
    for s in &b.body {
        match s {
            Structure::Attribute(a) => match a.key.as_str() {
                "value" => value = expr_to_value(&a.expr, &ctx, warnings),
                "sensitive" => warnings.push(format!(
                    "output '{name}': `sensitive` dropped — PetCow auto-derives output sensitivity from value taint"
                )),
                "description" | "depends_on" => {}
                other => warnings.push(format!("output '{name}': attribute '{other}' skipped")),
            },
            Structure::Block(nb) => warnings.push(format!(
                "output '{name}': nested block '{}' skipped",
                nb.identifier.as_str()
            )),
        }
    }
    match value {
        Some(v) => {
            sec.outputs.insert(Value::String(name.clone()), v);
        }
        None => warnings.push(format!("output '{name}': no `value` attribute — skipped")),
    }
}

/// Translate a `provider "<name>" { alias = …, region = …, profile = … }` block
/// into a `providers:` alias. Only **aliased** providers map (PetCow's
/// `providers:` section is alias-only; the default provider's region/credentials
/// come from the environment/CLI, so a no-alias block is reported, not invented).
fn migrate_provider(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    if labels.len() != 1 {
        warnings.push("skipped malformed provider block (expected a name)".into());
        return;
    }
    let tf_name = &labels[0];
    let cloud = match tf_name.as_str() {
        "aws" => "aws",
        "google" => "gcp",
        "azurerm" => "azure",
        other => {
            warnings.push(format!(
                "provider '{other}': no PetCow cloud mapping — skipped"
            ));
            return;
        }
    };
    let ctx = format!("provider.{tf_name}");
    let str_attr = |expr: &Expression, warnings: &mut Vec<String>| {
        expr_to_value(expr, &ctx, warnings).and_then(|v| match v {
            Value::String(s) => Some(s),
            _ => None,
        })
    };
    let (mut alias, mut region, mut profile) = (None, None, None);
    for s in &b.body {
        if let Structure::Attribute(a) = s {
            match a.key.as_str() {
                "alias" => alias = str_attr(&a.expr, warnings),
                "region" => region = str_attr(&a.expr, warnings),
                "profile" => profile = str_attr(&a.expr, warnings),
                other => {
                    warnings.push(format!("provider '{tf_name}': attribute '{other}' skipped"))
                }
            }
        }
    }
    let Some(alias) = alias else {
        warnings.push(format!(
            "provider '{tf_name}': default (no `alias`) — PetCow takes the default region/credentials from the environment; only aliased providers map to `providers:`"
        ));
        return;
    };
    let mut cfg = Mapping::new();
    cfg.insert(Value::String("cloud".into()), Value::String(cloud.into()));
    if let Some(r) = region {
        cfg.insert(Value::String("region".into()), Value::String(r));
    }
    if let Some(p) = profile {
        cfg.insert(Value::String("profile".into()), Value::String(p));
    }
    sec.providers
        .insert(Value::String(alias), Value::Mapping(cfg));
}

/// Translate a `module "name" { source = …, <inputs> }` block into a `modules:`
/// entry. **Source impedance (FR-12):** HCL `source` points at a directory of
/// `.tf` files, while a PetCow module is a single `.petcow.yaml`. Local **and
/// git** sources carry over (PetCow supports git sources since v0.175.0 — warned
/// to point the `//<path>` at the migrated `.petcow.yaml`); Terraform **registry**
/// shorthands (`namespace/name/provider`) have no PetCow equivalent and are flagged.
fn migrate_module(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    if labels.len() != 1 {
        warnings.push("skipped malformed module block (expected a name)".into());
        return;
    }
    let name = &labels[0];
    let ctx = format!("module.{name}");
    let mut entry = Mapping::new();
    let mut inputs = Mapping::new();
    let mut source = None;
    for s in &b.body {
        match s {
            Structure::Attribute(a) => match a.key.as_str() {
                "source" => {
                    source = expr_to_value(&a.expr, &ctx, warnings).and_then(|v| match v {
                        Value::String(s) => Some(s),
                        _ => None,
                    });
                }
                "version" => warnings.push(format!(
                    "module '{name}': `version` dropped — PetCow modules are local files, not registry-versioned"
                )),
                "count" => {
                    if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                        entry.insert(Value::String("count".into()), v);
                    }
                }
                "for_each" => {
                    if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                        entry.insert(Value::String("for_each".into()), v);
                    }
                }
                "providers" | "depends_on" => warnings.push(format!(
                    "module '{name}': `{}` skipped",
                    a.key.as_str()
                )),
                other => {
                    if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                        inputs.insert(Value::String(other.into()), v);
                    }
                }
            },
            Structure::Block(nb) => warnings.push(format!(
                "module '{name}': nested block '{}' skipped",
                nb.identifier.as_str()
            )),
        }
    }
    match source {
        Some(src) => match crate::modulesrc::parse(&src) {
            // Git sources are supported by PetCow (v0.175.0) — carry them over,
            // but a TF git module is a *directory of .tf*, so the `//<path>` must
            // point at the migrated `.petcow.yaml`.
            crate::modulesrc::ModuleSource::Git { .. } => {
                warnings.push(format!(
                    "module '{name}': git source '{src}' carried over — point its `//<path>` at the migrated `.petcow.yaml` (a Terraform module is a dir of .tf)"
                ));
                entry.insert(Value::String("source".into()), Value::String(src));
            }
            // A local relative/absolute path carries over (migrate the target).
            crate::modulesrc::ModuleSource::Local(_)
                if src.starts_with("./") || src.starts_with("../") || src.starts_with('/') =>
            {
                warnings.push(format!(
                    "module '{name}': source '{src}' points at Terraform files — migrate that module to a `.petcow.yaml` and update the path"
                ));
                entry.insert(Value::String("source".into()), Value::String(src));
            }
            // A bare `namespace/name/provider` is a Terraform *registry* source —
            // no PetCow equivalent (PetCow modules are local or git).
            crate::modulesrc::ModuleSource::Local(_) => {
                warnings.push(format!(
                    "module '{name}': Terraform registry source '{src}' has no PetCow equivalent — use a `git::`/`github.com/…//<path>` source pointing at a `.petcow.yaml`"
                ));
                return;
            }
        },
        None => {
            warnings.push(format!("module '{name}': no `source` — skipped"));
            return;
        }
    }
    entry.insert(Value::String("inputs".into()), Value::Mapping(inputs));
    sec.modules
        .insert(Value::String(name.clone()), Value::Mapping(entry));
}

/// Translate a `data` block into a `data:` entry (best-effort lookup name).
fn migrate_data(b: &hcl::structure::Block, sec: &mut Sections, warnings: &mut Vec<String>) -> bool {
    let labels: Vec<String> = b.labels.iter().map(label_str).collect();
    if labels.len() != 2 {
        warnings.push("skipped malformed data block (expected type + name)".into());
        return false;
    }
    let (tf_type, name) = (&labels[0], &labels[1]);
    let Some(petcow_type) = map_type(tf_type) else {
        warnings.push(format!(
            "data '{tf_type}.{name}': type not supported, skipped"
        ));
        return false;
    };
    // PetCow data sources look up by resource name; TF data sources use filters.
    // Pull a literal `name` if present, else flag it for manual completion.
    let mut lookup = None;
    for s in &b.body {
        if let Structure::Attribute(a) = s {
            if a.key.as_str() == "name" {
                if let Expression::String(v) = &a.expr {
                    lookup = Some(v.clone());
                }
            }
        }
    }
    let mut m = Mapping::new();
    m.insert(
        Value::String("type".into()),
        Value::String(petcow_type.into()),
    );
    match lookup {
        Some(v) => {
            m.insert(Value::String("name".into()), Value::String(v));
        }
        None => {
            m.insert(
                Value::String("name".into()),
                Value::String("TODO-set-lookup-name".into()),
            );
            warnings.push(format!(
                "data '{tf_type}.{name}': TF uses filters; set the lookup `name:` manually"
            ));
        }
    }
    sec.data
        .insert(Value::String(name.clone()), Value::Mapping(m));
    true
}

/// Translate a `lifecycle` block, folding it into the resource body (and the
/// document's `protected:` list for `prevent_destroy`).
fn migrate_lifecycle(
    nb: &hcl::structure::Block,
    res_name: &str,
    body_map: &mut Mapping,
    sec: &mut Sections,
    warnings: &mut Vec<String>,
) {
    let mut lc = Mapping::new();
    for s in &nb.body {
        let Structure::Attribute(a) = s else {
            warnings.push(format!(
                "resource '{res_name}': lifecycle nested block skipped"
            ));
            continue;
        };
        let ctx = format!("{res_name}.lifecycle.{}", a.key.as_str());
        match a.key.as_str() {
            "ignore_changes" => {
                // `ignore_changes = all` is the Variable `all`; else a list of attrs.
                if let Expression::Variable(v) = &a.expr {
                    if v.as_str() == "all" {
                        lc.insert(
                            Value::String("ignore_changes".into()),
                            Value::String("all".into()),
                        );
                        continue;
                    }
                }
                if let Some(v) = ignore_changes_to_value(&a.expr, &ctx, warnings) {
                    lc.insert(Value::String("ignore_changes".into()), v);
                }
            }
            "create_before_destroy" => {
                if let Some(v) = expr_to_value(&a.expr, &ctx, warnings) {
                    lc.insert(Value::String("create_before_destroy".into()), v);
                }
            }
            "prevent_destroy" => {
                if matches!(&a.expr, Expression::Bool(true)) {
                    sec.protected.push(Value::String(res_name.to_string()));
                    warnings.push(format!(
                        "resource '{res_name}': prevent_destroy → added to top-level protected:"
                    ));
                }
            }
            other => warnings.push(format!("{res_name}: lifecycle.{other} not translated")),
        }
    }
    if !lc.is_empty() {
        body_map.insert(Value::String("lifecycle".into()), Value::Mapping(lc));
    }
}

fn label_str(l: &BlockLabel) -> String {
    match l {
        BlockLabel::Identifier(id) => id.as_str().to_string(),
        BlockLabel::String(s) => s.clone(),
    }
}

/// Translate an HCL expression to a YAML value. Literals/arrays/objects become
/// plain YAML; references, function calls, operators, and conditionals become a
/// PetCow `${...}` template. Untranslatable expressions warn and return `None`.
fn expr_to_value(expr: &Expression, ctx: &str, warnings: &mut Vec<String>) -> Option<Value> {
    expr_to_value_iter(expr, ctx, None, warnings)
}

/// As [`expr_to_value`], but with a `dynamic`-block iterator name in scope.
fn expr_to_value_iter(
    expr: &Expression,
    ctx: &str,
    iter: Option<&str>,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    match expr {
        Expression::Null => Some(Value::Null),
        Expression::Bool(b) => Some(Value::Bool(*b)),
        Expression::Number(n) => Some(number_to_value(n)),
        Expression::String(s) => Some(Value::String(s.clone())),
        Expression::Array(items) => {
            let mut seq = Vec::new();
            for it in items {
                if let Some(v) = expr_to_value_iter(it, ctx, iter, warnings) {
                    seq.push(v);
                }
            }
            Some(Value::Sequence(seq))
        }
        Expression::Object(obj) => {
            let mut m = Mapping::new();
            for (k, v) in obj.iter() {
                let Some(key) = object_key_str(k) else {
                    warnings.push(format!("{ctx}: non-string object key skipped"));
                    continue;
                };
                if let Some(val) = expr_to_value_iter(v, ctx, iter, warnings) {
                    m.insert(Value::String(key), val);
                }
            }
            Some(Value::Mapping(m))
        }
        Expression::TemplateExpr(t) => template_to_value(t, ctx, iter, warnings),
        // References, calls, operators, conditionals → a PetCow `${...}` template.
        _ => render_expr(expr, ctx, iter, warnings).map(|e| Value::String(format!("${{{e}}}"))),
    }
}

/// Translate a `dynamic "NAME" { for_each = COLL  content { … } }` block into a
/// PetCow list attribute built with a for-expression:
/// `NAME: ${[for NAME in COLL : { k = v, … }]}`. The iterator (`NAME.value[.f]`)
/// maps to the loop variable. Returns `(attribute_name, value)`.
fn migrate_dynamic(
    nb: &hcl::structure::Block,
    res_name: &str,
    warnings: &mut Vec<String>,
) -> Option<(String, Value)> {
    let labels: Vec<String> = nb.labels.iter().map(label_str).collect();
    let Some(attr) = labels.first().cloned() else {
        warnings.push(format!(
            "resource '{res_name}': dynamic block without a name, skipped"
        ));
        return None;
    };
    let ctx = format!("{res_name}.dynamic.{attr}");

    let mut for_each: Option<&Expression> = None;
    let mut content: Option<&hcl::structure::Block> = None;
    let mut iter_name = attr.clone();
    for s in &nb.body {
        match s {
            Structure::Attribute(a) if a.key.as_str() == "for_each" => for_each = Some(&a.expr),
            Structure::Attribute(a) if a.key.as_str() == "iterator" => {
                if let Expression::Variable(v) = &a.expr {
                    iter_name = v.as_str().to_string();
                }
            }
            Structure::Attribute(a) => {
                warnings.push(format!("{ctx}: attribute '{}' ignored", a.key.as_str()))
            }
            Structure::Block(b) if b.identifier.as_str() == "content" => content = Some(b),
            Structure::Block(b) => warnings.push(format!(
                "{ctx}: nested block '{}' ignored",
                b.identifier.as_str()
            )),
        }
    }

    let Some(for_each) = for_each else {
        warnings.push(format!("{ctx}: missing for_each, skipped"));
        return None;
    };
    let Some(content) = content else {
        warnings.push(format!("{ctx}: missing content block, skipped"));
        return None;
    };
    let coll = render_expr(for_each, &ctx, None, warnings)?;

    // Render each content attribute as a `key = expr` entry (iterator in scope).
    let mut entries = Vec::new();
    for s in &content.body {
        match s {
            Structure::Attribute(a) => {
                let v = render_expr(&a.expr, &ctx, Some(&iter_name), warnings)?;
                entries.push(format!("{} = {}", a.key.as_str(), v));
            }
            Structure::Block(b) => warnings.push(format!(
                "{ctx}: nested block '{}' inside content not translated",
                b.identifier.as_str()
            )),
        }
    }

    let body = format!("{{{}}}", entries.join(", "));
    let expr = format!("[for {iter_name} in {coll} : {body}]");
    Some((attr, Value::String(format!("${{{expr}}}"))))
}

/// Translate an HCL string template (`"prefix-${expr}-suffix"`) into a PetCow
/// interpolated string, rendering each interpolation as `${...}`. Template
/// directives (`%{ if }` / `%{ for }`) aren't supported and abort with a warning.
fn template_to_value(
    t: &hcl::expr::TemplateExpr,
    ctx: &str,
    iter: Option<&str>,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    let tmpl = Template::from_expr(t).ok().or_else(|| {
        warnings.push(format!("{ctx}: could not parse string template, skipped"));
        None
    })?;
    let mut out = String::new();
    for el in tmpl.elements() {
        match el {
            Element::Literal(s) => out.push_str(s),
            Element::Interpolation(i) => {
                let rendered = render_expr(&i.expr, ctx, iter, warnings)?;
                out.push_str(&format!("${{{rendered}}}"));
            }
            Element::Directive(_) => {
                warnings.push(format!(
                    "{ctx}: template directive (%{{...}}) not translated, skipped"
                ));
                return None;
            }
        }
    }
    Some(Value::String(out))
}

/// Render an HCL expression as a PetCow expression-language string (the inside of
/// `${...}`). Returns `None` (with a warning) for constructs we can't represent.
fn render_expr(
    expr: &Expression,
    ctx: &str,
    iter: Option<&str>,
    warnings: &mut Vec<String>,
) -> Option<String> {
    match expr {
        Expression::Null => Some("null".into()),
        Expression::Bool(b) => Some(b.to_string()),
        Expression::Number(n) => Some(
            number_to_value(n)
                .as_f64()
                .map(|f| {
                    if f.fract() == 0.0 {
                        (f as i64).to_string()
                    } else {
                        f.to_string()
                    }
                })
                .unwrap_or_else(|| n.to_string()),
        ),
        Expression::String(s) => Some(quote_pcl(s)),
        Expression::Variable(v) => Some(v.as_str().to_string()),
        Expression::Array(items) => {
            let rendered: Option<Vec<String>> = items
                .iter()
                .map(|e| render_expr(e, ctx, iter, warnings))
                .collect();
            Some(format!("[{}]", rendered?.join(", ")))
        }
        Expression::Object(obj) => {
            let mut entries = Vec::new();
            for (k, v) in obj.iter() {
                let key = object_key_str(k)?;
                entries.push(format!("{key} = {}", render_expr(v, ctx, iter, warnings)?));
            }
            Some(format!("{{{}}}", entries.join(", ")))
        }
        Expression::Parenthesis(e) => Some(format!("({})", render_expr(e, ctx, iter, warnings)?)),
        Expression::Traversal(t) => render_traversal(t, ctx, iter, warnings),
        Expression::FuncCall(f) => {
            if !f.name.namespace.is_empty() {
                warnings.push(format!(
                    "{ctx}: namespaced function '{}' not translated",
                    f.name.name.as_str()
                ));
                return None;
            }
            let args: Option<Vec<String>> = f
                .args
                .iter()
                .map(|a| render_expr(a, ctx, iter, warnings))
                .collect();
            Some(format!("{}({})", f.name.name.as_str(), args?.join(", ")))
        }
        Expression::Conditional(c) => Some(format!(
            "{} ? {} : {}",
            render_expr(&c.cond_expr, ctx, iter, warnings)?,
            render_expr(&c.true_expr, ctx, iter, warnings)?,
            render_expr(&c.false_expr, ctx, iter, warnings)?
        )),
        Expression::Operation(op) => match op.as_ref() {
            hcl::expr::Operation::Unary(u) => Some(format!(
                "{}{}",
                u.operator,
                render_expr(&u.expr, ctx, iter, warnings)?
            )),
            hcl::expr::Operation::Binary(b) => Some(format!(
                "{} {} {}",
                render_expr(&b.lhs_expr, ctx, iter, warnings)?,
                b.operator,
                render_expr(&b.rhs_expr, ctx, iter, warnings)?
            )),
        },
        _ => {
            warnings.push(format!(
                "{ctx}: expression too complex to translate, skipped"
            ));
            None
        }
    }
}

/// Render a Terraform traversal as a PetCow path: `var.x`→`vars.x`, `local.x`,
/// `count.index`, `each.*`, `data.TYPE.NAME.attr`→`data.NAME.attr`, and a bare
/// resource reference `type.name.attr`→`resources.name.attr`. Inside a `dynamic`
/// block, `iter` is the iterator name: `<iter>.value[.f]` → the loop variable.
fn render_traversal(
    t: &hcl::expr::Traversal,
    ctx: &str,
    iter: Option<&str>,
    warnings: &mut Vec<String>,
) -> Option<String> {
    let Expression::Variable(root) = &t.expr else {
        warnings.push(format!("{ctx}: unsupported reference, skipped"));
        return None;
    };
    let root = root.as_str();
    let mut parts = Vec::new();
    // Index accessors (`[0]`, `["k"]`) are collected as a trailing suffix —
    // PetCow supports them (v0.72.0) as long as they come after the attribute
    // chain (the common `a.b.c[0]` shape). An attr after an index, or a splat,
    // stays unsupported.
    let mut index_suffix = String::new();
    for op in &t.operators {
        match op {
            TraversalOperator::GetAttr(id) if index_suffix.is_empty() => {
                parts.push(id.as_str().to_string())
            }
            TraversalOperator::LegacyIndex(n) => index_suffix.push_str(&format!("[{n}]")),
            TraversalOperator::Index(e) => {
                let rendered = render_expr(e, ctx, iter, warnings)?;
                index_suffix.push_str(&format!("[{rendered}]"));
            }
            _ => {
                warnings.push(format!(
                    "{ctx}: complex reference (splat/post-index attr) skipped"
                ));
                return None;
            }
        }
    }
    // Helper appends the collected index suffix to a rendered base path.
    let with_index = |base: String| -> String {
        if index_suffix.is_empty() {
            base
        } else {
            format!("{base}{index_suffix}")
        }
    };
    // `dynamic` iterator: `<iter>.value` is the element (the PetCow loop variable).
    if let Some(it) = iter {
        if root == it {
            return match parts.first().map(String::as_str) {
                Some("value") if parts.len() == 1 => Some(it.to_string()),
                Some("value") => Some(format!("{it}.{}", parts[1..].join("."))),
                _ => {
                    warnings.push(format!(
                        "{ctx}: dynamic iterator '{it}.key' not supported, skipped"
                    ));
                    None
                }
            };
        }
    }
    match root {
        "var" if !parts.is_empty() => Some(with_index(format!("vars.{}", parts.join(".")))),
        "local" if !parts.is_empty() => Some(with_index(format!("local.{}", parts.join(".")))),
        "count" if !parts.is_empty() => Some(with_index(format!("count.{}", parts.join(".")))),
        "each" if !parts.is_empty() => Some(with_index(format!("each.{}", parts.join(".")))),
        "data" if parts.len() >= 3 => Some(with_index(format!(
            "data.{}.{}",
            parts[1],
            parts[2..].join(".")
        ))),
        "module" | "self" | "path" | "terraform" => {
            warnings.push(format!(
                "{ctx}: '{root}.*' reference not translatable, skipped"
            ));
            None
        }
        _ if parts.len() >= 2 => Some(with_index(format!(
            "resources.{}.{}",
            parts[0],
            parts[1..].join(".")
        ))),
        _ => {
            warnings.push(format!(
                "{ctx}: reference '{root}.*' too short to map, skipped"
            ));
            None
        }
    }
}

/// Translate `depends_on = [type.name, …]` into a PetCow list of logical ids.
fn depends_on_to_value(expr: &Expression, ctx: &str, warnings: &mut Vec<String>) -> Option<Value> {
    let Expression::Array(items) = expr else {
        warnings.push(format!("{ctx}: depends_on must be a list, skipped"));
        return None;
    };
    let mut out = Vec::new();
    for it in items {
        if let Expression::Traversal(t) = it {
            // type.name → name
            if let TraversalOperator::GetAttr(id) = t.operators.first()? {
                out.push(Value::String(id.as_str().to_string()));
                continue;
            }
        }
        warnings.push(format!(
            "{ctx}: depends_on entry not a resource reference, skipped"
        ));
    }
    Some(Value::Sequence(out))
}

/// Translate `ignore_changes = [attr, …]`. Entries are usually bare traversals
/// of the attribute name.
fn ignore_changes_to_value(
    expr: &Expression,
    ctx: &str,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    let Expression::Array(items) = expr else {
        warnings.push(format!(
            "{ctx}: ignore_changes must be a list or 'all', skipped"
        ));
        return None;
    };
    let mut out = Vec::new();
    for it in items {
        match it {
            Expression::String(s) => out.push(Value::String(s.clone())),
            Expression::Variable(v) => out.push(Value::String(v.as_str().to_string())),
            Expression::Traversal(t) => {
                if let (Expression::Variable(root), true) = (&t.expr, t.operators.is_empty()) {
                    out.push(Value::String(root.as_str().to_string()));
                } else if let Some(TraversalOperator::GetAttr(id)) = t.operators.last() {
                    out.push(Value::String(id.as_str().to_string()));
                }
            }
            _ => warnings.push(format!("{ctx}: ignore_changes entry skipped")),
        }
    }
    Some(Value::Sequence(out))
}

/// Map a Terraform variable `type` expression to a PetCow var type keyword.
fn tf_type_to_vartype(expr: &Expression) -> String {
    match expr {
        Expression::Variable(v) => match v.as_str() {
            "string" | "number" | "bool" => v.as_str().to_string(),
            _ => "any".into(),
        },
        Expression::FuncCall(f) => match f.name.name.as_str() {
            "list" | "set" | "tuple" => "list".into(),
            "map" | "object" => "map".into(),
            _ => "any".into(),
        },
        _ => "any".into(),
    }
}

/// Quote a string as a PetCow expression-language literal, choosing a quote style
/// that avoids the embedded quote character (PetCow's lexer has no escapes).
fn quote_pcl(s: &str) -> String {
    if !s.contains('"') {
        format!("\"{s}\"")
    } else if !s.contains('\'') {
        format!("'{s}'")
    } else {
        // Both quote styles present — fall back to double quotes (rare).
        format!("\"{}\"", s.replace('"', ""))
    }
}

fn number_to_value(n: &hcl::Number) -> Value {
    if let Some(i) = n.as_i64() {
        Value::Number(i.into())
    } else if let Some(f) = n.as_f64() {
        serde_yaml::from_str(&f.to_string()).unwrap_or(Value::String(f.to_string()))
    } else {
        Value::String(n.to_string())
    }
}

fn object_key_str(k: &ObjectKey) -> Option<String> {
    match k {
        ObjectKey::Identifier(id) => Some(id.as_str().to_string()),
        ObjectKey::Expression(Expression::String(s)) => Some(s.clone()),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Ansible playbook → PetCow config plays (UR-10)
// ---------------------------------------------------------------------------

/// Task-control keys that are not the module being invoked.
const ANSIBLE_CONTROL_KEYS: &[&str] = &[
    "name",
    "become",
    "become_user",
    "when",
    "vars",
    "tags",
    "notify",
    "register",
    "loop",
    "with_items",
    "ignore_errors",
    "changed_when",
    "failed_when",
    "block",
];

/// Translate an Ansible playbook (YAML) into a PetCow document with `config:` plays.
pub fn migrate_ansible(src: &str, project: &str) -> Result<Migration> {
    let doc: Value = serde_yaml::from_str(src)
        .map_err(|e| PetcowError::document(format!("parsing Ansible playbook: {e}")))?;
    let plays_in = doc
        .as_sequence()
        .ok_or_else(|| PetcowError::document("an Ansible playbook must be a list of plays"))?;

    let mut warnings = Vec::new();
    let mut migrated = 0;
    let mut plays_out = Vec::new();

    for (pi, play) in plays_in.iter().enumerate() {
        let Some(pm) = play.as_mapping() else {
            warnings.push(format!("play #{pi}: not a mapping, skipped"));
            continue;
        };
        let name = sval(pm, "name").unwrap_or_else(|| format!("play-{pi}"));
        let hosts = sval(pm, "hosts");
        let mut play_map = Mapping::new();
        play_map.insert(Value::String("name".into()), Value::String(name.clone()));

        // Target: a simple host group, "all" → no filter, patterns → warn.
        if let Some(h) = &hosts {
            if h != "all" {
                if h.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                {
                    let mut t = Mapping::new();
                    t.insert(Value::String("group".into()), Value::String(h.clone()));
                    play_map.insert(Value::String("target".into()), Value::Mapping(t));
                } else {
                    warnings.push(format!(
                        "play '{name}': host pattern '{h}' not translated; target everything"
                    ));
                }
            }
        }

        let tasks = pm
            .get(Value::String("tasks".into()))
            .and_then(Value::as_sequence);
        let mut resources = Mapping::new();
        if let Some(tasks) = tasks {
            for (ti, task) in tasks.iter().enumerate() {
                let Some(tm) = task.as_mapping() else {
                    warnings.push(format!("play '{name}' task #{ti}: not a mapping, skipped"));
                    continue;
                };
                let tname = sval(tm, "name").unwrap_or_else(|| format!("task-{ti}"));
                if let Some(res) = ansible_task_to_resource(tm, &tname, &mut warnings) {
                    let id = format!("{:02}-{}", ti, crate::naming::sanitize(&tname));
                    resources.insert(Value::String(id), res);
                    migrated += 1;
                }
            }
        }
        play_map.insert(Value::String("resources".into()), Value::Mapping(resources));
        plays_out.push(Value::Mapping(play_map));
    }

    let mut out = Mapping::new();
    out.insert(
        Value::String("project".into()),
        Value::String(project.to_string()),
    );
    out.insert(Value::String("config".into()), Value::Sequence(plays_out));
    let yaml = serde_yaml::to_string(&Value::Mapping(out))
        .map_err(|e| PetcowError::document(format!("serializing: {e}")))?;
    Ok(Migration {
        yaml,
        migrated,
        warnings,
    })
}

/// Map one Ansible task to a PetCow CM resource value, or `None` (with a warning).
fn ansible_task_to_resource(
    tm: &Mapping,
    tname: &str,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    // The module is the one key that isn't a control key.
    let module = tm.iter().find_map(|(k, v)| {
        let key = k.as_str()?;
        if ANSIBLE_CONTROL_KEYS.contains(&key) {
            None
        } else {
            Some((key.to_string(), v))
        }
    });
    let Some((module, args)) = module else {
        warnings.push(format!("task '{tname}': no module found, skipped"));
        return None;
    };
    // Strip an `ansible.builtin.` (or other collection) prefix.
    let short = module.rsplit('.').next().unwrap_or(&module);
    let args_map = args.as_mapping();

    let res = |pairs: Vec<(&str, Value)>| -> Value {
        let mut m = Mapping::new();
        for (k, v) in pairs {
            m.insert(Value::String(k.to_string()), v);
        }
        Value::Mapping(m)
    };

    match short {
        "apt" | "yum" | "dnf" | "package" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            let present = !matches!(
                sval(m, "state").as_deref(),
                Some("absent") | Some("removed")
            );
            Some(res(vec![
                ("type", Value::String("os.package".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "service" | "systemd" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            let started = !matches!(sval(m, "state").as_deref(), Some("stopped"));
            let mut pairs = vec![
                ("type", Value::String("os.service".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if started { "started" } else { "stopped" }.into()),
                ),
            ];
            if let Some(en) = m
                .get(Value::String("enabled".into()))
                .and_then(Value::as_bool)
            {
                pairs.push(("enabled", Value::Bool(en)));
            }
            Some(res(pairs))
        }
        "copy" => {
            let m = args_map?;
            let dest = sval(m, "dest")?;
            let Some(content) = sval(m, "content") else {
                warnings.push(format!("task '{tname}': copy from a source file isn't supported (only inline `content`), skipped"));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.file".into())),
                ("path", Value::String(dest)),
                ("content", Value::String(content)),
            ];
            if let Some(mode) = sval(m, "mode") {
                pairs.push(("mode", Value::String(mode)));
            }
            Some(res(pairs))
        }
        "command" | "shell" => {
            // Args may be a bare string or a mapping with `cmd`.
            let cmd = args
                .as_str()
                .map(str::to_string)
                .or_else(|| args_map.and_then(|m| sval(m, "cmd")))?;
            Some(res(vec![
                ("type", Value::String("os.command".into())),
                ("command", Value::String(cmd)),
            ]))
        }
        "user" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            let mut pairs = vec![
                ("type", Value::String("os.user".into())),
                ("name", Value::String(name)),
                ("state", Value::String(ansible_present_state(m))),
            ];
            for (a, k) in [("shell", "shell"), ("home", "home")] {
                if let Some(v) = sval(m, a) {
                    pairs.push((k, Value::String(v)));
                }
            }
            if let Some(sys) = m
                .get(Value::String("system".into()))
                .and_then(Value::as_bool)
            {
                pairs.push(("system", Value::Bool(sys)));
            }
            Some(res(pairs))
        }
        "group" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            Some(res(vec![
                ("type", Value::String("os.group".into())),
                ("name", Value::String(name)),
                ("state", Value::String(ansible_present_state(m))),
            ]))
        }
        "cron" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            // Ansible spreads the schedule across minute/hour/day/month/weekday
            // (each defaulting to "*"); PetCow takes a single 5-field schedule.
            let field = |k: &str| sval(m, k).unwrap_or_else(|| "*".into());
            let schedule = format!(
                "{} {} {} {} {}",
                field("minute"),
                field("hour"),
                field("day"),
                field("month"),
                field("weekday"),
            );
            let mut pairs = vec![
                ("type", Value::String("os.cron".into())),
                ("name", Value::String(name)),
                ("state", Value::String(ansible_present_state(m))),
                ("schedule", Value::String(schedule)),
            ];
            if let Some(job) = sval(m, "job") {
                pairs.push(("command", Value::String(job)));
            }
            Some(res(pairs))
        }
        "lineinfile" => {
            let m = args_map?;
            let path = sval(m, "path").or_else(|| sval(m, "dest"))?;
            // Only the simple exact-line form maps; `regexp`-based replacement
            // has no honest equivalent in os.line_in_file.
            if m.contains_key(Value::String("regexp".into())) {
                warnings.push(format!(
                    "task '{tname}': lineinfile `regexp` not supported (only exact `line`), skipped"
                ));
                return None;
            }
            let line = sval(m, "line")?;
            Some(res(vec![
                ("type", Value::String("os.line_in_file".into())),
                ("path", Value::String(path)),
                ("line", Value::String(line)),
                ("state", Value::String(ansible_present_state(m))),
            ]))
        }
        "file" => {
            // `state: directory` → os.directory; `state: link` → os.symlink.
            // Other states (touch/hard) have no honest equivalent.
            let m = args_map?;
            match sval(m, "state").as_deref() {
                Some("directory") => {
                    let path = sval(m, "path").or_else(|| sval(m, "dest"))?;
                    let mut pairs = vec![
                        ("type", Value::String("os.directory".into())),
                        ("path", Value::String(path)),
                    ];
                    if let Some(mode) = sval(m, "mode") {
                        pairs.push(("mode", Value::String(mode)));
                    }
                    Some(res(pairs))
                }
                Some("link") => {
                    let path = sval(m, "path").or_else(|| sval(m, "dest"))?;
                    let target = sval(m, "src")?;
                    Some(res(vec![
                        ("type", Value::String("os.symlink".into())),
                        ("target", Value::String(target)),
                        ("path", Value::String(path)),
                    ]))
                }
                _ => {
                    warnings.push(format!(
                        "task '{tname}': file module only maps `state: directory`/`link`; skipped"
                    ));
                    None
                }
            }
        }
        "sysctl" => {
            let m = args_map?;
            let key = sval(m, "name")?;
            let value = sval(m, "value")?;
            Some(res(vec![
                ("type", Value::String("os.sysctl".into())),
                ("key", Value::String(key)),
                ("value", Value::String(value)),
            ]))
        }
        "hostname" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            Some(res(vec![
                ("type", Value::String("os.hostname".into())),
                ("name", Value::String(name)),
            ]))
        }
        "timezone" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            Some(res(vec![
                ("type", Value::String("os.timezone".into())),
                ("name", Value::String(name)),
            ]))
        }
        "mount" => {
            let m = args_map?;
            // PetCow os.mount is present/mounted only; absent/unmounted is a gap.
            match sval(m, "state").as_deref() {
                Some("absent") | Some("unmounted") => {
                    warnings.push(format!(
                        "task '{tname}': mount `state: {}` not supported (os.mount is mounted-only), skipped",
                        sval(m, "state").unwrap_or_default()
                    ));
                    return None;
                }
                _ => {}
            }
            // Ansible's `path` was historically `name`.
            let path = sval(m, "path").or_else(|| sval(m, "name"))?;
            let src = sval(m, "src")?;
            let fstype = sval(m, "fstype")?;
            let mut pairs = vec![
                ("type", Value::String("os.mount".into())),
                ("src", Value::String(src)),
                ("path", Value::String(path)),
                ("fstype", Value::String(fstype)),
            ];
            if let Some(opts) = sval(m, "opts") {
                pairs.push(("opts", Value::String(opts)));
            }
            Some(res(pairs))
        }
        "authorized_key" => {
            let m = args_map?;
            let user = sval(m, "user")?;
            let key = sval(m, "key")?;
            Some(res(vec![
                ("type", Value::String("os.authorized_key".into())),
                ("user", Value::String(user)),
                ("key", Value::String(key)),
                ("state", Value::String(ansible_present_state(m))),
            ]))
        }
        "git" => {
            let m = args_map?;
            let repo = sval(m, "repo")?;
            let dest = sval(m, "dest")?;
            let mut pairs = vec![
                ("type", Value::String("os.git".into())),
                ("repo", Value::String(repo)),
                ("dest", Value::String(dest)),
            ];
            if let Some(v) = sval(m, "version") {
                pairs.push(("version", Value::String(v)));
            }
            Some(res(pairs))
        }
        "pip" => {
            let m = args_map?;
            let name = sval(m, "name")?;
            let mut pairs = vec![
                ("type", Value::String("os.pip".into())),
                ("name", Value::String(name)),
                ("state", Value::String(ansible_present_state(m))),
            ];
            if let Some(v) = sval(m, "version") {
                pairs.push(("version", Value::String(v)));
            }
            Some(res(pairs))
        }
        other => {
            warnings.push(format!(
                "task '{tname}': module '{other}' not supported, skipped"
            ));
            None
        }
    }
}

/// Map an Ansible `state:` to PetCow's `present`/`absent` (default present).
fn ansible_present_state(m: &Mapping) -> String {
    match sval(m, "state").as_deref() {
        Some("absent") | Some("removed") => "absent",
        _ => "present",
    }
    .to_string()
}

/// Get a string field from a YAML mapping.
fn sval(m: &Mapping, key: &str) -> Option<String> {
    m.get(Value::String(key.to_string()))
        .and_then(Value::as_str)
        .map(str::to_string)
}

// ---------------------------------------------------------------------------
// Salt states (.sls YAML) → PetCow config plays (UR-10)
// ---------------------------------------------------------------------------

/// Translate a Salt `.sls` state file into a PetCow document with one `config:`
/// play. Each top-level key is a state ID mapping to `<module>.<function>: [args]`.
pub fn migrate_salt(src: &str, project: &str) -> Result<Migration> {
    let doc: Value = serde_yaml::from_str(src)
        .map_err(|e| PetcowError::document(format!("parsing Salt sls: {e}")))?;
    let states = doc
        .as_mapping()
        .ok_or_else(|| PetcowError::document("a Salt sls file must be a mapping of state IDs"))?;

    let mut warnings = Vec::new();
    let mut migrated = 0;
    let mut resources = Mapping::new();

    for (id_v, body_v) in states {
        let id = id_v.as_str().unwrap_or("?");
        if matches!(id, "include" | "extend") {
            warnings.push(format!("top-level '{id}' not translated, skipped"));
            continue;
        }
        let Some(body) = body_v.as_mapping() else {
            warnings.push(format!("state '{id}': not a mapping, skipped"));
            continue;
        };
        // A state ID maps function calls (`pkg.installed`) to their arg lists.
        let calls: Vec<(&str, &Value)> = body
            .iter()
            .filter_map(|(k, v)| {
                let key = k.as_str()?;
                key.contains('.').then_some((key, v))
            })
            .collect();
        let multi = calls.len() > 1;
        for (func, args_v) in calls {
            let args = salt_args(args_v);
            if let Some(res) = salt_state_to_resource(func, &args, id, &mut warnings) {
                let rid = if multi {
                    format!("{id}-{}", func.replace('.', "_"))
                } else {
                    id.to_string()
                };
                resources.insert(Value::String(rid), res);
                migrated += 1;
            }
        }
    }

    let mut play = Mapping::new();
    play.insert(
        Value::String("name".into()),
        Value::String("salt-import".into()),
    );
    play.insert(Value::String("resources".into()), Value::Mapping(resources));
    let mut out = Mapping::new();
    out.insert(
        Value::String("project".into()),
        Value::String(project.to_string()),
    );
    out.insert(
        Value::String("config".into()),
        Value::Sequence(vec![Value::Mapping(play)]),
    );
    let yaml = serde_yaml::to_string(&Value::Mapping(out))
        .map_err(|e| PetcowError::document(format!("serializing: {e}")))?;
    Ok(Migration {
        yaml,
        migrated,
        warnings,
    })
}

/// Flatten Salt's arg form (a list of single-key dicts, or a plain mapping) into
/// one mapping.
fn salt_args(v: &Value) -> Mapping {
    let mut out = Mapping::new();
    match v {
        Value::Sequence(seq) => {
            for item in seq {
                if let Some(m) = item.as_mapping() {
                    for (k, val) in m {
                        out.insert(k.clone(), val.clone());
                    }
                }
            }
        }
        Value::Mapping(m) => out = m.clone(),
        _ => {}
    }
    out
}

/// Map one Salt state call to a PetCow CM resource value, or `None` (with a warning).
fn salt_state_to_resource(
    func: &str,
    args: &Mapping,
    id: &str,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    // `name` arg overrides the state ID as the managed target.
    let name = sval(args, "name").unwrap_or_else(|| id.to_string());
    let res = |pairs: Vec<(&str, Value)>| -> Value {
        let mut m = Mapping::new();
        for (k, v) in pairs {
            m.insert(Value::String(k.to_string()), v);
        }
        Value::Mapping(m)
    };
    let truthy = |k: &str| {
        args.get(Value::String(k.into()))
            .and_then(|v| {
                v.as_bool()
                    .or_else(|| v.as_str().map(|s| s.eq_ignore_ascii_case("true")))
            })
            .unwrap_or(false)
    };

    match func {
        "pkg.installed" | "pkg.present" | "pkg.latest" => Some(res(vec![
            ("type", Value::String("os.package".into())),
            ("name", Value::String(name)),
            ("state", Value::String("present".into())),
        ])),
        "pkg.removed" | "pkg.absent" | "pkg.purged" => Some(res(vec![
            ("type", Value::String("os.package".into())),
            ("name", Value::String(name)),
            ("state", Value::String("absent".into())),
        ])),
        "service.running" | "service.enabled" => {
            let mut pairs = vec![
                ("type", Value::String("os.service".into())),
                ("name", Value::String(name)),
                ("state", Value::String("started".into())),
            ];
            if func == "service.enabled" || truthy("enable") {
                pairs.push(("enabled", Value::Bool(true)));
            }
            Some(res(pairs))
        }
        "service.dead" | "service.disabled" => Some(res(vec![
            ("type", Value::String("os.service".into())),
            ("name", Value::String(name)),
            ("state", Value::String("stopped".into())),
        ])),
        "file.managed" => {
            let Some(contents) = sval(args, "contents") else {
                warnings.push(format!(
                    "state '{id}': file.managed without inline `contents` (source not supported), skipped"
                ));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.file".into())),
                ("path", Value::String(name)),
                ("content", Value::String(contents)),
            ];
            if let Some(mode) = sval(args, "mode") {
                pairs.push(("mode", Value::String(mode)));
            }
            Some(res(pairs))
        }
        "cmd.run" | "cmd.script" => Some(res(vec![
            ("type", Value::String("os.command".into())),
            ("command", Value::String(name)),
        ])),
        "user.present" => Some(res(vec![
            ("type", Value::String("os.user".into())),
            ("name", Value::String(name)),
            ("state", Value::String("present".into())),
        ])),
        "user.absent" => Some(res(vec![
            ("type", Value::String("os.user".into())),
            ("name", Value::String(name)),
            ("state", Value::String("absent".into())),
        ])),
        "group.present" => Some(res(vec![
            ("type", Value::String("os.group".into())),
            ("name", Value::String(name)),
            ("state", Value::String("present".into())),
        ])),
        "group.absent" => Some(res(vec![
            ("type", Value::String("os.group".into())),
            ("name", Value::String(name)),
            ("state", Value::String("absent".into())),
        ])),
        "file.directory" => {
            let mut pairs = vec![
                ("type", Value::String("os.directory".into())),
                ("path", Value::String(name)),
            ];
            if let Some(mode) = sval(args, "mode") {
                pairs.push(("mode", Value::String(mode)));
            }
            Some(res(pairs))
        }
        "file.line" => {
            // Salt file.line: name=path, content=the line, mode=ensure|delete.
            let Some(content) = sval(args, "content") else {
                warnings.push(format!("state '{id}': file.line needs `content`, skipped"));
                return None;
            };
            let present = !matches!(
                sval(args, "mode").as_deref(),
                Some("delete") | Some("absent")
            );
            Some(res(vec![
                ("type", Value::String("os.line_in_file".into())),
                ("path", Value::String(name)),
                ("line", Value::String(content)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "cron.present" | "cron.absent" => {
            // Salt cron uses name=command, with minute/hour/... fields ("*" default).
            let field = |k: &str| sval(args, k).unwrap_or_else(|| "*".into());
            let schedule = format!(
                "{} {} {} {} {}",
                field("minute"),
                field("hour"),
                field("daymonth"),
                field("month"),
                field("dayweek"),
            );
            let present = func == "cron.present";
            Some(res(vec![
                ("type", Value::String("os.cron".into())),
                ("name", Value::String(name.clone())),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
                ("schedule", Value::String(schedule)),
                ("command", Value::String(name)),
            ]))
        }
        "sysctl.present" => {
            let value = sval(args, "value")?;
            Some(res(vec![
                ("type", Value::String("os.sysctl".into())),
                ("key", Value::String(name)),
                ("value", Value::String(value)),
            ]))
        }
        "timezone.system" => Some(res(vec![
            ("type", Value::String("os.timezone".into())),
            ("name", Value::String(name)),
        ])),
        "mount.mounted" => {
            let device = sval(args, "device")?;
            let fstype = sval(args, "fstype")?;
            // Salt `opts` may be a string or a list of options.
            let opts = match args.get(Value::String("opts".into())) {
                Some(Value::String(s)) => Some(s.clone()),
                Some(Value::Sequence(seq)) => Some(
                    seq.iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(","),
                ),
                _ => None,
            };
            let mut pairs = vec![
                ("type", Value::String("os.mount".into())),
                ("src", Value::String(device)),
                ("path", Value::String(name)),
                ("fstype", Value::String(fstype)),
            ];
            if let Some(opts) = opts {
                pairs.push(("opts", Value::String(opts)));
            }
            Some(res(pairs))
        }
        "mount.unmounted" => {
            warnings.push(format!(
                "state '{id}': mount.unmounted not supported (os.mount is mounted-only), skipped"
            ));
            None
        }
        "pip.installed" | "pip.removed" => {
            // Salt embeds any version in the name spec (`requests==2.31.0`); split
            // it out so os.pip can pin. `name` arg or state ID is the package.
            let present = func == "pip.installed";
            let (pkg, version) = match name.split_once("==") {
                Some((p, v)) => (p.to_string(), Some(v.to_string())),
                None => (name, None),
            };
            let mut pairs = vec![
                ("type", Value::String("os.pip".into())),
                ("name", Value::String(pkg)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ];
            if let Some(v) = version {
                pairs.push(("version", Value::String(v)));
            }
            Some(res(pairs))
        }
        "git.latest" => {
            // Salt git.latest: name=repo URL, target=checkout dir, rev=branch/tag.
            let target = sval(args, "target")?;
            let mut pairs = vec![
                ("type", Value::String("os.git".into())),
                ("repo", Value::String(name)),
                ("dest", Value::String(target)),
            ];
            if let Some(v) = sval(args, "rev") {
                pairs.push(("version", Value::String(v)));
            }
            Some(res(pairs))
        }
        "ssh_auth.present" | "ssh_auth.absent" => {
            // Salt ssh_auth: name=the public key, user=the account.
            let user = sval(args, "user")?;
            let present = func == "ssh_auth.present";
            Some(res(vec![
                ("type", Value::String("os.authorized_key".into())),
                ("user", Value::String(user)),
                ("key", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        other => {
            warnings.push(format!("state '{id}': '{other}' not supported, skipped"));
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Puppet manifests (.pp) → PetCow config plays (UR-10)
// ---------------------------------------------------------------------------

#[derive(Debug, PartialEq, Clone)]
enum PTok {
    Word(String),
    Str(String),
    Arrow, // =>
    Open,  // {
    Close, // }
    Colon, // :
    Comma, // ,
    Semi,  // ;
}

/// Tokenize a Puppet manifest (comments stripped). Lenient: unknown punctuation
/// is skipped.
fn lex_puppet(src: &str) -> Vec<PTok> {
    let chars: Vec<char> = src.chars().collect();
    let mut toks = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '#' {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
        } else if c.is_whitespace() {
            i += 1;
        } else if c == '\'' || c == '"' {
            let mut j = i + 1;
            while j < chars.len() && chars[j] != c {
                j += 1;
            }
            toks.push(PTok::Str(chars[i + 1..j.min(chars.len())].iter().collect()));
            i = j + 1;
        } else if c == '=' && chars.get(i + 1) == Some(&'>') {
            toks.push(PTok::Arrow);
            i += 2;
        } else if c == '{' {
            toks.push(PTok::Open);
            i += 1;
        } else if c == '}' {
            toks.push(PTok::Close);
            i += 1;
        } else if c == ':' {
            toks.push(PTok::Colon);
            i += 1;
        } else if c == ',' {
            toks.push(PTok::Comma);
            i += 1;
        } else if c == ';' {
            toks.push(PTok::Semi);
            i += 1;
        } else if c.is_alphanumeric() || "_/.-".contains(c) {
            let start = i;
            while i < chars.len() && (chars[i].is_alphanumeric() || "_/.-".contains(chars[i])) {
                i += 1;
            }
            toks.push(PTok::Word(chars[start..i].iter().collect()));
        } else {
            i += 1; // skip unrecognized punctuation
        }
    }
    toks
}

/// Translate a Puppet manifest into a PetCow document with one `config:` play.
/// Parses simple resource declarations: `type { 'title': attr => value, … }`.
pub fn migrate_puppet(src: &str, project: &str) -> Result<Migration> {
    let toks = lex_puppet(src);
    let mut i = 0;
    let mut resources = Mapping::new();
    let mut warnings = Vec::new();
    let mut migrated = 0;

    while i < toks.len() {
        // A resource declaration starts: Word '{' (Str|Word) ':'
        let PTok::Word(type_) = &toks[i] else {
            warnings.push(format!("skipped unexpected token {:?}", toks[i]));
            i += 1;
            continue;
        };
        let type_ = type_.clone();
        if toks.get(i + 1) != Some(&PTok::Open) {
            // Not a resource decl (could be a class/define/var) — skip to next '{' group.
            warnings.push(format!(
                "'{type_}' is not a simple resource declaration, skipped"
            ));
            i = skip_to_close(&toks, i);
            continue;
        }
        let title = match toks.get(i + 2) {
            Some(PTok::Str(s)) | Some(PTok::Word(s)) => s.clone(),
            _ => {
                warnings.push(format!("resource '{type_}': missing title, skipped"));
                i = skip_to_close(&toks, i);
                continue;
            }
        };
        if toks.get(i + 3) != Some(&PTok::Colon) {
            warnings.push(format!("resource '{type_} {title}': malformed, skipped"));
            i = skip_to_close(&toks, i);
            continue;
        }
        // Parse `attr => value` pairs until '}'.
        let mut attrs: BTreeMap<String, String> = BTreeMap::new();
        let mut j = i + 4;
        while j < toks.len() && toks[j] != PTok::Close {
            if matches!(toks[j], PTok::Comma | PTok::Semi) {
                j += 1;
                continue;
            }
            let (PTok::Word(name), Some(PTok::Arrow)) = (&toks[j], toks.get(j + 1)) else {
                j += 1;
                continue;
            };
            let name = name.clone();
            let val = match toks.get(j + 2) {
                Some(PTok::Str(s)) | Some(PTok::Word(s)) => s.clone(),
                _ => String::new(),
            };
            attrs.insert(name, val);
            j += 3;
        }
        if let Some(res) = puppet_resource(&type_, &title, &attrs, &mut warnings) {
            // Puppet titles are unique only per type (`package {'nginx'}` and
            // `service {'nginx'}` coexist) — disambiguate colliding config ids.
            let mut rid = title.clone();
            if resources.contains_key(Value::String(rid.clone())) {
                rid = format!("{type_}_{title}");
            }
            resources.insert(Value::String(rid), res);
            migrated += 1;
        }
        i = j + 1; // past the '}'
    }

    let mut play = Mapping::new();
    play.insert(
        Value::String("name".into()),
        Value::String("puppet-import".into()),
    );
    play.insert(Value::String("resources".into()), Value::Mapping(resources));
    let mut out = Mapping::new();
    out.insert(
        Value::String("project".into()),
        Value::String(project.to_string()),
    );
    out.insert(
        Value::String("config".into()),
        Value::Sequence(vec![Value::Mapping(play)]),
    );
    let yaml = serde_yaml::to_string(&Value::Mapping(out))
        .map_err(|e| PetcowError::document(format!("serializing: {e}")))?;
    Ok(Migration {
        yaml,
        migrated,
        warnings,
    })
}

/// Advance past the next `{ … }` group (best-effort resync after a parse issue).
fn skip_to_close(toks: &[PTok], from: usize) -> usize {
    let mut depth = 0;
    let mut i = from;
    while i < toks.len() {
        match toks[i] {
            PTok::Open => depth += 1,
            PTok::Close => {
                depth -= 1;
                if depth <= 0 {
                    return i + 1;
                }
            }
            _ => {}
        }
        i += 1;
    }
    toks.len()
}

/// Map a Puppet resource (`type`, `title`, attrs) to a PetCow CM resource.
fn puppet_resource(
    type_: &str,
    title: &str,
    attrs: &BTreeMap<String, String>,
    warnings: &mut Vec<String>,
) -> Option<Value> {
    let ensure = attrs.get("ensure").map(String::as_str);
    let res = |pairs: Vec<(&str, Value)>| -> Value {
        let mut m = Mapping::new();
        for (k, v) in pairs {
            m.insert(Value::String(k.to_string()), v);
        }
        Value::Mapping(m)
    };
    // Puppet `name`/`title` alias: an explicit name attr overrides the title.
    let name = attrs
        .get("name")
        .cloned()
        .unwrap_or_else(|| title.to_string());

    match type_ {
        "package" => {
            let present = !matches!(ensure, Some("absent") | Some("purged"));
            // A pip-provider package is a Python package → os.pip; `ensure` may
            // also carry a version string (e.g. ensure => '2.31.0').
            if matches!(
                attrs.get("provider").map(String::as_str),
                Some("pip") | Some("pip3")
            ) {
                let mut pairs = vec![
                    ("type", Value::String("os.pip".into())),
                    ("name", Value::String(name)),
                    (
                        "state",
                        Value::String(if present { "present" } else { "absent" }.into()),
                    ),
                ];
                if let Some(v) = ensure.filter(|e| {
                    !matches!(*e, "present" | "installed" | "latest" | "absent" | "purged")
                }) {
                    pairs.push(("version", Value::String(v.to_string())));
                }
                return Some(res(pairs));
            }
            Some(res(vec![
                ("type", Value::String("os.package".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "service" => {
            let started = !matches!(ensure, Some("stopped"));
            let mut pairs = vec![
                ("type", Value::String("os.service".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if started { "started" } else { "stopped" }.into()),
                ),
            ];
            if let Some(en) = attrs.get("enable") {
                pairs.push(("enabled", Value::Bool(en == "true")));
            }
            Some(res(pairs))
        }
        "file" => {
            if matches!(ensure, Some("directory")) {
                let mut pairs = vec![
                    ("type", Value::String("os.directory".into())),
                    ("path", Value::String(name)),
                ];
                if let Some(mode) = attrs.get("mode") {
                    pairs.push(("mode", Value::String(mode.clone())));
                }
                return Some(res(pairs));
            }
            let Some(content) = attrs.get("content") else {
                warnings.push(format!(
                    "file '{title}': no inline `content` (source/template not supported), skipped"
                ));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.file".into())),
                ("path", Value::String(name)),
                ("content", Value::String(content.clone())),
            ];
            if let Some(mode) = attrs.get("mode") {
                pairs.push(("mode", Value::String(mode.clone())));
            }
            Some(res(pairs))
        }
        "exec" => {
            let cmd = attrs.get("command").cloned().unwrap_or(name);
            Some(res(vec![
                ("type", Value::String("os.command".into())),
                ("command", Value::String(cmd)),
            ]))
        }
        "user" => {
            let present = !matches!(ensure, Some("absent"));
            Some(res(vec![
                ("type", Value::String("os.user".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "group" => {
            let present = !matches!(ensure, Some("absent"));
            Some(res(vec![
                ("type", Value::String("os.group".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "file_line" => {
            // puppetlabs-stdlib file_line: path + line + ensure.
            let Some(line) = attrs.get("line") else {
                warnings.push(format!("file_line '{title}': needs `line`, skipped"));
                return None;
            };
            let path = attrs.get("path").cloned().unwrap_or_else(|| name.clone());
            let present = !matches!(ensure, Some("absent"));
            Some(res(vec![
                ("type", Value::String("os.line_in_file".into())),
                ("path", Value::String(path)),
                ("line", Value::String(line.clone())),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        "cron" => {
            // Puppet cron fields: minute/hour/monthday/month/weekday ("*" default).
            let present = !matches!(ensure, Some("absent"));
            let field = |k: &str| attrs.get(k).cloned().unwrap_or_else(|| "*".into());
            let schedule = format!(
                "{} {} {} {} {}",
                field("minute"),
                field("hour"),
                field("monthday"),
                field("month"),
                field("weekday"),
            );
            let command = attrs
                .get("command")
                .cloned()
                .unwrap_or_else(|| name.clone());
            Some(res(vec![
                ("type", Value::String("os.cron".into())),
                ("name", Value::String(name)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
                ("schedule", Value::String(schedule)),
                ("command", Value::String(command)),
            ]))
        }
        "sysctl" => {
            // augeasproviders_sysctl: title=key, value attr.
            let Some(value) = attrs.get("value") else {
                warnings.push(format!("sysctl '{title}': needs `value`, skipped"));
                return None;
            };
            Some(res(vec![
                ("type", Value::String("os.sysctl".into())),
                ("key", Value::String(name)),
                ("value", Value::String(value.clone())),
            ]))
        }
        "mount" => {
            // Core Puppet `mount`: title/name=mountpoint, device, fstype, options.
            if matches!(ensure, Some("absent") | Some("unmounted")) {
                warnings.push(format!(
                    "mount '{title}': ensure '{}' not supported (os.mount is mounted-only), skipped",
                    ensure.unwrap_or_default()
                ));
                return None;
            }
            let (Some(device), Some(fstype)) = (attrs.get("device"), attrs.get("fstype")) else {
                warnings.push(format!(
                    "mount '{title}': needs `device` and `fstype`, skipped"
                ));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.mount".into())),
                ("src", Value::String(device.clone())),
                ("path", Value::String(name)),
                ("fstype", Value::String(fstype.clone())),
            ];
            if let Some(opts) = attrs.get("options") {
                pairs.push(("opts", Value::String(opts.clone())));
            }
            Some(res(pairs))
        }
        "vcsrepo" => {
            // puppetlabs-vcsrepo (git provider): path/title=dest, source=repo,
            // revision=version.
            let Some(repo) = attrs.get("source") else {
                warnings.push(format!("vcsrepo '{title}': needs `source`, skipped"));
                return None;
            };
            let dest = attrs.get("path").cloned().unwrap_or(name);
            let mut pairs = vec![
                ("type", Value::String("os.git".into())),
                ("repo", Value::String(repo.clone())),
                ("dest", Value::String(dest)),
            ];
            if let Some(v) = attrs.get("revision") {
                pairs.push(("version", Value::String(v.clone())));
            }
            Some(res(pairs))
        }
        "ssh_authorized_key" => {
            // Core Puppet: the key is split into `type` + `key` (base64); the
            // title is the trailing comment. Reconstruct the authorized_keys line.
            let (Some(user), Some(ktype), Some(kdata)) =
                (attrs.get("user"), attrs.get("type"), attrs.get("key"))
            else {
                warnings.push(format!(
                    "ssh_authorized_key '{title}': needs `user`, `type`, and `key`, skipped"
                ));
                return None;
            };
            let present = !matches!(ensure, Some("absent"));
            let line = format!("{ktype} {kdata} {title}");
            Some(res(vec![
                ("type", Value::String("os.authorized_key".into())),
                ("user", Value::String(user.clone())),
                ("key", Value::String(line)),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ]))
        }
        other => {
            warnings.push(format!(
                "resource type '{other}' ('{title}') not supported, skipped"
            ));
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Chef recipes (.rb) → PetCow config plays (UR-10)
// ---------------------------------------------------------------------------

/// Translate a Chef recipe into a PetCow document with one `config:` play.
/// Parses the common resource shape: `type 'name' do <attr value> … end`.
pub fn migrate_chef(src: &str, project: &str) -> Result<Migration> {
    let mut resources = Mapping::new();
    let mut warnings = Vec::new();
    let mut migrated = 0;

    // Line-oriented: recipes are a flat sequence of `type 'name' do … end` blocks.
    struct ChefBlock {
        type_: String,
        name: String,
        attrs: BTreeMap<String, String>,
        actions: Vec<String>,
    }
    let mut cur: Option<ChefBlock> = None;
    for raw in src.lines() {
        // Strip trailing `# comment` (best-effort; ignores `#` inside strings).
        let line = match raw.find('#') {
            Some(p) => &raw[..p],
            None => raw,
        };
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        match &mut cur {
            None => {
                if let Some((type_, name)) = parse_chef_header(t) {
                    cur = Some(ChefBlock {
                        type_,
                        name,
                        attrs: BTreeMap::new(),
                        actions: Vec::new(),
                    });
                } else if let Some((type_, name)) = parse_chef_oneliner(t) {
                    // A block-less resource (`hostname 'web-01'`): emit immediately
                    // with no attrs/actions.
                    if let Some((id, res)) =
                        chef_resource(&type_, &name, &BTreeMap::new(), &[], &mut warnings)
                    {
                        let id = if resources.contains_key(Value::String(id.clone())) {
                            format!("{type_}_{name}")
                        } else {
                            id
                        };
                        resources.insert(Value::String(id), res);
                        migrated += 1;
                    }
                } else {
                    warnings.push(format!("skipped non-resource line: {t}"));
                }
            }
            Some(blk) => {
                if t == "end" {
                    let ChefBlock {
                        type_,
                        name,
                        attrs,
                        actions,
                    } = cur.take().unwrap();
                    if let Some((id, res)) =
                        chef_resource(&type_, &name, &attrs, &actions, &mut warnings)
                    {
                        let id = if resources.contains_key(Value::String(id.clone())) {
                            format!("{type_}_{name}")
                        } else {
                            id
                        };
                        resources.insert(Value::String(id), res);
                        migrated += 1;
                    }
                } else if let Some((attr, val)) = t.split_once(char::is_whitespace) {
                    if attr == "action" {
                        // `action :install` or `action [:enable, :start]`
                        for a in val.split([' ', ',', '[', ']', ':']) {
                            let a = a.trim();
                            if !a.is_empty() {
                                blk.actions.push(a.to_string());
                            }
                        }
                    } else {
                        blk.attrs.insert(attr.to_string(), unquote(val.trim()));
                    }
                }
            }
        }
    }
    if cur.is_some() {
        warnings.push("recipe ended inside an unterminated resource block".into());
    }

    let mut play = Mapping::new();
    play.insert(
        Value::String("name".into()),
        Value::String("chef-import".into()),
    );
    play.insert(Value::String("resources".into()), Value::Mapping(resources));
    let mut out = Mapping::new();
    out.insert(
        Value::String("project".into()),
        Value::String(project.to_string()),
    );
    out.insert(
        Value::String("config".into()),
        Value::Sequence(vec![Value::Mapping(play)]),
    );
    let yaml = serde_yaml::to_string(&Value::Mapping(out))
        .map_err(|e| PetcowError::document(format!("serializing: {e}")))?;
    Ok(Migration {
        yaml,
        migrated,
        warnings,
    })
}

/// Parse a Chef resource header line (`type 'name' do`) → `(type, name)`.
fn parse_chef_header(line: &str) -> Option<(String, String)> {
    // A bare `do` needs no special case: it is shorter than the " do" suffix, so
    // the strip already rejects it.
    let body = line.strip_suffix(" do")?.trim_end();
    let (type_, rest) = body.split_once(char::is_whitespace)?;
    let rest = rest.trim();
    // A resource name must be quoted (distinguishes from `… do |x|` Ruby blocks).
    if !(rest.starts_with('\'') || rest.starts_with('"')) {
        return None;
    }
    Some((type_.to_string(), unquote(rest)))
}

/// Parse a block-less Chef resource one-liner (`hostname 'web-01'`) →
/// `(type, name)`. Rejects block headers (handled by `parse_chef_header`),
/// non-identifier types, and unquoted names (to avoid eating Ruby code).
fn parse_chef_oneliner(line: &str) -> Option<(String, String)> {
    if line == "do" || line.ends_with(" do") {
        return None;
    }
    let (type_, rest) = line.split_once(char::is_whitespace)?;
    if type_.is_empty() || !type_.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }
    let rest = rest.trim();
    // The name must be a single quoted token (no further args/code).
    let quote = rest.chars().next()?;
    if quote != '\'' && quote != '"' {
        return None;
    }
    if rest.len() < 2 || !rest.ends_with(quote) || rest[1..rest.len() - 1].contains(quote) {
        return None;
    }
    Some((type_.to_string(), unquote(rest)))
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    let bytes = s.as_bytes();
    if s.len() >= 2 && (bytes[0] == b'\'' || bytes[0] == b'"') && bytes[s.len() - 1] == bytes[0] {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

/// Map a Chef resource to `(config id, value)`.
fn chef_resource(
    type_: &str,
    name: &str,
    attrs: &BTreeMap<String, String>,
    actions: &[String],
    warnings: &mut Vec<String>,
) -> Option<(String, Value)> {
    let has = |a: &str| actions.iter().any(|x| x == a);
    let res = |pairs: Vec<(&str, Value)>| -> Value {
        let mut m = Mapping::new();
        for (k, v) in pairs {
            m.insert(Value::String(k.to_string()), v);
        }
        Value::Mapping(m)
    };
    // The resource title is the default name; an explicit attr overrides it.
    let rname = |key: &str| attrs.get(key).cloned().unwrap_or_else(|| name.to_string());

    let out = match type_ {
        "package" | "apt_package" | "yum_package" | "dnf_package" => {
            let present = !(has("remove") || has("purge"));
            res(vec![
                ("type", Value::String("os.package".into())),
                ("name", Value::String(rname("package_name"))),
                (
                    "state",
                    Value::String(if present { "present" } else { "absent" }.into()),
                ),
            ])
        }
        "service" => {
            let started = !(has("stop") || has("disable"))
                && (has("start") || has("enable") || actions.is_empty());
            let mut pairs = vec![
                ("type", Value::String("os.service".into())),
                ("name", Value::String(rname("service_name"))),
                (
                    "state",
                    Value::String(if started { "started" } else { "stopped" }.into()),
                ),
            ];
            if has("enable") {
                pairs.push(("enabled", Value::Bool(true)));
            }
            res(pairs)
        }
        "file" | "template" | "cookbook_file" => {
            let Some(content) = attrs.get("content") else {
                warnings.push(format!(
                    "{type_} '{name}': no inline `content` (source/template not supported), skipped"
                ));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.file".into())),
                ("path", Value::String(rname("path"))),
                ("content", Value::String(content.clone())),
            ];
            if let Some(mode) = attrs.get("mode") {
                pairs.push(("mode", Value::String(mode.clone())));
            }
            res(pairs)
        }
        "directory" => res(vec![
            ("type", Value::String("os.directory".into())),
            ("path", Value::String(rname("path"))),
        ]),
        "execute" | "bash" | "script" => res(vec![
            ("type", Value::String("os.command".into())),
            (
                "command",
                Value::String(
                    attrs
                        .get("command")
                        .cloned()
                        .unwrap_or_else(|| name.to_string()),
                ),
            ),
        ]),
        "user" => res(vec![
            ("type", Value::String("os.user".into())),
            ("name", Value::String(rname("username"))),
            (
                "state",
                Value::String(if has("remove") { "absent" } else { "present" }.into()),
            ),
        ]),
        "group" => res(vec![
            ("type", Value::String("os.group".into())),
            ("name", Value::String(rname("group_name"))),
            (
                "state",
                Value::String(if has("remove") { "absent" } else { "present" }.into()),
            ),
        ]),
        "cron" | "cron_d" => {
            // Chef cron fields: minute/hour/day/month/weekday ("*" default).
            let field = |k: &str| attrs.get(k).cloned().unwrap_or_else(|| "*".into());
            let schedule = format!(
                "{} {} {} {} {}",
                field("minute"),
                field("hour"),
                field("day"),
                field("month"),
                field("weekday"),
            );
            res(vec![
                ("type", Value::String("os.cron".into())),
                ("name", Value::String(name.to_string())),
                (
                    "state",
                    Value::String(if has("delete") { "absent" } else { "present" }.into()),
                ),
                ("schedule", Value::String(schedule)),
                (
                    "command",
                    Value::String(
                        attrs
                            .get("command")
                            .cloned()
                            .unwrap_or_else(|| name.to_string()),
                    ),
                ),
            ])
        }
        "sysctl" | "sysctl_param" => {
            let Some(value) = attrs.get("value") else {
                warnings.push(format!("sysctl '{name}': needs `value`, skipped"));
                return None;
            };
            res(vec![
                ("type", Value::String("os.sysctl".into())),
                ("key", Value::String(rname("key"))),
                ("value", Value::String(value.clone())),
            ])
        }
        "python_package" | "pip_package" => {
            let mut pairs = vec![
                ("type", Value::String("os.pip".into())),
                ("name", Value::String(rname("package_name"))),
                (
                    "state",
                    Value::String(
                        if has("remove") || has("purge") {
                            "absent"
                        } else {
                            "present"
                        }
                        .into(),
                    ),
                ),
            ];
            if let Some(v) = attrs.get("version") {
                pairs.push(("version", Value::String(v.clone())));
            }
            res(pairs)
        }
        "git" => {
            // Chef `git`: title=destination, repository/repo=URL, revision=ref.
            let Some(repo) = attrs.get("repository").or_else(|| attrs.get("repo")) else {
                warnings.push(format!("git '{name}': needs `repository`, skipped"));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.git".into())),
                ("repo", Value::String(repo.clone())),
                ("dest", Value::String(rname("destination"))),
            ];
            if let Some(v) = attrs.get("revision").or_else(|| attrs.get("reference")) {
                pairs.push(("version", Value::String(v.clone())));
            }
            res(pairs)
        }
        "hostname" => res(vec![
            ("type", Value::String("os.hostname".into())),
            ("name", Value::String(rname("hostname"))),
        ]),
        "timezone" => res(vec![
            ("type", Value::String("os.timezone".into())),
            ("name", Value::String(rname("timezone"))),
        ]),
        "mount" => {
            // Chef `mount` both mounts (:mount) and persists to fstab (:enable);
            // os.mount does both. Unmount/disable removal is the mounted-only gap.
            if has("umount") || has("unmount") || has("disable") {
                warnings.push(format!(
                    "mount '{name}': umount/disable not supported (os.mount is mounted-only), skipped"
                ));
                return None;
            }
            let (Some(device), Some(fstype)) = (attrs.get("device"), attrs.get("fstype")) else {
                warnings.push(format!(
                    "mount '{name}': needs `device` and `fstype`, skipped"
                ));
                return None;
            };
            let mut pairs = vec![
                ("type", Value::String("os.mount".into())),
                ("src", Value::String(device.clone())),
                ("path", Value::String(rname("mount_point"))),
                ("fstype", Value::String(fstype.clone())),
            ];
            if let Some(opts) = attrs.get("options") {
                pairs.push(("opts", Value::String(opts.clone())));
            }
            res(pairs)
        }
        other => {
            warnings.push(format!(
                "resource type '{other}' ('{name}') not supported, skipped"
            ));
            return None;
        }
    };
    Some((name.to_string(), out))
}

