FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS nvidia-base

# Install basic dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    git \
    pkg-config \
    yasm \
    nasm \
    cmake \
    libtool \
    libc6 \
    libc6-dev \
    unzip \
    libx264-dev \
    libx265-dev \
    libvpx-dev \
    libfdk-aac-dev \
    libmp3lame-dev \
    libopus-dev \
    autoconf \
    automake \
    libass-dev \
    libfreetype6-dev \
    libsdl2-dev \
    libtheora-dev \
    libtool \
    libva-dev \
    libvdpau-dev \
    libvorbis-dev \
    libxcb1-dev \
    libxcb-shm0-dev \
    libxcb-xfixes0-dev \
    texinfo \
    zlib1g-dev \
    cuda-nvcc-12-8 \
    cuda-cudart-dev-12-8 \
    libssl-dev \
    openssl \
    gettext-base \
    logrotate \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Setting LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# Setup logrotate configuration
COPY broadcaster-logrotate /etc/logrotate.d/broadcaster

# Enable cron service for logrotate
RUN chmod 644 /etc/logrotate.d/broadcaster && \
    echo "0 0 * * * /usr/sbin/logrotate /etc/logrotate.d/broadcaster --force" >> /etc/crontab

# Install NVIDIA SDK Components (nv-codec-headers)
RUN wget https://github.com/FFmpeg/nv-codec-headers/releases/download/n13.0.19.0/nv-codec-headers-13.0.19.0.tar.gz \
    && tar xf nv-codec-headers-13.0.19.0.tar.gz \
    && cd nv-codec-headers-* \
    && make install \
    && cd .. \
    && rm -rf nv-codec-headers*

# Build FFmpeg with NVIDIA support
WORKDIR /tmp/ffmpeg
RUN git clone https://git.ffmpeg.org/ffmpeg.git . \
    && ./configure \
        --prefix=/usr \
        --enable-nonfree \
        --enable-cuda-nvcc \
        --enable-libnpp \
        --extra-cflags=-I/usr/local/cuda/include \
        --extra-ldflags=-L/usr/local/cuda/lib64 \
        --enable-gpl \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libfdk-aac \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libass \
        --enable-libfreetype \
        --enable-libtheora \
        --enable-libvorbis \
        --enable-cuvid \
        --enable-nvenc \
        --enable-nvdec \
        --enable-nonfree \
        --enable-vaapi \
        --enable-vdpau \
        --enable-openssl \
        --enable-cuda \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/ffmpeg

# Build NGINX with RTMP module from source
WORKDIR /tmp
RUN wget https://nginx.org/download/nginx-1.26.1.tar.gz && \
    tar zxf nginx-1.26.1.tar.gz && \
    wget https://github.com/arut/nginx-rtmp-module/archive/master.zip && \
    unzip master.zip && \
    cd nginx-1.26.1 && \
    ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --add-module=../nginx-rtmp-module-master && \
    make -j$(nproc) && \
    make install

# Install YQ for YAML processing
RUN wget https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Create necessary directories
RUN mkdir -p /var/log/nginx && \
    mkdir -p /var/www/html && \
    mkdir -p /tmp/hls && \
    mkdir -p /tmp/hls_pid && \
    mkdir -p /var/log/broadcaster && \
    mkdir -p /etc/broadcaster

# Download and setup stat.xsl for RTMP statistics
RUN wget https://raw.githubusercontent.com/arut/nginx-rtmp-module/master/stat.xsl \
    -O /var/www/html/stat.xsl

# Copy configuration files
COPY profiles.yml /etc/broadcaster/profiles.yml
COPY nginx.conf /usr/local/nginx/conf/nginx.conf
COPY broadcaster /usr/local/bin/broadcaster
COPY hls_transcode /usr/local/bin/hls_transcode
COPY entrypoint.sh /entrypoint.sh

# Create a broadcaster user and set permissions
RUN groupadd -r broadcaster && useradd -r -g broadcaster broadcaster
RUN usermod -a -G video broadcaster

# Set permissions for files and directories
RUN chown -R broadcaster:broadcaster /var/log/broadcaster /etc/broadcaster
RUN chown -R broadcaster:broadcaster /tmp/hls_pid /tmp/hls 
RUN chmod 644 /etc/broadcaster/profiles.yml
RUN chmod 755 /usr/local/bin/broadcaster
RUN chmod 755 /usr/local/bin/hls_transcode
RUN chmod -R 755 /var/log/broadcaster
RUN chmod -R 755 /tmp/hls_pid
RUN chmod -R 755 /tmp/hls

# Set proper permissions
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 1935
EXPOSE 8080

# Set working directory
WORKDIR /usr/local/nginx

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]