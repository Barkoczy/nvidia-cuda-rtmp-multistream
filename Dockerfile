FROM nvidia/cuda:12.3.1-devel-ubuntu22.04 AS nvidia-base

# Inštalácia NVIDIA knižníc
RUN apt-get update && apt-get install -y --no-install-recommends \
    nvidia-driver-535 \
    cuda-drivers-535 \
    && rm -rf /var/lib/apt/lists/*

# Vytvorenie symlinkov pre NVIDIA knižnice
RUN ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.535 /usr/local/lib/libnvidia-encode.so.1 && \
    ln -sf /usr/lib/x86_64-linux-gnu/libnvcuvid.so.535 /usr/local/lib/libnvcuvid.so.1

# Nastavenie cesty ku knižniciam
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

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
    cuda-nvcc-12-3 \
    cuda-cudart-dev-12-3 \
    libssl-dev \
    openssl \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Vytvorenie symlinkov pre NVIDIA knižnice
RUN ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-encode.so /usr/local/lib/libnvidia-encode.so.1 && \
    ln -sf /usr/lib/x86_64-linux-gnu/libnvcuvid.so /usr/local/lib/libnvcuvid.so.1

# Nastavenie cesty ku knižniciam
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# Build NGINX with RTMP module from source
WORKDIR /tmp
RUN wget https://nginx.org/download/nginx-1.24.0.tar.gz && \
    tar zxf nginx-1.24.0.tar.gz && \
    wget https://github.com/arut/nginx-rtmp-module/archive/master.zip && \
    unzip master.zip && \
    cd nginx-1.24.0 && \
    ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --add-module=../nginx-rtmp-module-master && \
    make -j$(nproc) && \
    make install

# Install NVIDIA SDK Components
RUN wget https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.1.14.0/nv-codec-headers-12.1.14.0.tar.gz \
    && tar xf nv-codec-headers-12.1.14.0.tar.gz \
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

# Create necessary directories
RUN mkdir -p /var/log/nginx && \
    mkdir -p /var/www/html

# Download and setup stat.xsl for RTMP statistics
RUN wget https://raw.githubusercontent.com/arut/nginx-rtmp-module/master/stat.xsl \
    -O /var/www/html/stat.xsl

# Copy configuration files
COPY nginx.conf.template /usr/local/nginx/conf/nginx.conf.template

# Set up configuration files
COPY transcoding-templates /usr/local/nginx/conf/transcoding-templates
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 1935
EXPOSE 8080

# Set working directory
WORKDIR /usr/local/nginx

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]