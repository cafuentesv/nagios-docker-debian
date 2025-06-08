FROM debian:12-slim

# Información del mantenedor
LABEL maintainer="ca.fuentesv <ca.fuentesv@duocuc.cl>"
LABEL description="Nagios Core 4.x optimized for AWS ECS with EFS"
LABEL version="2.0"

# Variables de entorno
ENV DEBIAN_FRONTEND=noninteractive \
    NAGIOS_HOME=/opt/nagios \
    NAGIOS_USER=nagios \
    NAGIOS_GROUP=nagios \
    NAGIOS_CMDUSER=nagios \
    NAGIOS_CMDGROUP=nagcmd \
    NAGIOSADMIN_USER=cfuentes \
    NAGIOSADMIN_PASS=cfuentes \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    NAGIOS_VERSION=4.5.2 \
    PLUGINS_VERSION=2.4.10

# Configurar repositorios y actualizar sistema
RUN echo "deb http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bookworm-security main" >> /etc/apt/sources.list

# Instalar dependencias esenciales
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    apache2-utils \
    build-essential \
    libgd-dev \
    openssl \
    libssl-dev \
    unzip \
    wget \
    curl \
    gettext \
    autoconf \
    gcc \
    libc6 \
    make \
    php \
    libapache2-mod-php \
    libperl-dev \
    snmp \
    vim-tiny \
    bc \
    gawk \
    dc \
    iputils-ping \
    dnsutils \
    net-tools \
    procps \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Crear usuarios y grupos
RUN groupadd $NAGIOS_GROUP && \
    groupadd $NAGIOS_CMDGROUP && \
    useradd -m -g $NAGIOS_GROUP -G $NAGIOS_CMDGROUP -s /bin/bash $NAGIOS_USER && \
    usermod -a -G $NAGIOS_CMDGROUP $APACHE_RUN_USER

# Crear estructura de directorios para EFS
RUN mkdir -p $NAGIOS_HOME \
             /efs/nagios/etc \
             /efs/nagios/var \
             /efs/nagios/log \
             /efs/nagios/spool \
             /var/run/apache2 \
             /var/lock/apache2 \
             /var/nagios/rw

# Compilar e instalar Nagios Core
WORKDIR /tmp
RUN wget -O nagios-${NAGIOS_VERSION}.tar.gz \
        "https://github.com/NagiosEnterprises/nagioscore/releases/download/nagios-${NAGIOS_VERSION}/nagios-${NAGIOS_VERSION}.tar.gz" && \
    tar xzf nagios-${NAGIOS_VERSION}.tar.gz && \
    cd nagios-${NAGIOS_VERSION} && \
    ./configure \
        --prefix=${NAGIOS_HOME} \
        --exec-prefix=${NAGIOS_HOME} \
        --enable-event-broker \
        --with-command-user=${NAGIOS_CMDUSER} \
        --with-command-group=${NAGIOS_CMDGROUP} \
        --with-nagios-user=${NAGIOS_USER} \
        --with-nagios-group=${NAGIOS_GROUP} \
        --with-httpd-conf=/etc/apache2/sites-enabled && \
    make all && \
    make install && \
    make install-config && \
    make install-commandmode && \
    make install-webconf && \
    cp -R contrib/eventhandlers/ ${NAGIOS_HOME}/libexec/ && \
    chown -R ${NAGIOS_USER}:${NAGIOS_GROUP} ${NAGIOS_HOME}/libexec/eventhandlers

# Compilar e instalar Nagios Plugins
RUN cd /tmp && \
    wget -O nagios-plugins-${PLUGINS_VERSION}.tar.gz \
        "https://github.com/nagios-plugins/nagios-plugins/releases/download/release-${PLUGINS_VERSION}/nagios-plugins-${PLUGINS_VERSION}.tar.gz" && \
    tar xzf nagios-plugins-${PLUGINS_VERSION}.tar.gz && \
    cd nagios-plugins-${PLUGINS_VERSION} && \
    ./configure \
        --prefix=${NAGIOS_HOME} \
        --with-nagios-user=${NAGIOS_USER} \
        --with-nagios-group=${NAGIOS_GROUP} \
        --with-openssl && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/nagios-*

# Limpiar paquetes de compilación
RUN apt-get purge -y build-essential autoconf gcc make wget && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configurar permisos
RUN chown -R ${NAGIOS_USER}:${NAGIOS_GROUP} ${NAGIOS_HOME} && \
    chmod 2755 /var/nagios/rw && \
    chgrp ${NAGIOS_CMDGROUP} /var/nagios/rw

# Crear usuario web para Nagios
RUN htpasswd -bc ${NAGIOS_HOME}/etc/htpasswd.users ${NAGIOSADMIN_USER} ${NAGIOSADMIN_PASS}

# Configurar Apache
RUN a2enmod rewrite cgi headers && \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Script de inicio para ECS
COPY --chmod=755 start-ecs.sh /usr/local/bin/

# Configurar Nagios para comandos externos y EFS
RUN sed -i 's/check_external_commands=0/check_external_commands=1/' ${NAGIOS_HOME}/etc/nagios.cfg && \
    sed -i 's/#command_check_interval=15/command_check_interval=10/' ${NAGIOS_HOME}/etc/nagios.cfg && \
    sed -i 's|command_file=/opt/nagios/var/rw/nagios.cmd|command_file=/var/nagios/rw/nagios.cmd|' ${NAGIOS_HOME}/etc/nagios.cfg && \
    sed -i 's/use_large_installation_tweaks=1/use_large_installation_tweaks=0/' ${NAGIOS_HOME}/etc/nagios.cfg || echo "use_large_installation_tweaks=0" >> ${NAGIOS_HOME}/etc/nagios.cfg

# Exponer puerto
EXPOSE 80

# Health check para ECS
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/nagios/ || exit 1

# Comando por defecto
CMD ["/usr/local/bin/start-ecs.sh"]
