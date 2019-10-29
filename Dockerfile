# This is loosely based on ekidd/rust-musl-builder
# https://hub.docker.com/r/ekidd/rust-musl-builder/

# Notable changes:
# - Use Debian "buster" for our build
# - Use musl-cross-make to build a gcc that actually works correctly
# - Fetch upstream source for openssl/zlib rather than unsigned rando tar.gz off the interwebs
# - Alpine provides shared libraries for OpenSSL, etc. We have to build local versions that depend
#   on musl
# - We don't need libpq or Postgres
# - Use OpenSSL 1.1, because that's what's in both Alpine and Debian
# - No mdbook

# Use Debian "buster" as our base image.
FROM debian:buster-slim

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=stable

ARG TARGET_ARCH=armhf
ARG TARGET_TRIPLE=arm-linux-musleabihf
ARG RUST_TARGET=armv7-unknown-linux-musleabihf
# try also: --build-arg="TARGET_ARCH=aarch64" --build-arg="RUST_TARGET=aarch64-unknown-linux-musl" --build-arg="TARGET_TRIPLE=aarch64-linux-musl"

# This needs to match the output of `openssl version -p` in Alpine
ARG OPENSSL_PLATFORM=linux-armv4
# ARG OPENSSL_PLATFORM=linux-aarch64

ADD fixuid/fixuid /usr/local/bin/
RUN chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid && \
    mkdir -p /etc/fixuid && \
    printf "user: rust\ngroup: rust\n" > /etc/fixuid/config.yml

# Make sure we have basic dev tools for building C libraries.  Our goal
# here is to support the musl-libc builds and Cargo builds needed for a
# large selection of the most popular crates.
#
# We also set up a `rust` user by default, in whose account we'll install
# the Rust toolchain.  This user has sudo privileges if you need to install
# any more software.
#

RUN apt-get update && \
    apt-get install -y sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add deb-src lists
RUN sed 's/^deb /deb-src /' /etc/apt/sources.list > /etc/apt/sources.list.d/src.list
RUN dpkg --add-architecture ${TARGET_ARCH}

RUN useradd rust --user-group --create-home --shell /bin/bash --groups sudo

# Allow sudo without a password.
ADD sudoers /etc/sudoers.d/nopasswd

# Run all further code as user `rust`, and create our working directories
# as the appropriate user.
USER rust
WORKDIR /home/rust
RUN mkdir -p /home/rust/src

RUN sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        pkgconf \
        ssh \
        qemu-user-static \
        && \
    apt-get source libssl1.1 zlib1g && rm -rf ~/*.tar.gz ~/*.tar.xz ~/*.asc ~/*.dsc \
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
ENV PATH=/home/rust/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --chown=rust:rust musl-cross-make /home/rust/musl-cross-make/
RUN cd ~/musl-cross-make && \
    TARGET=${TARGET_TRIPLE} make -j8 && \
    sudo TARGET=${TARGET_TRIPLE} make install && \
    rm -r ~/musl-cross-make

RUN echo "Building zlib" && \
    cd ~/zlib-1.2.11.dfsg && \
    CHOST=${TARGET_TRIPLE} ./configure --static --prefix=/usr/local/${TARGET_TRIPLE} && \
    make -j && sudo make install && \
    rm -r ~/zlib-1.2.11.dfsg

# Build a musl-linked library version of OpenSSL using musl-libc.  This is needed by
# the popular Rust `hyper` crate.
#
# We point /usr/local/musl/include/linux at some Linux kernel headers (not
# necessarily the right ones) in an effort to compile OpenSSL 1.1's "engine"
# component. It's possible that this will cause bizarre and terrible things to
# happen. There may be "sanitized" header
RUN echo "Building OpenSSL" && \
    cd ~/openssl-1.1.1?/ && \
    ./Configure -fPIC --cross-compile-prefix=${TARGET_TRIPLE}- \
      --prefix=/usr/local/${TARGET_TRIPLE} -DOPENSSL_NO_SECURE_MEMORY ${OPENSSL_PLATFORM} no-shared no-zlib && \
    make -j8 && \
    sudo make install_sw && \
    rm -r ~/openssl-1.1.1?

ENV OPENSSL_DIR=/usr/local/${TARGET_TRIPLE}/ \
    OPENSSL_INCLUDE_DIR=/usr/local/${TARGET_TRIPLE}/include/ \
    DEP_OPENSSL_INCLUDE=/usr/local/${TARGET_TRIPLE}/include/ \
    OPENSSL_LIB_DIR=/usr/local/${TARGET_TRIPLE}/lib/ \
    OPENSSL_STATIC=1 \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_PATH_${RUST_TARGET}=/usr/local/${TARGET_TRIPLE}/lib/pkgconfig \
    PKG_CONFIG_ALL_STATIC=true \
    LIBZ_SYS_STATIC=1 \
    RUSTFLAGS="-C link_arg=-lgcc"

# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain ${TOOLCHAIN} && \
    rustup target add ${RUST_TARGET} && \
    cargo install cargo-prune cargo-cache && \
    rm -rf ~/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/share && \
# libcompiler_builtins~~~.rlib for some reason defines strong symbols that are in libgcc.a, so we
# are going to remove them surgically. This is terrible.
    find /home/rust/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/armv7-unknown-linux-musleabihf/lib/ \
        -name "libcompiler_builtins-*.rlib" \
        -execdir \
            arm-linux-musleabihf-objcopy \
            --strip-symbol=__sync_fetch_and_add_4 \
            --strip-symbol=__sync_fetch_and_sub_4 \
            {} {}_backup \; \
        -execdir \
            mv -f {}_backup {} \;

ADD cargo-config.toml /home/rust/.cargo/config

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /home/rust/src

ENTRYPOINT ["/usr/local/bin/fixuid"]
