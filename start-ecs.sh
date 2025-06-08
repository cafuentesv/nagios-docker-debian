#!/bin/bash
set -e

echo "=== Iniciando Nagios Core en AWS ECS ==="

# Función para manejar señales de terminación
cleanup() {
    echo "Recibida señal de terminación, deteniendo servicios..."
    
    # Detener Apache
    if [ -n "$APACHE_PID" ]; then
        kill -TERM "$APACHE_PID" 2>/dev/null || true
    fi
    
    # Detener Nagios
    if [ -n "$NAGIOS_PID" ]; then
        kill -TERM "$NAGIOS_PID" 2>/dev/null || true
    fi
    
    # Esperar a que terminen
    wait
    exit 0
}

# Capturar señales
trap cleanup SIGTERM SIGINT

# Función para sincronizar configuración con EFS
sync_efs_config() {
    echo "Sincronizando configuración con EFS..."
    
    # Si es la primera vez, copiar configuración inicial a EFS
    if [ ! -f "/efs/nagios/etc/nagios.cfg" ]; then
        echo "Primera ejecución detectada, copiando configuración inicial a EFS..."
        cp -r /opt/nagios/etc/* /efs/nagios/etc/
        cp -r /opt/nagios/var/* /efs/nagios/var/ 2>/dev/null || true
    fi
    
    # Crear enlaces simbólicos
    rm -rf /opt/nagios/etc
    rm -rf /opt/nagios/var
    ln -s /efs/nagios/etc /opt/nagios/etc
    ln -s /efs/nagios/var /opt/nagios/var
    
    # Asegurar que los directorios de log existan
    mkdir -p /efs/nagios/log
    mkdir -p /efs/nagios/spool
    mkdir -p /efs/nagios/var/rw
    
    # Enlaces para logs
    rm -rf /var/log/nagios
    ln -s /efs/nagios/log /var/log/nagios
}

# Función para configurar permisos
set_permissions() {
    echo "Configurando permisos..."
    
    # Permisos para directorios EFS
    chown -R nagios:nagios /efs/nagios
    chown nagios:nagcmd /var/nagios/rw
    chmod 2755 /var/nagios/rw
    
    # Permisos para Apache
    chown -R www-data:www-data /var/run/apache2 2>/dev/null || true
    chown -R www-data:www-data /var/lock/apache2 2>/dev/null || true
    
    # Asegurar que el archivo de comandos sea escribible
    if [ -e /efs/nagios/var/rw/nagios.cmd ]; then
        chmod 660 /efs/nagios/var/rw/nagios.cmd
        chown nagios:nagcmd /efs/nagios/var/rw/nagios.cmd
    fi
}

# Función para verificar configuración
verify_config() {
    echo "Verificando configuración de Nagios..."
    if ! /opt/nagios/bin/nagios -v /opt/nagios/etc/nagios.cfg; then
        echo "ERROR: Configuración de Nagios inválida"
        exit 1
    fi
}

# Función para monitorear procesos
monitor_processes() {
    while true; do
        # Verificar Apache
        if [ -n "$APACHE_PID" ] && ! kill -0 "$APACHE_PID" 2>/dev/null; then
            echo "Apache se ha detenido inesperadamente"
            exit 1
        fi
        
        # Verificar Nagios
        if [ -n "$NAGIOS_PID" ] && ! kill -0 "$NAGIOS_PID" 2>/dev/null; then
            echo "Nagios se ha detenido inesperadamente"
            exit 1
        fi
        
        sleep 10
    done
}

# Sincronizar con EFS
sync_efs_config

# Configurar permisos
set_permissions

# Verificar configuración
verify_config

# Crear directorios necesarios para Apache
mkdir -p /var/run/apache2
mkdir -p /var/lock/apache2

# Configurar variables de entorno para Apache
export APACHE_RUN_USER=www-data
export APACHE_RUN_GROUP=www-data
export APACHE_PID_FILE=/var/run/apache2/apache2.pid
export APACHE_RUN_DIR=/var/run/apache2
export APACHE_LOCK_DIR=/var/lock/apache2
export APACHE_LOG_DIR=/var/log/apache2

# Iniciar Apache en segundo plano
echo "Iniciando Apache..."
/usr/sbin/apache2ctl -D FOREGROUND &
APACHE_PID=$!

# Esperar a que Apache esté listo
sleep 5

# Verificar que Apache esté corriendo
if ! kill -0 "$APACHE_PID" 2>/dev/null; then
    echo "ERROR: Apache no pudo iniciarse"
    exit 1
fi

echo "Apache iniciado correctamente (PID: $APACHE_PID)"

# Iniciar Nagios en segundo plano
echo "Iniciando Nagios..."
su - nagios -s /bin/bash -c "/opt/nagios/bin/nagios /opt/nagios/etc/nagios.cfg" &
NAGIOS_PID=$!

# Esperar a que Nagios esté listo
sleep 5

# Verificar que Nagios esté corriendo
if ! kill -0 "$NAGIOS_PID" 2>/dev/null; then
    echo "ERROR: Nagios no pudo iniciarse"
    exit 1
fi

echo "Nagios iniciado correctamente (PID: $NAGIOS_PID)"
echo ""
echo "=== Servicios iniciados correctamente ==="
echo "Acceso web: http://localhost/nagios"
echo "Usuario: cfuentes"
echo "Contraseña: cfuentes"
echo ""

# Iniciar monitoreo de procesos en segundo plano
monitor_processes &
MONITOR_PID=$!

# Esperar a que cualquier proceso termine
wait -n $APACHE_PID $NAGIOS_PID $MONITOR_PID

# Si llegamos aquí, algo falló
echo "Un proceso ha terminado inesperadamente"
cleanup