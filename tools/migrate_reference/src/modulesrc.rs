//! The part of petcow's module-source parser the migration needs (no clone/confine).
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModuleSource {
    Local(String),
    Git {
        url: String,
        subdir: Option<String>,
        reference: Option<String>,
    },
}

pub fn parse(source: &str) -> ModuleSource {
    let s = source.trim();
    if !looks_like_git(s) {
        return ModuleSource::Local(s.to_string());
    }
    let s = s.strip_prefix("git::").unwrap_or(s);
    let (s, reference) = match s.split_once("?ref=") {
        Some((base, r)) if !r.is_empty() => (base, Some(r.to_string())),
        _ => (s, None),
    };
    let normalized;
    let s = if let Some(rest) = s.strip_prefix("github.com/") {
        normalized = format!("https://github.com/{rest}");
        normalized.as_str()
    } else {
        s
    };
    let (url, subdir) = split_subdir(s);
    ModuleSource::Git { url, subdir, reference }
}

fn looks_like_git(s: &str) -> bool {
    s.starts_with("git::")
        || s.starts_with("github.com/")
        || s.starts_with("git@")
        || (s.contains("://") && (s.contains(".git") || s.contains("//") || s.contains("?ref=")))
}

fn split_subdir(s: &str) -> (String, Option<String>) {
    let after_scheme = s.find("://").map(|i| i + 3).unwrap_or(0);
    match s[after_scheme..].find("//") {
        Some(rel) => {
            let at = after_scheme + rel;
            let url = s[..at].to_string();
            let sub = s[at + 2..].trim_matches('/');
            (url, (!sub.is_empty()).then(|| sub.to_string()))
        }
        None => (s.to_string(), None),
    }
}
