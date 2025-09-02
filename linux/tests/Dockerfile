# Docker container for testing bash functions
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages and tools used by bash functions
RUN apt-get update && apt-get install -y \
    # Core utilities
    bash \
    curl \
    wget \
    git \
    vim \
    nano \
    tree \
    htop \
    bc \
    jq \
    unzip \
    zip \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    p7zip-full \
    # Network tools
    net-tools \
    iputils-ping \
    dnsutils \
    nmap \
    netcat-openbsd \
    telnet \
    traceroute \
    # System monitoring
    lsof \
    strace \
    tcpdump \
    iotop \
    # Clipboard and display tools
    xclip \
    xsel \
    # Image processing
    imagemagick \
    exiftool \
    tesseract-ocr \
    tesseract-ocr-eng \
    # PDF tools
    poppler-utils \
    ghostscript \
    # Security tools
    clamav \
    clamav-daemon \
    gnupg \
    age \
    openssl \
    # Transfer tools
    rsync \
    magic-wormhole \
    rclone \
    # Development tools
    nodejs \
    npm \
    python3 \
    python3-pip \
    # Docker tools (for nested Docker testing)
    docker.io \
    docker-compose \
    # AWS CLI
    awscli \
    # Additional utilities
    fd-find \
    ripgrep \
    bat \
    exa \
    fzf \
    && rm -rf /var/lib/apt/lists/*

# Install additional Python packages
RUN pip3 install --no-cache-dir \
    requests \
    beautifulsoup4 \
    PyPDF2 \
    Pillow

# Create test user
RUN useradd -m -s /bin/bash testuser && \
    usermod -aG sudo testuser && \
    echo 'testuser:testpass' | chpasswd

# Create test directories
RUN mkdir -p /home/testuser/test_files /home/testuser/test_output /home/testuser/test_logs

# Copy bash function files
COPY .bash_* /home/testuser/
COPY .bashrc /home/testuser/

# Copy test files and scripts
COPY tests/ /home/testuser/tests/

# Set ownership
RUN chown -R testuser:testuser /home/testuser/

# Create some test files for testing
RUN su - testuser -c "mkdir -p /home/testuser/test_files" && \
    echo "This is a test file" > /home/testuser/test_files/test.txt && \
    echo "Another test file for searching" > /home/testuser/test_files/search_test.txt && \
    echo '{"name": "test", "value": 123}' > /home/testuser/test_files/test.json && \
    echo "#!/bin/bash\necho 'Hello from script'" > /home/testuser/test_files/test_script.sh && \
    chmod +x /home/testuser/test_files/test_script.sh

# Switch to test user
USER testuser
WORKDIR /home/testuser

# Source bash functions in bashrc
RUN echo "# Source all bash function files" >> ~/.bashrc && \
    echo "for file in ~/.bash_*; do" >> ~/.bashrc && \
    echo "    [ -r \"\$file\" ] && [ -f \"\$file\" ] && source \"\$file\"" >> ~/.bashrc && \
    echo "done" >> ~/.bashrc

# Set default command
CMD ["/bin/bash"]
