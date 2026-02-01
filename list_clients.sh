#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Список клиентов WireGuard ===${NC}"

# Определяем текущую директорию
CURRENT_DIR=$(pwd)
CLIENTS_CONFIGS_DIR="$CURRENT_DIR/clients_configs"

# Проверяем существование папки
if [ ! -d "$CLIENTS_CONFIGS_DIR" ]; then
    echo -e "${YELLOW}Папка clients_configs не найдена${NC}"
    echo "Запустите generate_client.sh для создания первого клиента"
    exit 1
fi

# Проверяем, есть ли файлы конфигов
CONFIG_FILES=$(ls "$CLIENTS_CONFIGS_DIR"/*.conf 2>/dev/null | wc -l)

if [ "$CONFIG_FILES" -eq 0 ]; then
    echo -e "${YELLOW}В папке clients_configs нет конфигурационных файлов${NC}"
    exit 0
fi

echo -e "${BLUE}Конфиги клиентов в папке: $CLIENTS_CONFIGS_DIR${NC}"
echo ""

# Список конфигов
echo "Список клиентов:"
echo "----------------------------------------"

# Получаем информацию о подключенных клиентах
CONNECTED_CLIENTS=""
if [ -f "/etc/wireguard/wg0.conf" ] && command -v wg &> /dev/null; then
    CONNECTED_CLIENTS=$(wg show 2>/dev/null | grep "peer:" | awk '{print $2}' | cut -c 6-)
fi

# Показываем все конфиги в папке
for CONFIG_FILE in "$CLIENTS_CONFIGS_DIR"/*.conf; do
    if [ -f "$CONFIG_FILE" ]; then
        FILENAME=$(basename "$CONFIG_FILE")
        CLIENT_NAME=$(echo "$FILENAME" | sed 's/^wg_//' | sed 's/\.conf$//')
        
        # Получаем информацию из конфига
        CLIENT_IP=$(grep "Address" "$CONFIG_FILE" | awk '{print $3}' | cut -d'/' -f1)
        CLIENT_DNS=$(grep "DNS" "$CONFIG_FILE" | awk '{print $3}')
        QR_FILE="${CLIENTS_CONFIGS_DIR}/wg_${CLIENT_NAME}_qrcode.png"
        
        # Проверяем, подключен ли клиент
        IS_CONNECTED=""
        if [ -n "$CONNECTED_CLIENTS" ]; then
            # Получаем публичный ключ клиента из файла
            CLIENT_PRIVATE_KEY=$(grep "PrivateKey" "$CONFIG_FILE" | awk '{print $3}')
            if [ -n "$CLIENT_PRIVATE_KEY" ]; then
                CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey 2>/dev/null)
                if echo "$CONNECTED_CLIENTS" | grep -q "$CLIENT_PUBLIC_KEY"; then
                    IS_CONNECTED="✓ ПОДКЛЮЧЕН"
                else
                    IS_CONNECTED="○ ОТКЛЮЧЕН"
                fi
            fi
        fi
        
        echo -e "${GREEN}Клиент: $CLIENT_NAME${NC}"
        echo "  Файл: $FILENAME"
        echo "  IP: $CLIENT_IP"
        echo "  DNS: $CLIENT_DNS"
        
        if [ -n "$IS_CONNECTED" ]; then
            echo -e "  Статус: $IS_CONNECTED"
        fi
        
        if [ -f "$QR_FILE" ]; then
            echo "  QR-код: wg_${CLIENT_NAME}_qrcode.png"
        fi
        
        # Показываем команду для просмотра конфига
        echo "  Просмотр: cat $CLIENTS_CONFIGS_DIR/$FILENAME"
        echo "----------------------------------------"
    fi
done

# Показываем статистику
TOTAL_CLIENTS=$(ls "$CLIENTS_CONFIGS_DIR"/*.conf 2>/dev/null | wc -l)
TOTAL_QR=$(ls "$CLIENTS_CONFIGS_DIR"/*.png 2>/dev/null | wc -l)

echo ""
echo -e "${BLUE}Статистика:${NC}"
echo "Всего конфигов: $TOTAL_CLIENTS"
echo "Всего QR-кодов: $TOTAL_QR"
echo ""

# Показываем полезные команды
echo -e "${YELLOW}Полезные команды:${NC}"
echo "Просмотр подключенных клиентов: sudo wg show"
echo "Добавить нового клиента: sudo ./generate_client.sh"
echo "Удалить конфиг клиента: rm $CLIENTS_CONFIGS_DIR/wg_имя_клиента.conf"