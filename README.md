# Nagios Core 4.x Docker Container

## Descripción

Implementación de Nagios Core 4.5.2 en contenedor Docker. Este proyecto proporciona una solución de monitoreo de red robusta y escalable diseñada para entornos de nube.

## Características

- **Nagios Core 4.5.2** con Nagios Plugins 2.4.10
- **Base**: Debian 12 Slim
- **Servidor Web**: Apache2 con módulos PHP

## Especificaciones Técnicas

### Versiones de Software
- Nagios Core: 4.5.2
- Nagios Plugins: 2.4.10
- Sistema Base: Debian 12 (Bookworm)
- Apache: 2.x
- PHP: 8.x

### Estructura de Directorios
```
/opt/nagios/          # Instalación principal de Nagios
/efs/nagios/etc       # Configuraciones persistentes
/efs/nagios/var       # Datos variables
/efs/nagios/log       # Logs del sistema
/efs/nagios/spool     # Cola de trabajos
```

## Instalación y Uso

### Construcción del Contenedor

```bash
docker build -t nagios-core:latest .
```

### Ejecución Local

```bash
docker run -d \
  --name nagios \
  -p 80:80 \
  nagios-core:latest
```

### Acceso a la Interfaz Web

- **URL**: `http://localhost/nagios/`
- **Usuario**: cfuentes
- **Contraseña**: cfuentes

## Configuración para AWS ECS

### Variables de Entorno

| Variable           | Valor           | Descripción               |
|--------------------|-----------------|---------------------------|
| `NAGIOS_HOME`      | `/opt/nagios`   | Directorio base de Nagios |
| `NAGIOS_USER`      | `nagios`        | Usuario del servicio      |
| `NAGIOS_GROUP`     | `nagios`        | Grupo del servicio        |
| `NAGIOSADMIN_USER` | `cfuentes`      | Usuario administrador web |
| `NAGIOSADMIN_PASS` | `cfuentes`      | Contraseña administrador  |

### Montaje de Volúmenes EFS

El contenedor está configurado para utilizar Amazon EFS en las siguientes rutas:
- `/efs/nagios/etc` - Archivos de configuración
- `/efs/nagios/var` - Datos variables
- `/efs/nagios/log` - Archivos de log
- `/efs/nagios/spool` - Cola de trabajos

## Funcionalidades

### Monitoreo Incluido
- Comandos externos habilitados
- Event handlers configurados
- Plugins estándar de Nagios
- Herramientas de red (ping, nslookup, snmp)

### Health Check
El contenedor incluye un health check automático que verifica:
- Disponibilidad del servicio web
- Respuesta en `/nagios/`
- Intervalo: 30 segundos
- Timeout: 10 segundos

## Arquitectura

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
│   ECS Service   │────│   Container  │────│   EFS Vol   │
│                 │    │   Nagios     │    │             │
└─────────────────┘    └──────────────┘    └─────────────┘
         │                       │                  │
         │                       │                  │
    ┌────▼────┐              ┌───▼───┐         ┌────▼────┐
    │   ALB   │              │Apache │         │ Config  │
    │         │              │  :80  │         │  Data   │
    └─────────┘              └───────┘         └─────────┘
```

## Desarrollo

### Estructura del Proyecto
```
.
├── Dockerfile         # Definición del contenedor
├── start-ecs.sh       # Script de inicio para ECS
└── README.md          # Documentación del proyecto
```

### Personalización
Para personalizar la configuración, modifique las variables de entorno en el Dockerfile o monte configuraciones personalizadas en los volúmenes EFS correspondientes.

## Información del Autor

**Mantenedor**: ca.fuentesv 
**Email**: ca.fuentesv@duocuc.cl 
**Institución**: DuocUC 
**Versión**: 2.0

## Licencia

Este proyecto utiliza software open source. Nagios Core está licenciado bajo GPL v2.

## Soporte

Para problemas o consultas relacionadas con esta implementación, contactar al mantenedor del proyecto.
