//! InfiniLM-SVC Library
//! Shared modules for router, registry, and babysitter binaries

// Router modules (used by infini-router binary)
pub mod config;
pub mod handlers;
pub mod models;
pub mod proxy;
pub mod registry;
pub mod router;
pub mod utils;

// Babysitter module (used by infini-babysitter binary)
pub mod babysitter;

// Re-export commonly used babysitter types for convenience
pub use babysitter::BabysitterState;
