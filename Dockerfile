# Copyright (c) 2022-2025, AllWorldIT.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.


FROM registry.conarx.tech/containers/alpine/3.22 AS ruby-builder


# Latest? - https://www.ruby-lang.org/en/downloads/branches/
# UPDATE IN NEXT SECTION TOO
ENV RUBY_VER=3.4.5


# Copy build patches
COPY patches build/patches


# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/ruby/APKBUILD
	apk add --no-cache \
		autoconf \
		build-base \
		ca-certificates \
		coreutils \
		gdbm-dev \
		gmp-dev \
		jemalloc-dev \
		libffi-dev \
		libucontext-dev \
		linux-headers \
		openssl-dev \
		readline-dev \
		yaml-dev \
		zlib-dev


# Download packages
RUN set -eux; \
	mkdir -p build; \
	cd build; \
	wget "https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz"; \
	tar -xf "ruby-${RUBY_VER}.tar.gz"


# Build and install Ruby
RUN set -eux; \
	cd build; \
	cd "ruby-${RUBY_VER}"; \
# Patching
	for i in ../patches/*.patch; do \
		echo "Applying patch $i..."; \
		patch -p1 < $i; \
	done; \
# -fomit-frame-pointer makes ruby segfault, see gentoo bug #150413
# In many places aliasing rules are broken; play it safe
# as it's risky with newer compilers to leave it as it is.
	export CFLAGS="-fno-omit-frame-pointer -fno-strict-aliasing"; \
	export CPPFLAGS="-fno-omit-frame-pointer -fno-strict-aliasing"; \
	\
# Needed for coroutine stuff
	export LIBS="-lucontext"; \
# ruby saves path to install. we want use $PATH
	export INSTALL=install; \
# install path
	pkgdir="/opt/ruby-$RUBY_VER"; \
# the configure script does not detect isnan/isinf as macros
	export ac_cv_func_isnan=yes; \
	export ac_cv_func_isinf=yes; \
	\
	./configure \
		--prefix="$pkgdir" \
		--sysconfdir=/etc \
		--mandir="$pkgdir/share/man" \
		--infodir="$pkgdir/share/info" \
		--with-sitedir="$pkgdir/lib/site_ruby" \
		--with-search-path="$pkgdir/lib/site_ruby/\$(ruby_ver)/x86_64-linux" \
		--enable-pthread \
		--disable-rpath \
		--enable-shared \
		--disable-install-doc; \
# Build
	nice -n 20 make -j$(nproc) -l 8; \
# Test
	make test; \
# Install
	make SUDO="" install; \
# Remove cruft
	rm -rfv \
		"$pkgdir"/share


RUN set -eux; \
	cd "/opt/ruby-$RUBY_VER"; \
	scanelf --recursive --nobanner --osabi --etype "ET_DYN,ET_EXEC" .  | awk '{print $3}' | xargs \
		strip \
			--remove-section=.comment \
			--remove-section=.note \
			-R .gnu.lto_* -R .gnu.debuglto_* \
			-N __gnu_lto_slim -N __gnu_lto_v1 \
			--strip-unneeded; \
	du -hs .


FROM registry.conarx.tech/containers/alpine/3.22

ARG VERSION_INFO=
LABEL org.opencontainers.image.authors		= "Nigel Kukard <nkukard@conarx.tech>"
LABEL org.opencontainers.image.version		= "3.22"
LABEL org.opencontainers.image.base.name	= "registry.conarx.tech/containers/alpine/3.22"

# Latest? - https://www.ruby-lang.org/en/downloads/branches/
ENV RUBY_VER=3.4.5

ENV FDC_DISABLE_SUPERVISORD=true
ENV FDC_QUIET=true

# Copy in built binaries
COPY --from=ruby-builder /opt /opt/

# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/ruby/APKBUILD
	apk add --no-cache \
		ca-certificates \
		gdbm \
		gmp \
		libffi \
		libucontext \
		openssl \
		readline \
		yaml \
		zlib

# Adjust flexible docker containers as this is not a daemon-based image
RUN set -eux; \
	# Set up this language so it can be pulled into other images
	echo "# Ruby $RUBY_VER" > "/opt/ruby-$RUBY_VER/ld-musl-x86_64.path"; \
	echo "/opt/ruby-$RUBY_VER/lib" >> "/opt/ruby-$RUBY_VER/ld-musl-x86_64.path"; \
	echo "/opt/ruby-$RUBY_VER/bin" > "/opt/ruby-$RUBY_VER/PATH"; \
	# Set up library search path
	cat "/opt/ruby-$RUBY_VER/ld-musl-x86_64.path" >> /etc/ld-musl-x86_64.path; \
	# Remove things we dont need
	rm -f /usr/local/share/flexible-docker-containers/tests.d/40-crond.sh; \
	rm -f /usr/local/share/flexible-docker-containers/tests.d/90-healthcheck.sh

RUN set -eux; \
	true "Test"; \
# Test
	export PATH="$(cat /opt/ruby-*/PATH):$PATH"; \
	ruby -e "puts 'Hello, World!'"; \
	ruby -e "puts RUBY_VERSION"; \
	du -hs /opt/ruby-$RUBY_VER

# Ruby
COPY usr/local/share/flexible-docker-containers/init.d/41-ruby.sh /usr/local/share/flexible-docker-containers/init.d
COPY usr/local/share/flexible-docker-containers/tests.d/41-ruby.sh /usr/local/share/flexible-docker-containers/tests.d
RUN set -eux; \
	true "Flexible Docker Containers"; \
	if [ -n "$VERSION_INFO" ]; then echo "$VERSION_INFO" >> /.VERSION_INFO; fi; \
	true "Permissions"; \
	fdc set-perms