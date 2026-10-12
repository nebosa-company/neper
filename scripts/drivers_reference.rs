// Cargo.toml for this file (offline build, the registry cache has all three):
//   [package] name = "l048ref" version = "0.1.0" edition = "2021"
//   [dependencies] serde = { version = "1", features = ["derive"] }, serde_json = "1", serde_yaml = "0.9"
// Build: cargo build --offline; pass the resulting l048ref.exe to scripts/drivers_vectors.mjs.
// L048 reference: the pure helpers of Petcow's k8s provider, the S3/IAM/EC2/Lightsail providers and the per-host
// transport selection, extracted unchanged (the bodies below are copied from src/provider/k8s/mod.rs,
// src/provider/aws/{s3,iam,ec2,lightsail}.rs and src/transport/mod.rs) behind thin shims for the SDK tag and
// permission builders, ResolvedHost and PetcowError. Reads a JSON array of cases on stdin, writes the answers.
use serde_json::{json, Value as Json};
use serde_yaml::Value;
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io::Read;
use std::rc::Rc;

// ---- shims -------------------------------------------------------------------------------------------------------

#[derive(Debug)]
pub enum PetcowError {
    Document(String),
    Resource { logical_id: String, message: String },
}
impl std::fmt::Display for PetcowError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PetcowError::Document(m) => write!(f, "invalid document: {m}"),
            PetcowError::Resource { logical_id, message } => write!(f, "in resource '{logical_id}': {message}"),
        }
    }
}
impl PetcowError {
    pub fn document(msg: impl Into<String>) -> Self {
        PetcowError::Document(msg.into())
    }
    pub fn resource(logical_id: impl Into<String>, message: impl Into<String>) -> Self {
        PetcowError::Resource { logical_id: logical_id.into(), message: message.into() }
    }
}
type Result<T> = std::result::Result<T, PetcowError>;

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ObservedResource {
    pub name: String,
    pub type_: String,
    pub attributes: BTreeMap<String, Value>,
    pub real_id: Option<String>,
}

mod ec2_types {
    #[derive(Clone)]
    pub struct Tag {
        key: Option<String>,
        value: Option<String>,
    }
    pub struct TagBuilder {
        key: Option<String>,
        value: Option<String>,
    }
    impl Tag {
        pub fn builder() -> TagBuilder {
            TagBuilder { key: None, value: None }
        }
        pub fn key(&self) -> Option<&str> {
            self.key.as_deref()
        }
        pub fn value(&self) -> Option<&str> {
            self.value.as_deref()
        }
    }
    impl TagBuilder {
        pub fn key(mut self, k: impl Into<String>) -> Self {
            self.key = Some(k.into());
            self
        }
        pub fn value(mut self, v: impl Into<String>) -> Self {
            self.value = Some(v.into());
            self
        }
        pub fn build(self) -> Tag {
            Tag { key: self.key, value: self.value }
        }
    }
    #[derive(Clone)]
    pub struct IpRange {
        pub cidr_ip: Option<String>,
    }
    pub struct IpRangeBuilder {
        cidr_ip: Option<String>,
    }
    impl IpRange {
        pub fn builder() -> IpRangeBuilder {
            IpRangeBuilder { cidr_ip: None }
        }
    }
    impl IpRangeBuilder {
        pub fn cidr_ip(mut self, c: impl Into<String>) -> Self {
            self.cidr_ip = Some(c.into());
            self
        }
        pub fn build(self) -> IpRange {
            IpRange { cidr_ip: self.cidr_ip }
        }
    }
    #[derive(Clone)]
    pub struct IpPermission {
        pub ip_protocol: Option<String>,
        pub from_port: Option<i32>,
        pub to_port: Option<i32>,
        pub ip_ranges: Vec<IpRange>,
    }
    pub struct IpPermissionBuilder {
        p: IpPermission,
    }
    impl IpPermission {
        pub fn builder() -> IpPermissionBuilder {
            IpPermissionBuilder { p: IpPermission { ip_protocol: None, from_port: None, to_port: None, ip_ranges: Vec::new() } }
        }
    }
    impl IpPermissionBuilder {
        pub fn ip_protocol(mut self, v: impl Into<String>) -> Self {
            self.p.ip_protocol = Some(v.into());
            self
        }
        pub fn from_port(mut self, v: i32) -> Self {
            self.p.from_port = Some(v);
            self
        }
        pub fn to_port(mut self, v: i32) -> Self {
            self.p.to_port = Some(v);
            self
        }
        pub fn ip_ranges(mut self, r: IpRange) -> Self {
            self.p.ip_ranges.push(r);
            self
        }
        pub fn build(self) -> IpPermission {
            self.p
        }
    }
}
use ec2_types::Tag;

pub mod iam_types {
    pub struct Tag {
        pub key: String,
        pub value: String,
    }
    pub struct TagBuilder {
        key: Option<String>,
        value: Option<String>,
    }
    impl Tag {
        pub fn builder() -> TagBuilder {
            TagBuilder { key: None, value: None }
        }
    }
    impl TagBuilder {
        pub fn key(mut self, k: impl Into<String>) -> Self {
            self.key = Some(k.into());
            self
        }
        pub fn value(mut self, v: impl Into<String>) -> Self {
            self.value = Some(v.into());
            self
        }
        pub fn build(self) -> std::result::Result<Tag, String> {
            Ok(Tag { key: self.key.ok_or("key")?, value: self.value.ok_or("value")? })
        }
    }
}
mod iam {
    pub use crate::iam_types as types;
}

const MANAGED_TAG_KEY: &str = "petcow:managed";
const NAME_TAG_KEY: &str = "petcow:name";

// ---- k8s (src/provider/k8s/mod.rs) -------------------------------------------------------------------------------

pub(crate) const MANAGED_LABEL: &str = "petcow.io/managed";
pub(crate) const NAME_LABEL: &str = "petcow.io/name";

#[derive(Debug, Clone, PartialEq, serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub struct K8sResourceDef {
    #[serde(rename = "type")]
    pub petcow_type: String,
    pub api_version: String,
    pub kind: String,
    #[serde(default = "default_true")]
    pub namespaced: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Namespaced,
    Cluster,
}

impl K8sResourceDef {
    fn new(petcow_type: &str, api_version: &str, kind: &str, scope: Scope) -> K8sResourceDef {
        K8sResourceDef {
            petcow_type: petcow_type.to_string(),
            api_version: api_version.to_string(),
            kind: kind.to_string(),
            namespaced: scope == Scope::Namespaced,
        }
    }
}

pub fn default_defs() -> Vec<K8sResourceDef> {
    vec![
        K8sResourceDef::new("k8s.namespace", "v1", "Namespace", Scope::Cluster),
        K8sResourceDef::new("k8s.config_map", "v1", "ConfigMap", Scope::Namespaced),
        K8sResourceDef::new("k8s.secret", "v1", "Secret", Scope::Namespaced),
        K8sResourceDef::new("k8s.service", "v1", "Service", Scope::Namespaced),
        K8sResourceDef::new(
            "k8s.service_account",
            "v1",
            "ServiceAccount",
            Scope::Namespaced,
        ),
        K8sResourceDef::new(
            "k8s.persistent_volume_claim",
            "v1",
            "PersistentVolumeClaim",
            Scope::Namespaced,
        ),
        K8sResourceDef::new("k8s.deployment", "apps/v1", "Deployment", Scope::Namespaced),
        K8sResourceDef::new(
            "k8s.stateful_set",
            "apps/v1",
            "StatefulSet",
            Scope::Namespaced,
        ),
        K8sResourceDef::new("k8s.daemon_set", "apps/v1", "DaemonSet", Scope::Namespaced),
        K8sResourceDef::new("k8s.job", "batch/v1", "Job", Scope::Namespaced),
        K8sResourceDef::new("k8s.cron_job", "batch/v1", "CronJob", Scope::Namespaced),
        K8sResourceDef::new(
            "k8s.ingress",
            "networking.k8s.io/v1",
            "Ingress",
            Scope::Namespaced,
        ),
        K8sResourceDef::new(
            "k8s.role",
            "rbac.authorization.k8s.io/v1",
            "Role",
            Scope::Namespaced,
        ),
        K8sResourceDef::new(
            "k8s.cluster_role",
            "rbac.authorization.k8s.io/v1",
            "ClusterRole",
            Scope::Cluster,
        ),
    ]
}

fn parse_defs(yaml: &str) -> Result<Vec<K8sResourceDef>> {
    serde_yaml::from_str(yaml).map_err(|e| PetcowError::document(format!("k8s manifest: {e}")))
}

// `all_defs` with the environment's definitions passed in.
fn all_defs_with(extra: Vec<K8sResourceDef>) -> Vec<K8sResourceDef> {
    let mut by_type: BTreeMap<String, K8sResourceDef> = default_defs()
        .into_iter()
        .map(|d| (d.petcow_type.clone(), d))
        .collect();
    for d in extra {
        by_type.insert(d.petcow_type.clone(), d);
    }
    by_type.into_values().collect()
}

fn selector(def: &K8sResourceDef) -> String {
    match def.api_version.split_once('/') {
        Some((group, _)) => format!("{}.{group}", def.kind),
        None => def.kind.clone(),
    }
}

fn ns_args(def: &K8sResourceDef, namespace: &Option<String>) -> Vec<String> {
    match (&def.namespaced, namespace) {
        (true, Some(ns)) => vec!["-n".to_string(), ns.clone()],
        _ => Vec::new(),
    }
}

fn is_managed_item(item: &Json) -> bool {
    item.get("metadata")
        .and_then(|m| m.get("labels"))
        .and_then(|l| l.get(MANAGED_LABEL))
        .and_then(Json::as_str)
        == Some("true")
}

fn is_not_found(stderr: &str) -> bool {
    let s = stderr.to_ascii_lowercase();
    s.contains("notfound") || s.contains("not found")
}

fn apply_manifest(
    def: &K8sResourceDef,
    name: &str,
    attrs: &BTreeMap<String, Value>,
) -> Result<String> {
    let mut obj = serde_json::Map::new();
    for (k, v) in attrs {
        if k == "metadata" || k == "apiVersion" || k == "kind" {
            continue; // set explicitly below
        }
        obj.insert(
            k.clone(),
            serde_json::to_value(v)
                .map_err(|e| PetcowError::document(format!("k8s manifest {k}: {e}")))?,
        );
    }
    obj.insert("apiVersion".into(), Json::String(def.api_version.clone()));
    obj.insert("kind".into(), Json::String(def.kind.clone()));

    let mut meta = match attrs.get("metadata") {
        Some(m) => match serde_json::to_value(m) {
            Ok(Json::Object(o)) => o,
            _ => serde_json::Map::new(),
        },
        None => serde_json::Map::new(),
    };
    meta.insert("name".into(), Json::String(name.to_string()));
    let mut labels = match meta.get("labels") {
        Some(Json::Object(o)) => o.clone(),
        _ => serde_json::Map::new(),
    };
    labels.insert(MANAGED_LABEL.into(), Json::String("true".into()));
    labels.insert(NAME_LABEL.into(), Json::String(name.to_string()));
    meta.insert("labels".into(), Json::Object(labels));
    obj.insert("metadata".into(), Json::Object(meta));

    serde_json::to_string(&Json::Object(obj))
        .map_err(|e| PetcowError::document(format!("k8s manifest encode: {e}")))
}

const LAST_APPLIED: &str = "kubectl.kubernetes.io/last-applied-configuration";

fn observed(type_: &str, json: &Json) -> ObservedResource {
    let name = json
        .get("metadata")
        .and_then(|m| m.get("name"))
        .and_then(|n| n.as_str())
        .unwrap_or_default()
        .to_string();
    let real_id = json
        .get("metadata")
        .and_then(|m| m.get("uid"))
        .and_then(|u| u.as_str())
        .map(str::to_string);
    let last_applied = json
        .get("metadata")
        .and_then(|m| m.get("annotations"))
        .and_then(|a| a.get(LAST_APPLIED))
        .and_then(|v| v.as_str())
        .and_then(|s| serde_json::from_str::<Json>(s).ok());
    let source = last_applied.as_ref().unwrap_or(json);
    let mut attributes = BTreeMap::new();
    if let Json::Object(map) = source {
        for (k, v) in map {
            if matches!(k.as_str(), "apiVersion" | "kind" | "metadata" | "status") {
                continue;
            }
            if let Ok(yv) = serde_yaml::to_value(v) {
                attributes.insert(k.clone(), yv);
            }
        }
    }
    ObservedResource {
        name,
        type_: type_.to_string(),
        attributes,
        real_id,
    }
}

// ---- S3 (src/provider/aws/s3.rs) ---------------------------------------------------------------------------------

fn validate_bucket_name(name: &str) -> Result<()> {
    let bad = |m: &str| {
        Err(PetcowError::resource(
            name,
            format!("invalid S3 bucket name: {m}"),
        ))
    };
    if name.len() < 3 || name.len() > 63 {
        return bad("must be 3–63 characters");
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '.')
    {
        return bad("only lowercase letters, digits, '-' and '.' are allowed");
    }
    if name.starts_with('-') || name.ends_with('-') || name.starts_with('.') || name.ends_with('.')
    {
        return bad("must start and end with a letter or digit");
    }
    Ok(())
}

fn attr_bool(attrs: &BTreeMap<String, Value>, key: &str) -> bool {
    attrs.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn attr_str<'a>(attrs: &'a BTreeMap<String, Value>, key: &str) -> Option<&'a str> {
    attrs.get(key).and_then(Value::as_str)
}

fn desired_user_tags(attrs: &BTreeMap<String, Value>) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    if let Some(Value::Mapping(m)) = attrs.get("tags") {
        for (k, v) in m {
            if let (Some(k), Some(v)) = (k.as_str(), v.as_str()) {
                out.insert(k.to_string(), v.to_string());
            }
        }
    }
    out
}

// ---- IAM (src/provider/aws/iam.rs) -------------------------------------------------------------------------------

pub fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hi = (bytes[i + 1] as char).to_digit(16);
            let lo = (bytes[i + 2] as char).to_digit(16);
            if let (Some(h), Some(l)) = (hi, lo) {
                out.push((h * 16 + l) as u8);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn assume_role_json(attributes: &BTreeMap<String, Value>, name: &str) -> Result<String> {
    match attributes.get("assume_role_policy") {
        Some(Value::String(s)) => Ok(s.clone()),
        Some(v) => serde_json::to_string(v).map_err(|e| {
            PetcowError::resource(name, format!("serializing assume_role_policy: {e}"))
        }),
        None => Err(PetcowError::resource(
            name,
            "aws.iam_role requires 'assume_role_policy'",
        )),
    }
}

fn managed_iam_tags(name: &str, user: &BTreeMap<String, String>) -> Result<Vec<iam::types::Tag>> {
    let mut tags = Vec::new();
    let mut push = |k: &str, v: &str| -> Result<()> {
        tags.push(
            iam::types::Tag::builder()
                .key(k)
                .value(v)
                .build()
                .map_err(|e| PetcowError::resource(name, format!("building tag: {e}")))?,
        );
        Ok(())
    };
    push(MANAGED_TAG_KEY, "true")?;
    push(NAME_TAG_KEY, name)?;
    for (k, v) in user {
        push(k, v)?;
    }
    Ok(tags)
}

fn desired_arns(attributes: &BTreeMap<String, Value>) -> Vec<String> {
    let mut arns: Vec<String> = match attributes.get("managed_policy_arns") {
        Some(Value::Sequence(seq)) => seq
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    };
    arns.sort();
    arns
}

// ---- EC2 (src/provider/aws/ec2.rs) -------------------------------------------------------------------------------

fn managed_tags(name: &str, user: &BTreeMap<String, String>) -> Vec<Tag> {
    let mut tags = vec![
        Tag::builder().key("Name").value(name).build(),
        Tag::builder().key(MANAGED_TAG_KEY).value("true").build(),
        Tag::builder().key(NAME_TAG_KEY).value(name).build(),
    ];
    for (k, v) in user {
        tags.push(Tag::builder().key(k).value(v).build());
    }
    tags
}

fn observed_user_tags(tags: &[Tag]) -> Value {
    let mut m = serde_yaml::Mapping::new();
    for t in tags {
        let (Some(k), Some(v)) = (t.key(), t.value()) else {
            continue;
        };
        if k == MANAGED_TAG_KEY || k == NAME_TAG_KEY || k == "Name" {
            continue;
        }
        m.insert(Value::String(k.to_string()), Value::String(v.to_string()));
    }
    Value::Mapping(m)
}

fn petcow_name(tags: &[Tag]) -> Option<String> {
    tags.iter()
        .find(|t| t.key() == Some(NAME_TAG_KEY))
        .and_then(|t| t.value())
        .map(str::to_string)
}

fn name_or_id(tags: &[Tag], real_id: &str) -> String {
    tags.iter()
        .find(|t| t.key() == Some("Name"))
        .and_then(|t| t.value())
        .filter(|v| !v.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| real_id.to_string())
}

fn unmanaged(type_: &str, tags: &[Tag], real_id: String) -> ObservedResource {
    let mut attributes = BTreeMap::new();
    attributes.insert("tags".to_string(), observed_user_tags(tags));
    ObservedResource {
        name: name_or_id(tags, &real_id),
        type_: type_.to_string(),
        attributes,
        real_id: Some(real_id),
    }
}

fn attr_i64(attrs: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    attrs.get(key).and_then(Value::as_i64)
}

fn attr_str_list(attrs: &BTreeMap<String, Value>, key: &str) -> Vec<String> {
    match attrs.get(key) {
        Some(Value::Sequence(seq)) => seq
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    }
}

fn ingress_permissions(
    name: &str,
    attrs: &BTreeMap<String, Value>,
) -> Result<Vec<ec2_types::IpPermission>> {
    use ec2_types::{IpPermission, IpRange};
    let mut out = Vec::new();
    let Some(Value::Sequence(rules)) = attrs.get("ingress") else {
        return Ok(out);
    };
    for rule in rules {
        let m = rule
            .as_mapping()
            .ok_or_else(|| PetcowError::resource(name, "each ingress rule must be a mapping"))?;
        let proto = m
            .get("protocol")
            .and_then(Value::as_str)
            .ok_or_else(|| PetcowError::resource(name, "ingress rule needs 'protocol'"))?;
        let from = m.get("from_port").and_then(Value::as_i64).unwrap_or(0) as i32;
        let to = m
            .get("to_port")
            .and_then(Value::as_i64)
            .unwrap_or(from as i64) as i32;
        let cidr = m
            .get("cidr")
            .and_then(Value::as_str)
            .ok_or_else(|| PetcowError::resource(name, "ingress rule needs 'cidr'"))?;
        out.push(
            IpPermission::builder()
                .ip_protocol(proto)
                .from_port(from)
                .to_port(to)
                .ip_ranges(IpRange::builder().cidr_ip(cidr).build())
                .build(),
        );
    }
    Ok(out)
}

// ---- Lightsail (src/provider/aws/lightsail.rs) -------------------------------------------------------------------

fn req_attr(attrs: &BTreeMap<String, Value>, key: &str, kind: &str) -> Result<String> {
    opt_attr(attrs, key)
        .ok_or_else(|| PetcowError::resource(kind, format!("missing required attribute '{key}'")))
}

fn opt_attr(attrs: &BTreeMap<String, Value>, key: &str) -> Option<String> {
    attrs.get(key).and_then(Value::as_str).map(str::to_string)
}

fn lightsail_managed_tags(name: &str) -> Vec<Tag> {
    vec![
        Tag::builder().key("petcow:managed").value("true").build(),
        Tag::builder().key("petcow:name").value(name).build(),
    ]
}

// ---- transports (src/transport/mod.rs) ---------------------------------------------------------------------------

pub struct ResolvedHost {
    pub name: String,
    pub address: String,
    pub vars: BTreeMap<String, Value>,
    pub groups: Vec<String>,
}

pub struct CommandResult {
    pub host: String,
    pub stdout: String,
}

pub trait Transport {
    fn name(&self) -> &str;
    fn run(&self, host: &ResolvedHost, command: &str) -> Result<CommandResult>;
}

pub type TransportFactory = Box<dyn Fn(&str) -> Result<Rc<dyn Transport>>>;

pub struct PerHostTransport {
    default_kind: String,
    built: RefCell<BTreeMap<String, Rc<dyn Transport>>>,
    factory: TransportFactory,
}

impl PerHostTransport {
    pub fn new(default_kind: &str, factory: TransportFactory) -> Self {
        PerHostTransport {
            default_kind: default_kind.to_string(),
            built: RefCell::new(BTreeMap::new()),
            factory,
        }
    }

    pub fn kind_for(&self, host: &ResolvedHost) -> String {
        match host.vars.get("transport") {
            Some(serde_yaml::Value::String(s)) if !s.trim().is_empty() => s.trim().to_string(),
            _ => self.default_kind.clone(),
        }
    }

    fn resolve(&self, host: &ResolvedHost) -> Result<Rc<dyn Transport>> {
        let kind = self.kind_for(host);
        if let Some(t) = self.built.borrow().get(&kind) {
            return Ok(Rc::clone(t));
        }
        let t = (self.factory)(&kind)
            .map_err(|e| PetcowError::resource(&host.name, format!("transport '{kind}': {e}")))?;
        self.built.borrow_mut().insert(kind, Rc::clone(&t));
        Ok(t)
    }
}

impl Transport for PerHostTransport {
    fn name(&self) -> &str {
        &self.default_kind
    }

    fn run(&self, host: &ResolvedHost, command: &str) -> Result<CommandResult> {
        self.resolve(host)?.run(host, command)
    }
}

struct Stub(String);
impl Transport for Stub {
    fn name(&self) -> &str {
        &self.0
    }
    fn run(&self, host: &ResolvedHost, _c: &str) -> Result<CommandResult> {
        Ok(CommandResult { host: host.name.clone(), stdout: self.0.clone() })
    }
}

// ---- WinRM (src/transport/winrm.rs): the functions copied unchanged ------------------------------------------------------

#[derive(Clone, Copy)]
pub enum Shell {
    Posix,
    PowerShell,
}

const WINRM_HTTPS_PORT: &str = "5986";
const WINRM_HTTP_PORT: &str = "5985";
const WINRM_PASSWORD_ENV: &str = "PETCOW_WINRM_PASSWORD";

pub fn winrm_args(host: &ResolvedHost, command: &str, shell: Shell) -> Vec<String> {
    vec![
        "-NoProfile".into(),
        "-NonInteractive".into(),
        "-EncodedCommand".into(),
        encode_command(&driver_script(host, command, shell)),
    ]
}

fn driver_script(host: &ResolvedHost, command: &str, shell: Shell) -> String {
    let allow_http = host_bool(host, "winrm_allow_http").unwrap_or(false);
    let port = host_str(host, &["winrm_port", "ansible_port", "port"])
        .unwrap_or_else(|| if allow_http { WINRM_HTTP_PORT } else { WINRM_HTTPS_PORT }.to_string());

    let mut s = String::from("$ErrorActionPreference = 'Stop'\n");
    let mut opts = String::new();

    let mut skips: Vec<&str> = Vec::new();
    if host_bool(host, "winrm_skip_ca_check").unwrap_or(false) {
        skips.push("-SkipCACheck");
    }
    if host_bool(host, "winrm_skip_cn_check").unwrap_or(false) {
        skips.push("-SkipCNCheck");
    }
    if !skips.is_empty() {
        s.push_str(&format!(
            "$sessionOpts = New-PSSessionOption {}\n",
            skips.join(" ")
        ));
        opts.push_str(" -SessionOption $sessionOpts");
    }

    if let Some(user) = host_str(host, &["winrm_user", "ansible_user", "user"]) {
        s.push_str(&format!(
            "$pw = $env:{WINRM_PASSWORD_ENV}\n\
if (-not $pw) {{ throw \"{WINRM_PASSWORD_ENV} is not set, but host var 'winrm_user' names a user to \
authenticate as — set the variable, or remove the user to use the caller's own identity\" }}\n\
$cred = New-Object System.Management.Automation.PSCredential(\
'{user}', (ConvertTo-SecureString $pw -AsPlainText -Force))\n"
        ));
        opts.push_str(" -Credential $cred");
    }

    if let Some(auth) = host_str(host, &["winrm_auth", "winrm_authentication"]) {
        opts.push_str(&format!(" -Authentication {auth}"));
    }
    if !allow_http {
        opts.push_str(" -UseSSL");
    }

    let payload = match shell {
        Shell::PowerShell => command.to_string(),
        Shell::Posix => command.to_string(),
    };
    s.push_str(&format!(
        "$enc = '{}'\n\
Invoke-Command -ComputerName '{}' -Port {}{} -ScriptBlock {{\n  \
powershell -NoProfile -NonInteractive -EncodedCommand $using:enc\n}}\n",
        encode_command(&payload),
        host.address,
        port,
        opts
    ));
    s
}

pub fn encode_command(script: &str) -> String {
    use base64::Engine;
    let utf16: Vec<u8> = script
        .encode_utf16()
        .flat_map(|u| u.to_le_bytes())
        .collect();
    base64::engine::general_purpose::STANDARD.encode(utf16)
}

fn host_str(host: &ResolvedHost, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|k| {
        host.vars.get(*k).and_then(|v| match v {
            Value::String(s) if !s.trim().is_empty() => Some(s.clone()),
            Value::Number(n) => Some(n.to_string()),
            _ => None,
        })
    })
}

fn host_bool(host: &ResolvedHost, key: &str) -> Option<bool> {
    match host.vars.get(key)? {
        Value::Bool(b) => Some(*b),
        Value::String(s) => match s.trim().to_ascii_lowercase().as_str() {
            "true" | "yes" => Some(true),
            "false" | "no" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

// the spawn-error texts of exec() in winrm.rs, with the OS error replaced by the case's message
fn winrm_spawn_error(host: &str, exe: &str, not_found: bool, msg: &str) -> String {
    if not_found {
        PetcowError::resource(host, format!("`{exe}` is not installed (needed for the winrm transport)")).to_string()
    } else {
        PetcowError::resource(host, format!("winrm exec: {msg}")).to_string()
    }
}

fn winrm_program(windows: bool) -> &'static str {
    if windows {
        "powershell"
    } else {
        "pwsh"
    }
}

// ---- local (src/transport/local.rs) -------------------------------------------------------------------------------

fn shell_name(shell: Shell) -> &'static str {
    match shell {
        Shell::Posix => "sh",
        Shell::PowerShell => "powershell",
    }
}

// the program and arguments exec() hands to Command
fn local_argv(command: &str, shell: Shell) -> Vec<String> {
    match shell {
        Shell::PowerShell => ["powershell", "-NoProfile", "-NonInteractive", "-Command", command].iter().map(|s| s.to_string()).collect(),
        Shell::Posix => ["sh", "-c", command].iter().map(|s| s.to_string()).collect(),
    }
}

// ---- SSM (src/transport/ssm.rs): the loop with the two SDK calls scripted ----------------------------------------------

#[derive(PartialEq, Clone)]
pub enum InvStatus {
    Pending,
    InProgress,
    Delayed,
    Success,
    Cancelled,
    Failed,
    TimedOut,
    Cancelling,
    Unknown,
}

fn status_of(s: &str) -> InvStatus {
    match s {
        "Pending" => InvStatus::Pending,
        "InProgress" => InvStatus::InProgress,
        "Delayed" => InvStatus::Delayed,
        "Success" => InvStatus::Success,
        "Cancelled" => InvStatus::Cancelled,
        "Failed" => InvStatus::Failed,
        "TimedOut" => InvStatus::TimedOut,
        "Cancelling" => InvStatus::Cancelling,
        _ => InvStatus::Unknown,
    }
}

const SSM_DOCUMENT: &str = "AWS-RunShellScript";
const SSM_DOCUMENT_PS: &str = "AWS-RunPowerShellScript";

fn document_for(shell: Shell) -> &'static str {
    match shell {
        Shell::Posix => SSM_DOCUMENT,
        Shell::PowerShell => SSM_DOCUMENT_PS,
    }
}

fn instance_id(host: &ResolvedHost) -> Result<String> {
    host.vars
        .get("resource_id")
        .or_else(|| host.vars.get("instance_id"))
        .and_then(serde_yaml::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| {
            PetcowError::resource(
                &host.name,
                "SSM transport needs an instance id — set a `resource_id`/`instance_id` var \
                 or use dynamic inventory (it sets one from discovery)",
            )
        })
}

fn is_terminal(status: &InvStatus) -> bool {
    matches!(
        status,
        InvStatus::Success | InvStatus::Cancelled | InvStatus::Failed | InvStatus::TimedOut
    )
}

#[derive(Clone)]
enum InvError {
    DoesNotExist,
    Other(String),
}

#[derive(Clone)]
struct Invocation {
    status: Option<InvStatus>,
    response_code: i32,
    stdout: Option<String>,
    stderr: Option<String>,
}

struct SsmResult {
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    ok: bool,
}

// `sent`: what send_command answered (an error text, or an optional command id); `answers[i]`: get_command_invocation's
// i-th answer (a call past the script reads as still pending); `calls` counts the invocations asked for
fn ssm_send(
    host: &ResolvedHost,
    sent: &std::result::Result<Option<String>, String>,
    answers: &[std::result::Result<Invocation, InvError>],
    calls: &std::cell::Cell<usize>,
    max_polls: u32,
) -> Result<SsmResult> {
    let _id = instance_id(host)?;

    let sent = sent.clone().map_err(|e| {
        PetcowError::resource(&host.name, format!("ssm send_command: {e}"))
    })?;
    let _command_id = sent
        .ok_or_else(|| PetcowError::resource(&host.name, "send_command returned no command id"))?
        .to_string();

    for _ in 0..max_polls {
        let n = calls.get();
        calls.set(n + 1);
        let inv = answers.get(n).cloned().unwrap_or(Ok(Invocation {
            status: Some(InvStatus::Pending),
            response_code: 0,
            stdout: None,
            stderr: None,
        }));
        let out = match inv {
            Ok(o) => o,
            Err(e) => {
                if matches!(e, InvError::DoesNotExist) {
                    continue;
                }
                let InvError::Other(m) = e else { unreachable!() };
                return Err(PetcowError::resource(
                    &host.name,
                    format!("ssm get_command_invocation: {m}"),
                ));
            }
        };
        match &out.status {
            Some(status) if is_terminal(status) => {
                return Ok(SsmResult {
                    exit_code: Some(out.response_code),
                    stdout: out.stdout.clone().unwrap_or_default(),
                    stderr: out.stderr.clone().unwrap_or_default(),
                    ok: matches!(status, InvStatus::Success),
                });
            }
            _ => continue,
        }
    }

    Err(PetcowError::resource(
        &host.name,
        format!("ssm command timed out after {max_polls} polls"),
    ))
}

// ---- Lightsail list mapping (src/provider/aws/lightsail.rs), SDK getters over the wire JSON -----------------------------

fn s_of<'a>(v: &'a Json, k: &str) -> Option<&'a str> {
    v.get(k).and_then(|x| x.as_str())
}

fn ls_type(kind: &str) -> &'static str {
    match kind {
        "instance" => "aws.lightsail_instance",
        "database" => "aws.lightsail_database",
        _ => "aws.lightsail_domain",
    }
}

fn ls_map_instance(i: &Json) -> Option<ObservedResource> {
    let name = s_of(i, "name")?;
    let mut attrs = BTreeMap::new();
    if let Some(s) = i.get("state").and_then(|s| s_of(s, "name")) {
        attrs.insert("state".into(), Value::String(s.to_string()));
    }
    if let Some(b) = s_of(i, "blueprintId") {
        attrs.insert("blueprint".into(), Value::String(b.to_string()));
    }
    if let Some(b) = s_of(i, "bundleId") {
        attrs.insert("bundle".into(), Value::String(b.to_string()));
    }
    if let Some(az) = i.get("location").and_then(|l| s_of(l, "availabilityZone")) {
        attrs.insert("availability_zone".into(), Value::String(az.to_string()));
    }
    if let Some(ip) = s_of(i, "publicIpAddress") {
        attrs.insert("public_ip".into(), Value::String(ip.to_string()));
    }
    Some(ObservedResource {
        name: name.to_string(),
        type_: ls_type("instance").to_string(),
        attributes: attrs,
        real_id: s_of(i, "arn").map(str::to_string),
    })
}

fn ls_map_database(d: &Json) -> Option<ObservedResource> {
    let name = s_of(d, "name")?;
    let mut attrs = BTreeMap::new();
    if let Some(e) = s_of(d, "engine") {
        attrs.insert("engine".into(), Value::String(e.to_string()));
    }
    if let Some(v) = s_of(d, "engineVersion") {
        attrs.insert("engine_version".into(), Value::String(v.to_string()));
    }
    if let Some(s) = s_of(d, "state") {
        attrs.insert("state".into(), Value::String(s.to_string()));
    }
    if let Some(b) = s_of(d, "relationalDatabaseBlueprintId") {
        attrs.insert("blueprint".into(), Value::String(b.to_string()));
    }
    if let Some(b) = s_of(d, "relationalDatabaseBundleId") {
        attrs.insert("bundle".into(), Value::String(b.to_string()));
    }
    if let Some(m) = s_of(d, "masterDatabaseName") {
        attrs.insert("master_database_name".into(), Value::String(m.to_string()));
    }
    if let Some(u) = s_of(d, "masterUsername") {
        attrs.insert("master_username".into(), Value::String(u.to_string()));
    }
    Some(ObservedResource {
        name: name.to_string(),
        type_: ls_type("database").to_string(),
        attributes: attrs,
        real_id: s_of(d, "arn").map(str::to_string),
    })
}

fn ls_map_domain(dom: &Json) -> Option<ObservedResource> {
    let name = s_of(dom, "name")?;
    let mut attrs = BTreeMap::new();
    let empty = Vec::new();
    let entries = dom.get("domainEntries").and_then(|e| e.as_array()).unwrap_or(&empty);
    attrs.insert(
        "dns_record_count".into(),
        Value::Number(serde_yaml::Number::from(entries.len() as u64)),
    );
    let records: Vec<Value> = entries
        .iter()
        .map(|e| {
            let t = s_of(e, "type").unwrap_or("");
            let n = s_of(e, "name").unwrap_or("");
            let tgt = s_of(e, "target").unwrap_or("");
            Value::String(format!("{t} {n} -> {tgt}"))
        })
        .collect();
    attrs.insert("dns_records".into(), Value::Sequence(records));
    Some(ObservedResource {
        name: name.to_string(),
        type_: ls_type("domain").to_string(),
        attributes: attrs,
        real_id: s_of(dom, "arn").map(str::to_string),
    })
}

// list_instances / list_databases / list_domains with the page fetch scripted: `pages[i]` answers call i (an `error` member
// fails it), and the token each call carried is recorded
fn ls_list_all(kind: &str, pages: &[Json], tokens: &mut Vec<Json>) -> Result<Vec<ObservedResource>> {
    let (call, member) = match kind {
        "instance" => ("get_instances", "instances"),
        "database" => ("get_relational_databases", "relationalDatabases"),
        _ => ("get_domains", "domains"),
    };
    let mut out = Vec::new();
    let mut token: Option<String> = None;
    let mut n = 0;
    loop {
        tokens.push(token.clone().map(Json::from).unwrap_or(Json::Null));
        let page = pages.get(n).cloned().unwrap_or(json!({}));
        n += 1;
        if let Some(e) = page.get("error").and_then(|e| e.as_str()) {
            return Err(PetcowError::resource(ls_type(kind), format!("{call}: {e}")));
        }
        let empty = Vec::new();
        for it in page.get(member).and_then(|m| m.as_array()).unwrap_or(&empty) {
            let mapped = match kind {
                "instance" => ls_map_instance(it),
                "database" => ls_map_database(it),
                _ => ls_map_domain(it),
            };
            if let Some(o) = mapped {
                out.push(o);
            }
        }
        if kind == "domain" {
            break;
        }
        token = page.get("nextPageToken").and_then(|t| t.as_str()).map(str::to_string);
        if token.is_none() {
            break;
        }
    }
    Ok(out)
}

fn ls_is_managed(o: &ObservedResource) -> bool {
    o.name.starts_with(&format!("{}-", "petcow"))
}

// ---- the dispatcher ----------------------------------------------------------------------------------------------

fn attrs_of(v: &Json) -> BTreeMap<String, Value> {
    let mut out = BTreeMap::new();
    if let Json::Object(m) = v {
        for (k, x) in m {
            out.insert(k.clone(), serde_yaml::to_value(x).unwrap());
        }
    }
    out
}

fn yaml_json(v: &Value) -> Json {
    serde_json::to_value(v).unwrap_or(Json::Null)
}

fn def_json(d: &K8sResourceDef) -> Json {
    serde_json::to_value(d).unwrap()
}

fn def_of(v: &Json) -> K8sResourceDef {
    serde_json::from_value(v.clone()).unwrap()
}

fn observed_json(o: &ObservedResource) -> Json {
    let attrs: serde_json::Map<String, Json> = o.attributes.iter().map(|(k, v)| (k.clone(), yaml_json(v))).collect();
    json!({"name": o.name, "type": o.type_, "attributes": attrs, "real_id": o.real_id})
}

fn tag_pairs(tags: &[Tag]) -> Json {
    Json::Array(
        tags.iter()
            .map(|t| json!([t.key().map(Json::from).unwrap_or(Json::Null), t.value().map(Json::from).unwrap_or(Json::Null)]))
            .collect(),
    )
}

fn tags_of(v: &Json) -> Vec<Tag> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|p| {
            let p = p.as_array().unwrap();
            let mut b = Tag::builder();
            if let Some(k) = p[0].as_str() {
                b = b.key(k);
            }
            if let Some(x) = p[1].as_str() {
                b = b.value(x);
            }
            b.build()
        })
        .collect()
}

fn err_json<T>(r: Result<T>, f: impl Fn(T) -> Json) -> Json {
    match r {
        Ok(v) => json!({"ok": true, "v": f(v)}),
        Err(e) => json!({"ok": false, "error": e.to_string()}),
    }
}

fn run_case(c: &Json) -> Json {
    let op = c["op"].as_str().unwrap();
    match op {
        "k8sDefs" => Json::Array(default_defs().iter().map(def_json).collect()),
        "parseDefs" => err_json(parse_defs(c["text"].as_str().unwrap()), |d| Json::Array(d.iter().map(def_json).collect())),
        "allDefs" => err_json(parse_defs(c["text"].as_str().unwrap()), |d| Json::Array(all_defs_with(d).iter().map(def_json).collect())),
        "selector" => {
            let d = def_of(&c["def"]);
            let ns = c.get("ns").and_then(|n| n.as_str()).map(str::to_string);
            json!({"selector": selector(&d), "args": ns_args(&d, &ns)})
        }
        "applyManifest" => {
            let d = def_of(&c["def"]);
            err_json(apply_manifest(&d, c["name"].as_str().unwrap(), &attrs_of(&c["attrs"])), Json::String)
        }
        "observed" => observed_json(&observed(c["type"].as_str().unwrap(), &c["obj"])),
        "managedItem" => Json::Bool(is_managed_item(&c["item"])),
        "notFound" => Json::Bool(is_not_found(c["stderr"].as_str().unwrap())),
        "bucketName" => err_json(validate_bucket_name(c["name"].as_str().unwrap()), |_| Json::Null),
        "attrBool" => Json::Bool(attr_bool(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap())),
        "attrStr" => attr_str(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap()).map(Json::from).unwrap_or(Json::Null),
        "userTags" => serde_json::to_value(desired_user_tags(&attrs_of(&c["attrs"]))).unwrap(),
        "percentDecode" => Json::String(percent_decode(c["s"].as_str().unwrap())),
        "assumeRole" => err_json(assume_role_json(&attrs_of(&c["attrs"]), c["name"].as_str().unwrap()), Json::String),
        "iamTags" => {
            let user: BTreeMap<String, String> = serde_json::from_value(c["user"].clone()).unwrap();
            err_json(managed_iam_tags(c["name"].as_str().unwrap(), &user), |ts| Json::Array(ts.iter().map(|t| json!([t.key, t.value])).collect()))
        }
        "desiredArns" => serde_json::to_value(desired_arns(&attrs_of(&c["attrs"]))).unwrap(),
        "managedTags" => {
            let user: BTreeMap<String, String> = serde_json::from_value(c["user"].clone()).unwrap();
            tag_pairs(&managed_tags(c["name"].as_str().unwrap(), &user))
        }
        "observedUserTags" => yaml_json(&observed_user_tags(&tags_of(&c["tags"]))),
        "petcowName" => petcow_name(&tags_of(&c["tags"])).map(Json::from).unwrap_or(Json::Null),
        "nameOrId" => Json::String(name_or_id(&tags_of(&c["tags"]), c["realId"].as_str().unwrap())),
        "unmanaged" => observed_json(&unmanaged(c["type"].as_str().unwrap(), &tags_of(&c["tags"]), c["realId"].as_str().unwrap().to_string())),
        "attrI64" => attr_i64(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap()).map(Json::from).unwrap_or(Json::Null),
        "attrStrList" => serde_json::to_value(attr_str_list(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap())).unwrap(),
        "ingress" => err_json(ingress_permissions(c["name"].as_str().unwrap(), &attrs_of(&c["attrs"])), |ps| {
            Json::Array(
                ps.iter()
                    .map(|p| json!({"protocol": p.ip_protocol, "from": p.from_port, "to": p.to_port, "cidrs": p.ip_ranges.iter().map(|r| r.cidr_ip.clone()).collect::<Vec<_>>()}))
                    .collect(),
            )
        }),
        "reqAttr" => err_json(req_attr(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap(), c["kind"].as_str().unwrap()), Json::String),
        "optAttr" => opt_attr(&attrs_of(&c["attrs"]), c["key"].as_str().unwrap()).map(Json::from).unwrap_or(Json::Null),
        "lsTags" => tag_pairs(&lightsail_managed_tags(c["name"].as_str().unwrap())),
        "transport" => {
            let known: Vec<String> = serde_json::from_value(c["known"].clone()).unwrap();
            let builds = Rc::new(std::cell::Cell::new(0usize));
            let b = Rc::clone(&builds);
            let t = PerHostTransport::new(
                c["default"].as_str().unwrap(),
                Box::new(move |kind| {
                    b.set(b.get() + 1);
                    if known.iter().any(|k| k == kind) {
                        Ok(Rc::new(Stub(kind.to_string())) as Rc<dyn Transport>)
                    } else {
                        Err(PetcowError::document(format!("unknown transport '{kind}'")))
                    }
                }),
            );
            let mut runs = Vec::new();
            for h in c["hosts"].as_array().unwrap() {
                let mut vars = BTreeMap::new();
                if let Some(x) = h.get("transport") {
                    vars.insert("transport".to_string(), serde_yaml::to_value(x).unwrap());
                }
                let host = ResolvedHost { name: h["name"].as_str().unwrap().to_string(), address: "10.0.0.1".into(), vars, groups: Vec::new() };
                let kind = t.kind_for(&host);
                match t.run(&host, "x") {
                    Ok(r) => runs.push(json!({"kind": kind, "ok": true, "stdout": r.stdout, "host": r.host, "builds": builds.get()})),
                    Err(e) => runs.push(json!({"kind": kind, "ok": false, "error": e.to_string(), "builds": builds.get()})),
                }
            }
            json!({"name": t.name(), "runs": runs})
        }
        "winrmArgs" => {
            let host = ResolvedHost {
                name: "win1".into(),
                address: c["address"].as_str().unwrap().to_string(),
                vars: attrs_of(&c["vars"]),
                groups: Vec::new(),
            };
            let shell = if c["shell"].as_str() == Some("powershell") { Shell::PowerShell } else { Shell::Posix };
            serde_json::to_value(winrm_args(&host, c["command"].as_str().unwrap(), shell)).unwrap()
        }
        "encodeCommand" => Json::String(encode_command(c["s"].as_str().unwrap())),
        "winrmProgram" => Json::String(winrm_program(c["windows"].as_bool().unwrap()).to_string()),
        "winrmError" => Json::String(winrm_spawn_error(
            c["host"].as_str().unwrap(),
            c["exe"].as_str().unwrap(),
            c["notFound"].as_bool().unwrap(),
            c["msg"].as_str().unwrap(),
        )),
        "localArgv" => {
            let shell = if c["shell"].as_str() == Some("powershell") { Shell::PowerShell } else { Shell::Posix };
            serde_json::to_value(local_argv(c["command"].as_str().unwrap(), shell)).unwrap()
        }
        "localError" => {
            let shell = if c["shell"].as_str() == Some("powershell") { Shell::PowerShell } else { Shell::Posix };
            Json::String(PetcowError::resource(c["host"].as_str().unwrap(), format!("local exec via {}: {}", shell_name(shell), c["msg"].as_str().unwrap())).to_string())
        }
        "ssmDocument" => {
            let shell = if c["shell"].as_str() == Some("powershell") { Shell::PowerShell } else { Shell::Posix };
            Json::String(document_for(shell).to_string())
        }
        "ssmTerminal" => Json::Bool(is_terminal(&status_of(c["status"].as_str().unwrap()))),
        "ssmInstanceId" => {
            let host = ResolvedHost { name: c["name"].as_str().unwrap().to_string(), address: String::new(), vars: attrs_of(&c["vars"]), groups: Vec::new() };
            err_json(instance_id(&host), Json::String)
        }
        "ssmRun" => {
            let host = ResolvedHost { name: c["name"].as_str().unwrap().to_string(), address: String::new(), vars: attrs_of(&c["vars"]), groups: Vec::new() };
            let shell = if c["shell"].as_str() == Some("powershell") { Shell::PowerShell } else { Shell::Posix };
            let sent: std::result::Result<Option<String>, String> = match (c["sent"].get("error"), c["sent"].get("id")) {
                (Some(e), _) if e.is_string() => Err(e.as_str().unwrap().to_string()),
                (_, Some(id)) => Ok(id.as_str().map(str::to_string)),
                _ => Ok(None),
            };
            let answers: Vec<std::result::Result<Invocation, InvError>> = c["answers"]
                .as_array()
                .unwrap()
                .iter()
                .map(|a| {
                    if a.get("missing").is_some() {
                        Err(InvError::DoesNotExist)
                    } else if let Some(e) = a.get("error").and_then(|e| e.as_str()) {
                        Err(InvError::Other(e.to_string()))
                    } else {
                        Ok(Invocation {
                            status: a.get("status").and_then(|s| s.as_str()).map(status_of),
                            response_code: a["code"].as_i64().unwrap_or(0) as i32,
                            stdout: a.get("out").and_then(|s| s.as_str()).map(str::to_string),
                            stderr: a.get("err").and_then(|s| s.as_str()).map(str::to_string),
                        })
                    }
                })
                .collect();
            let calls = std::cell::Cell::new(0usize);
            let r = ssm_send(&host, &sent, &answers, &calls, c["maxPolls"].as_u64().unwrap() as u32);
            let mut out = err_json(r, |o| json!({"exit_code": o.exit_code, "stdout": o.stdout, "stderr": o.stderr, "ok": o.ok}));
            out["polls"] = json!(calls.get());
            out["document"] = json!(document_for(shell));
            out
        }
        "lsList" => {
            let kind = c["kind"].as_str().unwrap();
            let pages: Vec<Json> = c["pages"].as_array().unwrap().clone();
            let mut tokens = Vec::new();
            let r = ls_list_all(kind, &pages, &mut tokens);
            let mode = c["mode"].as_str().unwrap();
            let mut out = err_json(r.map(|v| {
                v.into_iter()
                    .filter(|o| match mode {
                        "managed" => ls_is_managed(o),
                        "unmanaged" => !ls_is_managed(o),
                        _ => true,
                    })
                    .collect::<Vec<_>>()
            }), |v| Json::Array(v.iter().map(observed_json).collect()));
            out["tokens"] = Json::Array(tokens);
            out
        }
        other => panic!("unknown op {other}"),
    }
}

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();
    let cases: Vec<Json> = serde_json::from_str(&input).unwrap();
    let out: Vec<Json> = cases.iter().map(run_case).collect();
    println!("{}", serde_json::to_string(&out).unwrap());
}
