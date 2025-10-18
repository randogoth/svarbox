FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base packages and enable the dosemu2 PPA
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      gnupg \
      openssh-server \
      busybox-static \
      sudo \
      ca-certificates \
      curl \
      mtools \
      unzip \
      file \
      xauth \
      && add-apt-repository -y ppa:dosemu2/ppa && \
      apt-get install -y --no-install-recommends \
        dosemu2 \
      && rm -rf /var/lib/apt/lists/*

# Provide DOS wrapper, SvarDOS bootstrapper, and service supervisor
COPY scripts/dos-shell /usr/local/bin/dos-shell
COPY scripts/prepare-svardos.sh /usr/local/bin/prepare-svardos
COPY scripts/start-services.sh /usr/local/bin/start-dos-services
RUN chmod +x /usr/local/bin/dos-shell /usr/local/bin/start-dos-services /usr/local/bin/prepare-svardos && \
    echo "/usr/local/bin/dos-shell" >> /etc/shells

# Create sshd runtime directory
RUN mkdir -p /var/run/sshd

# Create dos user
RUN useradd -m -s /usr/local/bin/dos-shell dosuser && \
    mkdir -p /home/dosuser/.ssh && chown -R dosuser:dosuser /home/dosuser && \
    echo "dosuser:dosuser" | chpasswd

# Create directories for allowed DOS files and the C: drive mount
RUN mkdir -p /opt/allowed_repo /cdrive /etc/dos_env /opt/svardos && \
    chown -R dosuser:dosuser /opt/allowed_repo /cdrive

# Download and stage SvarDOS base files
ARG SVARDOS_IMG_URL
ENV SVARDOS_IMG_URL=${SVARDOS_IMG_URL}
RUN /usr/local/bin/prepare-svardos && \
    chown -R dosuser:dosuser /opt/svardos

# Default allowed list (can be overridden with a bind mount)
COPY config/dos_allowed /etc/dos_allowed

# Configure sshd to force command for dosuser
COPY config/sshd_config /etc/ssh/sshd_config

EXPOSE 22 23
CMD ["/usr/local/bin/start-dos-services"]
