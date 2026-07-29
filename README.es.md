# get-antigravity

[🇬🇧 Read in English](README.md)

Instalador de **Google Antigravity** para Linux. Todos los productos en un solo comando.

## Instalación rápida

### Modo interactivo (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/jairuque/get-antigravity/main/install.sh -o install.sh
bash install.sh
```

### Una línea (producto específico)

```bash
# Instalar Antigravity IDE para el usuario actual
curl -fsSL https://raw.githubusercontent.com/jairuque/get-antigravity/main/install.sh | bash -s -- --install ide --user

# Instalar CLI en todo el sistema
curl -fsSL https://raw.githubusercontent.com/jairuque/get-antigravity/main/install.sh | sudo bash -s -- --install cli

# Instalar todo
curl -fsSL https://raw.githubusercontent.com/jairuque/get-antigravity/main/install.sh | bash -s -- --user all
```

### Instalación en todo el sistema (requiere sudo)

```bash
sudo bash install.sh --install ide
```

## Productos soportados

| Producto | Descripción | Binario |
|---|---|---|
| **Antigravity 2.0** | Aplicación de escritorio | `/usr/local/bin/antigravity` |
| **Antigravity IDE** | Editor de código (fork de VS Code) | `/usr/local/bin/antigravity-ide` |
| **Antigravity CLI** | Agente de terminal (`agy`) | `~/.local/bin/agy` |
| **Antigravity SDK** | SDK para Python | `pipx` / `pip install` |

## Opciones

```
Uso: install.sh [OPCIONES] [PRODUCTOS...]

Productos: antigravity, ide, cli, sdk, all

Opciones:
  --install PRODUCTO   Instalar un producto (se puede repetir)
  --update             Actualizar todos los productos instalados
  --uninstall PRODUCTO Desinstalar un producto
  --list               Listar versiones instaladas vs disponibles
  --dry-run            Previsualizar sin ejecutar cambios
  --force              Forzar reinstalación aunque esté actualizado
  --user               Instalar solo para el usuario actual (no requiere root)
  --keep-previous N    Conservar N versiones anteriores de respaldo (defecto: 1)
  --verbose            Salida detallada para depuración
  --quiet              Salida mínima
  --help               Mostrar esta ayuda
```

## Distribuciones soportadas

| Distribución | Notas |
|---|---|
| Ubuntu 20.04+ | Soporte completo |
| Debian 11+ | Soporte completo (Debian 10: glibc 2.28 mínimo) |
| Fedora 36+ | Soporte completo |
| RHEL 8+ / Rocky 8+ | Soporte completo (necesita EPEL para pip) |
| Arch Linux / Manjaro | Soporte completo (nombres de paquetes distintos) |
| openSUSE Leap 15.4+ | Soporte completo |
| openSUSE Tumbleweed | Soporte completo |
| Linux Mint 20+ | Soporte completo |
| **Alpine Linux** | **No soportado** para apps de escritorio (musl libc). CLI y SDK funcionan. |

Todas las distribuciones requieren **glibc >= 2.28** para los productos de escritorio.

## Rutas de instalación

| Modo | Binarios | Escritorio/Iconos | Datos de aplicación |
|---|---|---|---|
| Sistema (`sudo`) | `/usr/local/bin/` | `/usr/share/` | `/opt/` |
| Usuario (`--user`) | `~/.local/bin/` | `~/.local/share/` | `~/.local/opt/` |

## Verificación de integridad

Al ejecutarse desde un archivo descargado, el script verifica automáticamente su hash SHA256 antes de ejecutarse. Esta verificación se omite en modo pipe (`curl | bash`).

## Dependencias automáticas

Si faltan `curl`, `tar` o `python3`, el script detecta el gestor de paquetes del sistema (`apt`, `dnf`, `pacman`, `zypper`) y las instala automáticamente si se ejecuta con `sudo`.

## Requisitos

- **bash** (viene por defecto en todas las distribuciones soportadas)
- **glibc >= 2.28** (para productos de escritorio: Antigravity 2.0 e IDE)
- Conexión a internet para descargar los productos

## Licencia

MIT — ver [LICENSE](LICENSE)
