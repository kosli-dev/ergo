FROM rust:1.99.0
RUN rustup component add rustfmt clippy && rustup target add wasm32-unknown-unknown
RUN cargo install wasm-bindgen-cli --version 0.2.129 --locked
ENV CARGO_TARGET_DIR=/target
WORKDIR /src/ports/rust
