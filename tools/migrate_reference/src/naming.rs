//! Name-based identity (decision D4).
//!
//! PetCow is stateless: it finds the resources it manages by deriving a
//! deterministic provider name from the project + logical id, rather than
//! persisting real resource IDs. The scheme is `petcow-<project>-<logical id>`,
//! with everything sanitized to a safe, lowercase, DNS-ish token set.

/// The fixed prefix that marks a resource as PetCow-managed.
pub const PREFIX: &str = "petcow";

/// Sanitize a single token: lowercase, keep `[a-z0-9-]`, turn every other run of
/// characters into a single `-`, and trim leading/trailing `-`.
///
/// Examples: `Subnet[0]` -> `subnet-0`, `my_VPC!!` -> `my-vpc`.
pub fn sanitize(token: &str) -> String {
    let mut out = String::with_capacity(token.len());
    let mut last_dash = false;
    for ch in token.chars() {
        let c = ch.to_ascii_lowercase();
        if c.is_ascii_alphanumeric() {
            out.push(c);
            last_dash = false;
        } else if !last_dash {
            out.push('-');
            last_dash = true;
        }
    }
    // Trim leading/trailing dashes.
    out.trim_matches('-').to_string()
}

/// Derive the provider-facing name for an instance: `petcow-<project>-<logical id>`.
pub fn resource_name(project: &str, logical_id: &str) -> String {
    let project = sanitize(project);
    let logical = sanitize(logical_id);
    format!("{PREFIX}-{project}-{logical}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_lowercases() {
        assert_eq!(sanitize("MyVPC"), "myvpc");
    }

    #[test]
    fn sanitize_replaces_special_runs_with_single_dash() {
        assert_eq!(sanitize("a__b!!c"), "a-b-c");
        assert_eq!(sanitize("subnet[0]"), "subnet-0");
        assert_eq!(sanitize("foo.bar/baz"), "foo-bar-baz");
    }

    #[test]
    fn sanitize_trims_edge_dashes() {
        assert_eq!(sanitize("[0]"), "0");
        assert_eq!(sanitize("!!hi!!"), "hi");
        assert_eq!(sanitize("---"), "");
    }

    #[test]
    fn sanitize_empty_stays_empty() {
        assert_eq!(sanitize(""), "");
    }

    #[test]
    fn sanitize_unicode_dropped_to_dash() {
        // Non-ASCII alphanumerics are treated as separators (provider names are ASCII).
        assert_eq!(sanitize("café"), "caf");
    }

    #[test]
    fn resource_name_full_scheme() {
        assert_eq!(resource_name("demo", "vpc"), "petcow-demo-vpc");
        assert_eq!(
            resource_name("Demo App", "subnet[us-east-1a]"),
            "petcow-demo-app-subnet-us-east-1a"
        );
    }
}
