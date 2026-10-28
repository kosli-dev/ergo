FROM rust:1.99.0
RUN rustup component add rustfmt clippy && rustup target add wasm32-unknown-unknown
ENV CARGO_TARGET_DIR=/target
WORKDIR /src/ports/rust
