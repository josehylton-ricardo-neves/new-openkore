#!/bin/sh
set -eu

echo "[VPN-GUARD] Validando bot${BOT_NUMBER:-?} antes de iniciar o Gluetun..."

if /bin/sh /checks/openkore-preflight.sh; then
    echo "[VPN-GUARD] Validação concluída. Iniciando Gluetun."
    exec /gluetun-entrypoint "$@"
fi

code=$?

echo "[VPN-GUARD] BLOQUEADO: Gluetun não será iniciado porque a validação falhou (código $code)." >&2
echo "[VPN-GUARD] Corrija o problema e reinicie este serviço." >&2

# Mantém o container vivo para que:
# - o Docker mostre claramente o serviço;
# - o healthcheck fique unhealthy;
# - depends_on: service_healthy impeça o OpenKore de iniciar;
# - restart: unless-stopped não entre em loop infinito.
while :; do
    sleep 3600
done
