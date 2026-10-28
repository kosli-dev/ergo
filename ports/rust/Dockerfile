FROM rust:1.99.0
RUN rustup component add rustfmt clippy && rustup target add wasm32-unknown-unknown
RUN cargo install wasm-bindgen-cli --version 0.2.129 --locked
ENV CARGO_TARGET_DIR=/target
WORKDIR /src/ports/rust
RUN arch="$(uname -m)" && curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-$arch-linux.tar.gz" \
    | tar -xz -C /opt && ln -s /opt/binaryen-version_133/bin/wasm-opt /usr/local/bin/wasm-opt
