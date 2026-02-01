#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Установка WireGuard VPN ===${NC}"

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

# Настройки по умолчанию
DEFAULT_DNS="8.8.8.8, 1.1.1.1"
WG_PORT="51820"
WG_NETWORK="10.0.0.1/24"

echo -e "${BLUE}Настройка параметров WireGuard:${NC}"
read -p "Введите DNS сервера для клиентов [по умолчанию: $DEFAULT_DNS]: " CLIENT_DNS
CLIENT_DNS=${CLIENT_DNS:-$DEFAULT_DNS}

read -p "Введите порт WireGuard [по умолчанию: $WG_PORT]: " CUSTOM_PORT
WG_PORT=${CUSTOM_PORT:-$WG_PORT}

read -p "Введите сеть VPN [по умолчанию: $WG_NETWORK]: " CUSTOM_NETWORK
WG_NETWORK=${CUSTOM_NETWORK:-$WG_NETWORK}

# Запрос публичного IPv4 адреса сервера
echo -e "${YELLOW}Определение публичного IPv4 адреса сервера...${NC}"

# Попробуем разные способы получить IPv4
SERVER_IP=""

# Способ 1: Через curl с принудительным использованием IPv4
if command -v curl &> /dev/null; then
    SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null)
fi

# Способ 2: Если curl не сработал, попробуем wget
if [ -z "$SERVER_IP" ] && command -v wget &> /dev/null; then
    SERVER_IP=$(wget -4 -qO- ifconfig.me 2>/dev/null || wget -4 -qO- ipinfo.io/ip 2>/dev/null)
fi

# Способ 3: Попробуем получить из вывода ip
if [ -z "$SERVER_IP" ]; then
    # Ищем публичный IPv4 в выводе ip route
    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
fi

# Способ 4: Попробуем hostname -I
if [ -z "$SERVER_IP" ]; then
    # Берем только IPv4 адреса из вывода
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {print $i; exit}}')
fi

if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}Не удалось определить публичный IPv4 адрес автоматически.${NC}"
    read -p "Введите публичный IPv4 адрес сервера вручную: " SERVER_IP
else
    echo -e "${GREEN}Определен IPv4 адрес сервера: $SERVER_IP${NC}"
    read -p "Этот IPv4 адрес правильный? (y/n) [y]: " CONFIRM_IP
    CONFIRM_IP=${CONFIRM_IP:-y}
    if [[ ! $CONFIRM_IP =~ ^[Yy]$ ]]; then
        read -p "Введите правильный публичный IPv4 адрес сервера: " SERVER_IP
    fi
fi

# Проверяем, что введен IPv4 адрес
if ! [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Ошибка: '$SERVER_IP' не является валидным IPv4 адресом!${NC}"
    echo -e "${YELLOW}WireGuard на Android не работает с IPv6 адресами.${NC}"
    echo "Пожалуйста, укажите IPv4 адрес (например: 192.168.1.100 или 95.165.123.45)"
    read -p "Введите публичный IPv4 адрес сервера: " SERVER_IP
    if ! [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Неверный IPv4 адрес. Установка прервана.${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Обновление пакетов...${NC}"
apt update && apt upgrade -y

# Установка WireGuard
echo -e "${YELLOW}Установка WireGuard...${NC}"
apt install -y wireguard wireguard-tools qrencode

# Генерация ключей сервера
echo -e "${YELLOW}Генерация ключей сервера...${NC}"
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Определение сетевого интерфейса для маршрутизации
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi

# Создание конфигурации сервера
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $WG_NETWORK
ListenPort = $WG_PORT
PrivateKey = $(cat server_private.key)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE
SaveConfig = true

# Клиенты будут добавляться ниже
EOF

# Настройка проброса пакетов
echo -e "${YELLOW}Настройка проброса пакетов...${NC}"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Настройка firewall
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}Настройка UFW для WireGuard...${NC}"
    ufw allow $WG_PORT/udp
    ufw reload
fi

# Настройка iptables
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

# Сохранение правил iptables
if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4
fi

# Проверка и настройка Nginx
if systemctl is-active --quiet nginx; then
    echo -e "${YELLOW}Обнаружен работающий Nginx${NC}"
    
    # Проверяем, слушает ли Nginx порт WireGuard
    if netstat -tulpn | grep ":$WG_PORT" | grep nginx; then
        echo -e "${YELLOW}Nginx использует порт $WG_PORT. Изменяем порт WireGuard...${NC}"
        NEW_PORT=$((WG_PORT + 1))
        sed -i "s/ListenPort = $WG_PORT/ListenPort = $NEW_PORT/g" /etc/wireguard/wg0.conf
        echo -e "${GREEN}Порт WireGuard изменен на $NEW_PORT${NC}"
        
        # Обновляем правила firewall
        if command -v ufw &> /dev/null; then
            ufw allow $NEW_PORT/udp
            ufw reload
        fi
    else
        echo -e "${GREEN}Конфликтов портов с Nginx не обнаружено${NC}"
    fi
fi

# Создание файла с настройками для клиентов
cat > /etc/wireguard/wg_settings.conf << EOF
# Настройки WireGuard сервера
SERVER_IP=$SERVER_IP
WG_PORT=$(grep "ListenPort" wg0.conf | awk '{print $3}' | head -1)
WG_NETWORK=$WG_NETWORK
CLIENT_DNS=$CLIENT_DNS
EOF

# Запуск и автозагрузка WireGuard
echo -e "${YELLOW}Запуск WireGuard...${NC}"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Проверка статуса
echo -e "${YELLOW}Проверка статуса WireGuard...${NC}"
wg show

echo -e "${GREEN}=== Установка завершена! ===${NC}"
echo -e "${YELLOW}Публичный ключ сервера:${NC}"
cat /etc/wireguard/server_public.key
echo -e "${YELLOW}Настройки клиентов:${NC}"
echo "IPv4 адрес сервера: $SERVER_IP"
echo "DNS серверы: $CLIENT_DNS"
echo "Порт: $(grep "ListenPort" wg0.conf | awk '{print $3}')"
echo -e "${YELLOW}Конфигурация сервера: /etc/wireguard/wg0.conf${NC}"
echo -e "${YELLOW}Для генерации конфигов клиентов используйте скрипт generate_client.sh${NC}"
echo -e "${RED}ВАЖНО: В клиентских конфигах будет использоваться IPv4: $SERVER_IP${NC}"