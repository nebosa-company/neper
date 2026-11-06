//! Error types for PetCow.
//!
//! Great exception handling is a first-class product requirement (FR-14), so
//! errors are specific, carry context (which resource / which expression), and
//! never panic on user input.

use thiserror::Error;

/// The result type used throughout the engine.
pub type Result<T> = std::result::Result<T, PetcowError>;

#[derive(Debug, Error)]
pub enum PetcowError {
    #[error("failed to parse YAML: {0}")]
    Yaml(#[from] serde_yaml::Error),

    #[error("invalid document: {0}")]
    Document(String),

    #[error("in resource '{logical_id}': {message}")]
    Resource { logical_id: String, message: String },

    /// An interpolation/template error, e.g. an unterminated `${` or an
    /// undefined variable reference.
    #[error("interpolation error in '{context}': {message}")]
    Interp { context: String, message: String },

    /// Two expanded resource instances of the **same type** resolved to the same
    /// provider name — this would make (type, name) identity ambiguous (D4), so it
    /// is rejected. (Two instances of *different* types may share a name — the
    /// provider namespaces are distinct — so identity is keyed by (type, name).)
    #[error("name collision: instances '{a}' and '{b}' (type '{type_}') both map to provider name '{name}'")]
    NameCollision {
        a: String,
        b: String,
        type_: String,
        name: String,
    },
}

impl PetcowError {
    pub fn document(msg: impl Into<String>) -> Self {
        PetcowError::Document(msg.into())
    }

    pub fn resource(logical_id: impl Into<String>, message: impl Into<String>) -> Self {
        PetcowError::Resource {
            logical_id: logical_id.into(),
            message: message.into(),
        }
    }

    pub fn interp(context: impl Into<String>, message: impl Into<String>) -> Self {
        PetcowError::Interp {
            context: context.into(),
            message: message.into(),
        }
    }
}
