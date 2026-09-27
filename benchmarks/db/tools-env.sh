# Source before building the Go and Rust benchmarks on Linux (WSL):  . benchmarks/db/tools-env.sh
# Everything the two toolchains write goes under $NEPER_DB_TOOLS (default /mnt/d/tools): Go's
# toolchain, module cache (shared with Windows) and build cache, and Cargo's registry and builds.
# Rust itself comes from the rustup already installed; only CARGO_HOME moves.
tools=${NEPER_DB_TOOLS:-/mnt/d/tools}
mkdir -p "$tools/gopath" "$tools/gocache/linux" "$tools/cargo-home-linux" "$tools/cargo-target/linux" "$tools/toolhome/config"
export GOROOT="$tools/go-linux"
export GOPATH="$tools/gopath"
export GOMODCACHE="$tools/gopath/pkg/mod"
export GOCACHE="$tools/gocache/linux"
export GOENV="$tools/gopath/env-linux"
export GOTOOLCHAIN=local
export GOFLAGS=-modcacherw
# Go's config (telemetry included) lives in the user config directory.
export XDG_CONFIG_HOME="$tools/toolhome/config"
export CARGO_HOME="$tools/cargo-home-linux"
export CARGO_TARGET_DIR="$tools/cargo-target/linux"
export PATH="$GOROOT/bin:$HOME/.cargo/bin:$PATH"
