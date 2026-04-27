#!/usr/bin/env python3

import subprocess
import sys
import os

# ===== UTILIDADES =====

def run(cmd, check=True):
    print(f"[INFO] Ejecutando: {cmd}")
    result = subprocess.run(cmd, shell=True)
    if check and result.returncode != 0:
        print(f"[ERROR] Falló comando: {cmd}")
        sys.exit(1)

def command_exists(cmd):
    return subprocess.call(f"type {cmd}", shell=True,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL) == 0

def require_root():
    if os.geteuid() != 0:
        print("[ERROR] Ejecuta este script con sudo")
        sys.exit(1)

# ===== INSTALACIÓN BASE =====

def install_base_dependencies():
    run("apt-get update")
    run("apt-get install -y ca-certificates curl gnupg lsb-release git")

# ===== DOCKER =====

def install_docker():
    if command_exists("docker"):
        print("[INFO] Docker ya está instalado, omitiendo...")
        return

    print("[INFO] Instalando Docker...")

    run("install -m 0755 -d /etc/apt/keyrings")

    run("curl -fsSL https://download.docker.com/linux/ubuntu/gpg | "
        "gpg --dearmor -o /etc/apt/keyrings/docker.gpg")

    run("chmod a+r /etc/apt/keyrings/docker.gpg")

    run(
        'echo "deb [arch=$(dpkg --print-architecture) '
        'signed-by=/etc/apt/keyrings/docker.gpg] '
        'https://download.docker.com/linux/ubuntu '
        '$(. /etc/os-release && echo $VERSION_CODENAME) stable" '
        '> /etc/apt/sources.list.d/docker.list'
    )

    run("apt-get update")

    run(
        "apt-get install -y docker-ce docker-ce-cli containerd.io "
        "docker-buildx-plugin docker-compose-plugin"
    )

    run("systemctl enable docker")
    run("systemctl start docker")

# ===== GITHUB CLI =====

def install_github_cli():
    if command_exists("gh"):
        print("[INFO] GitHub CLI ya instalado, omitiendo...")
        return

    print("[INFO] Instalando GitHub CLI...")

    run(
        "curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | "
        "dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
    )

    run(
        'echo "deb [arch=$(dpkg --print-architecture) '
        'signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] '
        'https://cli.github.com/packages stable main" '
        '> /etc/apt/sources.list.d/github-cli.list'
    )

    run("apt-get update")
    run("apt-get install -y gh")

# ===== PERMISOS =====

def configure_user_permissions():
    user = os.getenv("SUDO_USER") or os.getenv("USER")

    if not user:
        print("[ERROR] No se pudo determinar el usuario")
        sys.exit(1)

    print(f"[INFO] Agregando usuario '{user}' al grupo docker...")
    run(f"usermod -aG docker {user}")

    print("[WARN] Necesitas cerrar sesión y volver a entrar para aplicar permisos")

# ===== VALIDACIÓN =====

def validate_installation():
    print("[INFO] Validando instalación de Docker...")

    run("docker --version")
    run("docker compose version")

    print("[INFO] Ejecutando contenedor de prueba...")
    run("docker run --rm hello-world", check=False)

# ===== MAIN =====

def main():
    require_root()

    print("🚀 Configuración de host para Docker iniciada...\n")

    install_base_dependencies()
    install_docker()
    install_github_cli()
    configure_user_permissions()
    validate_installation()

    print("\n✅ Configuración completada con éxito")

if __name__ == "__main__":
    main()
