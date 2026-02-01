#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Диагностика WireGuard ===${NC}"

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Запуск с sudo...${NC}"
    exec sudo "$0" "$@"
fi

echo -e "${BLUE}1. Проверка статуса службы WireGuard${NC}"
systemctl status wg-quick@wg0 --no-pager -l

echo -e "\n${BLUE}2. Проверка активных интерфейсов WireGuard${NC}"
wg show
wg show all

echo -e "\n${BLUE}3. Проверка сетевых интерфейсов${NC}"
ip addr show wg0 2>/dev/null || echo "Интерфейс wg0 не найден"
ip link show wg0 2>/dev/null || echo "Ссылка wg0 не найдена"

echo -e "\n${BLUE}4. Проверка открытых портов${NC}"
netstat -tulpn | grep -E '(wg|51820|51821)'
ss -tulpn | grep -E '(wg|51820|51821)'

echo -e "\n${BLUE}5. Проверка правил iptables${NC}"
iptables -L -n -v | grep -E '(wg0|ACCEPT|MASQUERADE)'
iptables -t nat -L -n -v

echo -e "\n${BLUE}6. Проверка проброса пакетов${NC}"
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding

echo -e "\n${BLUE}7. Проверка фаервола UFW${NC}"
if command -v ufw &> /dev/null; then
    ufw status numbered
else
    echo "UFW не установлен"
fi

echo -e "\n${BLUE}8. Проверка логов WireGuard${NC}"
journalctl -u wg-quick@wg0 --since "5 minutes ago" --no-pager

echo -e "\n${BLUE}9. Проверка конфигурационных файлов${NC}"
echo "Конфиг сервера (/etc/wireguard/wg0.conf):"
if [ -f "/etc/wireguard/wg0.conf" ]; then
    cat /etc/wireguard/wg0.conf
else
    echo "Файл не найден"
fi

echo -e "\n${BLUE}10. Проверка публичного IP сервера${NC}"
PUBLIC_IP=$(curl -4 -s ifconfig.me)
echo "Публичный IPv4: $PUBLIC_IP"

echo -e "\n${BLUE}11. Проверка маршрутов${NC}"
ip route show
ip route show table all

echo -e "\n${BLUE}12. Проверка DNS${NC}"
cat /etc/resolv.conf

echo -e "\n${BLUE}13. Проверка клиентских конфигов в папке${NC}"
CURRENT_DIR=$(pwd)
CLIENTS_DIR="$CURRENT_DIR/clients_configs"
if [ -d "$CLIENTS_DIR" ]; then
    echo "Содержимое $CLIENTS_DIR:"
    ls -la "$CLIENTS_DIR"
    echo ""
    for conf in "$CLIENTS_DIR"/*.conf; do
        if [ -f "$conf" ]; then
            echo "Конфиг: $(basename "$conf")"
            echo "Endpoint в конфиге:"
            grep "Endpoint" "$conf"
            echo ""
        fi
    done
fi

echo -e "\n${RED}=== Ручная проверка подключения ===${NC}"
echo "1. Проверьте, что порт открыт извне:"
echo "   nc -zv $PUBLIC_IP 51820"
echo "   или"
echo "   telnet $PUBLIC_IP 51820"

echo -e "\n2. Проверьте с другого сервера:"
echo "   wg-quick up /path/to/client.conf"
echo "   ping 10.0.0.1"

echo -e "\n${GREEN}=== Самые частые проблемы ===${NC}"
echo "1. Порт не открыт в облачном фаерволе (AWS, GCP, Azure, DigitalOcean)"
echo "2. Заблокирован провайдером или домашним роутером"
echo "3. Неправильный IPv4 адрес в Endpoint"
echo "4. Конфликт портов с Nginx или другим сервисом"
echo "5. Не включен IP forwarding"
echo "6. Неправильные правила iptables"