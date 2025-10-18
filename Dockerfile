FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openssh-server \
      dosemu2 \
      dosbox-staging \
      busybox-static \
      sudo \
      ca-certificates \
      curl \
      && rm -rf /var/lib/apt/lists/*

# Provide DOS wrapper and service supervisor
COPY dos-shell /usr/local/bin/dos-shell
COPY start-services.sh /usr/local/bin/start-dos-services
RUN chmod +x /usr/local/bin/dos-shell /usr/local/bin/start-dos-services && \
    echo "/usr/local/bin/dos-shell" >> /etc/shells

# Create sshd runtime directory
RUN mkdir -p /var/run/sshd

# Create dos user
RUN useradd -m -s /usr/local/bin/dos-shell dosuser && \
    mkdir -p /home/dosuser/.ssh && chown -R dosuser:dosuser /home/dosuser && \
    echo "dosuser:dosuser" | chpasswd

# Create directories for allowed DOS files and the C: drive mount
RUN mkdir -p /opt/allowed_repo /cdrive /etc/dos_env && \
    chown -R dosuser:dosuser /opt/allowed_repo /cdrive

# Default allowed list (can be overridden with a bind mount)
COPY dos_allowed /etc/dos_allowed

# Configure sshd to force command for dosuser
COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22 23
CMD ["/usr/local/bin/start-dos-services"]
