FROM debian:stable-slim
MAINTAINER Dwelo Engineering <softwaredev@dwelo.com>

ARG USER_ID

ENV CC_DIR /opt/gcc-linaro-arm-linux-gnueabihf-raspbian/bin
ENV CC_armv7-unknown-linux-gnueabihf arm-linux-gnueabihf-gcc-with-link-search
ENV CXX_armv7-unknown-linux-gnueabihf arm-linux-gnueabihf-g++-with-link-search
ENV OBJCOPY $CC_DIR/arm-linux-gnueabihf-objcopy
ENV PKG_CONFIG_ALLOW_CROSS 1
ENV PATH $CC_DIR:$PATH:/home/docker/.cargo/bin

COPY build/arm-linux-gnueabihf-gcc-with-link-search /usr/local/bin/
COPY build/arm-linux-gnueabihf-g++-with-link-search /usr/local/bin/

RUN dpkg --add-architecture armhf \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git file openssh-client pkg-config libssl-dev libc6-dev:armhf libssl-dev:armhf \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

RUN if [[ $(uname -m) == 'x86_64' ]]; then export TOOLCHAIN_SUFFIX='-x64'; fi \
    && curl -sSL https://github.com/raspberrypi/tools/archive/master.tar.gz \
    | tar -zxC /opt tools-master/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian${TOOLCHAIN_SUFFIX} --strip=2 && \
    if [[ ! -d /opt/gcc-linaro-arm-linux-gnueabihf-raspbian ]]; then ln -s /opt/gcc-linaro-arm-linux-gnueabihf-raspbian-x64 /opt/gcc-linaro-arm-linux-gnueabihf-raspbian; fi \
    && addgroup --gid ${USER_ID} docker \
    && adduser --uid ${USER_ID} --ingroup docker --home /home/docker --shell /bin/bash --disabled-password --gecos '' docker

SHELL ["/bin/sh", "-c"]

USER docker:docker

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && ~/.cargo/bin/rustup target add armv7-unknown-linux-gnueabihf \
    && rm -rf ~/.rustup/toolchains/stable-$(uname -m)-unknown-linux-gnu/share \
    && cargo install cargo-deb cargo-prune cargo-cache

COPY build/build-boss-deb-package /usr/local/bin/

WORKDIR /usr/src/app

CMD ["cargo"]
