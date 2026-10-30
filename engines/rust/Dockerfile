FROM rust:1.99.0
RUN rustup component add rustfmt clippy && rustup target add wasm32-unknown-unknown
RUN cargo install wasm-bindgen-cli --version 0.2.129 --locked
ENV CARGO_TARGET_DIR=/target
WORKDIR /src/engines/rust
RUN arch="$(uname -m)" && \
    case "$arch" in \
      x86_64) sha=2dc9c7813f5375db93d96ead4b78222fcc3e2677bbb832297af4797782a37489 ;; \
      aarch64) sha=89c07ea56faf38d0fbecf36ca8ec0721756716185f265b568e133d427f299bf8 ;; \
      *) echo "no Binaryen checksum for $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/binaryen.tar.gz "https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-$arch-linux.tar.gz" && \
    echo "$sha  /tmp/binaryen.tar.gz" | sha256sum -c - && \
    tar -xz -C /opt -f /tmp/binaryen.tar.gz && rm /tmp/binaryen.tar.gz && \
    ln -s /opt/binaryen-version_133/bin/wasm-opt /usr/local/bin/wasm-opt
