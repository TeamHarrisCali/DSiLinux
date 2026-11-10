# Build host for DSLinux: Debian Wheezy i386 (the toolchain is 2008 i686 and the 64-bit tools segfault).
# Wheezy is EOL, so apt must use archive.debian.org.
FROM i386/debian:wheezy
RUN echo 'deb http://archive.debian.org/debian wheezy main' > /etc/apt/sources.list \
 && echo 'deb http://archive.debian.org/debian-security wheezy/updates main' >> /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive \
 && apt-get update \
 && apt-get -y --force-yes dist-upgrade \
 && apt-get install -y --force-yes make gcc g++ binutils bison flex gawk libncurses5-dev zlib1g-dev \
      gettext texinfo patch bzip2 wget perl libperl-dev python ca-certificates xz-utils file \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
