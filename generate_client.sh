#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Генерация конфига WireGuard клиента ===${NC}"

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Запуск с sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Определяем текущую директорию (откуда запущен скрипт)
CURRENT_DIR=$(pwd)
CLIENTS_CONFIGS_DIR="$CURRENT_DIR/clients_configs"

# Создаем папку для конфигов, если не существует
mkdir -p "$CLIENTS_CONFIGS_DIR"
chmod 755 "$CLIENTS_CONFIGS_DIR"

# Переход в директорию WireGuard
cd /etc/wireguard || exit 1

# Проверка существования конфига сервера
if [ ! -f "wg0.conf" ]; then
    echo -e "${RED}Конфигурация сервера не найдена! Сначала запустите install_wireguard.sh${NC}"
    exit 1
fi

# Загрузка настроек
if [ -f "wg_settings.conf" ]; then
    source wg_settings.conf
else
    # Настройки по умолчанию
    CLIENT_DNS="8.8.8.8, 1.1.1.1"
    WG_NETWORK="10.0.0.1/24"
fi

# Определение IPv4 адреса сервера
if [ -z "$SERVER_IP" ] || [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
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
        SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
    fi
    
    # Способ 4: Попробуем hostname -I
    if [ -z "$SERVER_IP" ]; then
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
fi

# Проверяем, что у нас IPv4 адрес
if ! [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Ошибка: '$SERVER_IP' не является валидным IPv4 адресом!${NC}"
    echo -e "${YELLOW}WireGuard на Android не работает с IPv6 адресами.${NC}"
    echo "Пожалуйста, укажите IPv4 адрес (например: 192.168.1.100 или 95.165.123.45)"
    read -p "Введите публичный IPv4 адрес сервера: " SERVER_IP
    if ! [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Неверный IPv4 адрес. Генерация прервана.${NC}"
        exit 1
    fi
fi

# Определение порта из конфига сервера
if [ -z "$WG_PORT" ]; then
    WG_PORT=$(grep "ListenPort" wg0.conf | awk '{print $3}')
    if [ -z "$WG_PORT" ]; then
        WG_PORT="51820"
    fi
fi

echo -e "${BLUE}Текущие настройки:${NC}"
echo "IPv4 сервера: $SERVER_IP"
echo "Порт: $WG_PORT"
echo "DNS: $CLIENT_DNS"
echo "Сеть: $WG_NETWORK"
echo "Папка для конфигов: $CLIENTS_CONFIGS_DIR"
echo ""

# Запрос имени клиента
read -p "Введите имя клиента (например: ivan, petr): " CLIENT_NAME
if [ -z "$CLIENT_NAME" ]; then
    CLIENT_NAME="client_$(date +%s)"
fi

# Проверяем, не существует ли уже конфиг с таким именем в папке clients_configs
if [ -f "$CLIENTS_CONFIGS_DIR/wg_${CLIENT_NAME}.conf" ]; then
    echo -e "${YELLOW}Внимание: Конфиг с именем '$CLIENT_NAME' уже существует в папке clients_configs${NC}"
    read -p "Перезаписать? (y/n): " OVERWRITE
    if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
        echo "Отмена. Введите другое имя клиента."
        exit 1
    fi
    # Удаляем старые файлы в папке clients_configs
    rm -f "$CLIENTS_CONFIGS_DIR/wg_${CLIENT_NAME}.conf"
    rm -f "$CLIENTS_CONFIGS_DIR/wg_${CLIENT_NAME}_qrcode.png" 2>/dev/null
fi

# Выбор DNS
echo -e "${YELLOW}Выберите DNS серверы:${NC}"
echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
echo "3) Яндекс DNS (77.88.8.8, 77.88.8.1)"
echo "4) Quad9 (9.9.9.9, 149.112.112.112)"
echo "5) AdGuard DNS (94.140.14.14, 94.140.15.15)"
echo "6) Использовать текущие: $CLIENT_DNS"
echo "7) Ввести свои DNS серверы"
read -p "Ваш выбор [1-7]: " DNS_CHOICE

case $DNS_CHOICE in
    1) SELECTED_DNS="8.8.8.8, 8.8.4.4" ;;
    2) SELECTED_DNS="1.1.1.1, 1.0.0.1" ;;
    3) SELECTED_DNS="77.88.8.8, 77.88.8.1" ;;
    4) SELECTED_DNS="9.9.9.9, 149.112.112.112" ;;
    5) SELECTED_DNS="94.140.14.14, 94.140.15.15" ;;
    6) SELECTED_DNS="$CLIENT_DNS" ;;
    7) read -p "Введите DNS серверы (через запятую): " SELECTED_DNS ;;
    *) SELECTED_DNS="$CLIENT_DNS" ;;
esac

# Проверка существования клиента в конфиге сервера
if grep -q "### Client ${CLIENT_NAME}" wg0.conf; then
    echo -e "${YELLOW}Клиент с именем '$CLIENT_NAME' уже есть в конфиге сервера${NC}"
    read -p "Обновить ключи и IP? (y/n): " UPDATE_CLIENT
    if [[ ! $UPDATE_CLIENT =~ ^[Yy]$ ]]; then
        echo "Отмена. Введите другое имя клиента."
        exit 1
    fi
    # Удаляем старую конфигурацию из wg0.conf
    sed -i "/### Client ${CLIENT_NAME}/,/### End Client ${CLIENT_NAME}/d" wg0.conf
fi

# Создаем директорию для ключей клиентов, если не существует
mkdir -p clients

# Генерация ключей клиента
echo -e "${YELLOW}Генерация ключей для клиента ${CLIENT_NAME}...${NC}"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

# Сохранение ключей
echo $CLIENT_PRIVATE_KEY > "clients/${CLIENT_NAME}_private.key"
echo $CLIENT_PUBLIC_KEY > "clients/${CLIENT_NAME}_public.key"
chmod 600 "clients/${CLIENT_NAME}"*.key

# Определение IP клиента
NETWORK_PREFIX=$(echo $WG_NETWORK | cut -d'.' -f1-3)
LAST_IP=$(grep "AllowedIPs" wg0.conf | tail -1 | awk -F'=' '{print $2}' | awk -F'/' '{print $1}' | sed 's/ //g')

if [ -z "$LAST_IP" ]; then
    CLIENT_IP="${NETWORK_PREFIX}.2"
else
    # Увеличиваем последний октет
    OCTET=$(echo $LAST_IP | cut -d'.' -f4)
    NEXT_OCTET=$((OCTET + 1))
    CLIENT_IP="${NETWORK_PREFIX}.${NEXT_OCTET}"
fi

# Добавление клиента в конфиг сервера
echo -e "${YELLOW}Добавление клиента в конфиг сервера...${NC}"
cat >> wg0.conf << EOF

### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
### End Client ${CLIENT_NAME}
EOF

# Перезагрузка конфига сервера
echo -e "${YELLOW}Применение изменений...${NC}"
wg syncconf wg0 <(wg-quick strip wg0)

# Создание конфига клиента с IPv4
CLIENT_CONFIG="${CLIENT_NAME}.conf"
cat > "${CLIENT_CONFIG}" << EOF
# WireGuard конфиг для клиента: ${CLIENT_NAME}
# Создан: $(date)
# IPv4 адрес сервера: ${SERVER_IP}

[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = ${SELECTED_DNS}

[Peer]
PublicKey = $(cat server_public.key)
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Создание QR-кода
if command -v qrencode &> /dev/null; then
    QR_FILE="${CLIENT_NAME}_qrcode.png"
    qrencode -t png -o "${QR_FILE}" < "${CLIENT_CONFIG}"
    echo -e "${GREEN}QR-код создан${NC}"
fi

# Копирование конфига и QR-кода в папку clients_configs
echo -e "${YELLOW}Копирование конфигов в папку clients_configs...${NC}"

# Копируем конфиг
cp "${CLIENT_CONFIG}" "$CLIENTS_CONFIGS_DIR/"
echo "Конфиг скопирован: $CLIENTS_CONFIGS_DIR/${CLIENT_CONFIG}"

# Копируем QR-код, если он создан
if [ -f "${QR_FILE}" ]; then
    cp "${QR_FILE}" "$CLIENTS_CONFIGS_DIR/"
    echo "QR-код скопирован: $CLIENTS_CONFIGS_DIR/${QR_FILE}"
fi

# Меняем права на файлы в папке clients_configs
chmod 644 "$CLIENTS_CONFIGS_DIR/${CLIENT_NAME}.conf" 2>/dev/null
chmod 644 "$CLIENTS_CONFIGS_DIR/${CLIENT_NAME}_qrcode.png" 2>/dev/null

echo -e "${GREEN}=== Конфиг создан! ===${NC}"
echo -e "${BLUE}Файлы сохранены в папке: $CLIENTS_CONFIGS_DIR/${NC}"
echo ""
echo -e "${YELLOW}Настройки клиента:${NC}"
echo "Имя: $CLIENT_NAME"
echo "IP адрес: $CLIENT_IP"
echo "DNS серверы: $SELECTED_DNS"
echo "IPv4 сервера: $SERVER_IP"
echo "Порт сервера: $WG_PORT"
echo ""

# Показываем содержимое конфига
echo -e "${YELLOW}Содержимое конфига (обратите внимание на Endpoint):${NC}"
echo "========================================"
cat "$CLIENTS_CONFIGS_DIR/${CLIENT_CONFIG}"
echo "========================================"
echo ""
echo -e "${GREEN}Для подключения:${NC}"
echo "1. Конфиг находится: $CLIENTS_CONFIGS_DIR/${CLIENT_CONFIG}"
echo "2. Или отсканируйте QR-код: $CLIENTS_CONFIGS_DIR/${QR_FILE}"
echo "3. Убедитесь, что в Endpoint указан IPv4 адрес: $SERVER_IP"
echo ""
echo -e "${RED}ВАЖНО: Проверьте, что в Endpoint указан IPv4 адрес, а не IPv6!${NC}"
echo "Android WireGuard приложение не работает с IPv6 в Endpoint."