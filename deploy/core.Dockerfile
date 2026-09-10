# Supply immutable base references; the build script rejects tags without digests.
ARG RUST_IMAGE
ARG BASE_IMAGE
FROM ${RUST_IMAGE} AS build
WORKDIR /build
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY services/core services/core
RUN cargo build --release --locked -p starbase-core
FROM ${BASE_IMAGE}
COPY --from=build /build/target/release/starbase-core /usr/local/bin/starbase-core
USER 10001:10001
WORKDIR /tmp
ENTRYPOINT ["/usr/local/bin/starbase-core"]
