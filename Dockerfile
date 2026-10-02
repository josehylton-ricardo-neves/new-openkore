# syntax=docker/dockerfile:1.7

# ============================================================
# STAGE 1 - COMPILA XSTOOLS LINUX UMA ÚNICA VEZ
#
# Usa a árvore do bot1 somente como fonte de compilação.
# Em runtime o OpenKore será fornecido por bind mount.
# ============================================================
FROM debian:bookworm-slim AS xstools-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        libcurl4-openssl-dev \
        libncurses-dev \
        libreadline-dev \
        perl \
        perl-modules-5.36 \
        python3 \
        python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/openkore

COPY instances/openkore-bot1/ /build/openkore/

RUN test -f openkore.pl \
    && test -f Makefile \
    && make all \
    && test -f src/auto/XSTools/libXSTools.so

RUN mkdir -p /runtime/xstools \
    && cp -a src/auto/XSTools/libXSTools.so /runtime/xstools/libXSTools.so \
    && cp -a src/auto/XSTools/libXSTools.so /runtime/xstools/XSTools.so


# ============================================================
# STAGE 2 - RUNTIME FINAL
#
# Uma ÚNICA imagem suporta os três modos:
#
#   console -> perl openkore.pl
#   map     -> perl openkore.pl + mapview.pl
#   wx      -> perl openkore.pl --interface=Wx
#
# O OpenKore real NÃO é copiado para a imagem.
# Ele é montado em runtime:
#
#   ./instances/openkore-botN -> /opt/openkore
#
# ============================================================
FROM debian:bookworm-slim AS openkore-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    APP_HOME=/opt/openkore

# Mesmo no modo Console mantemos Wx/Xvfb/VNC/noVNC instalados
# nesta única imagem para permitir trocar de modo sem manter
# imagens Docker diferentes.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        fluxbox \
        fonts-dejavu-core \
        libcarp-assert-perl \
        libclass-data-inheritable-perl \
        libcompress-zlib-perl \
        libcurl4 \
        libexception-class-perl \
        libenum-perl \
        libio-socket-ssl-perl \
        libjson-perl \
        liblist-moreutils-perl \
        libncurses6 \
        libnet-ssleay-perl \
        libreadline8 \
        libterm-readkey-perl \
        libwww-perl \
        libwx-perl \
        libxml-libxml-perl \
        novnc \
        perl \
        tini \
        websockify \
        x11-utils \
        x11vnc \
        xauth \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

# XSTools Linux compilado no estágio anterior.
COPY --from=xstools-builder /runtime/xstools/ /opt/openkore-runtime/xstools/

# Scripts base da imagem.
COPY openkore-entrypoint.sh /usr/local/bin/openkore-entrypoint
COPY openkore-mode.sh /usr/local/bin/openkore-mode

# Remove CRLF caso tenham sido editados no Windows e garante
# permissão de execução dentro da imagem.
RUN sed -i 's/\r$//' \
        /usr/local/bin/openkore-entrypoint \
        /usr/local/bin/openkore-mode \
    && chmod 0755 \
        /usr/local/bin/openkore-entrypoint \
        /usr/local/bin/openkore-mode

WORKDIR /opt/openkore

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/openkore-entrypoint"]

# Modo padrão da imagem. O Compose/okmode pode sobrescrever para
# console, map ou wx sem criar outra imagem.
CMD ["/usr/local/bin/openkore-mode", "wx"]
