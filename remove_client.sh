#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== Удаление клиента WireGuard ===${NC}"

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Запуск с sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Определяем текущую директорию
CURRENT_DIR=$(pwd)
CLIENTS_CONFIGS_DIR="$CURRENT_DIR/clients_configs"

# Проверяем существование папки
if [ ! -d "$CLIENTS_CONFIGS_DIR" ]; then
    echo -e "${YELLOW}Папка clients_configs не найдена${NC}"
    exit 1
fi

# Список доступных клиентов
echo "Доступные клиенты:"
CONFIGS=()
INDEX=1

for CONFIG_FILE in "$CLIENTS_CONFIGS_DIR"/*.conf; do
    if [ -f "$CONFIG_FILE" ]; then
        FILENAME=$(basename "$CONFIG_FILE")
        CLIENT_NAME=$(echo "$FILENAME" | sed 's/^wg_//' | sed 's/\.conf$//')
        CONFIGS[$INDEX]="$CLIENT_NAME"
        echo "$INDEX) $CLIENT_NAME"
        ((INDEX++))
    fi
done

if [ ${#CONFIGS[@]} -eq 0 ]; then
    echo "Нет доступных клиентов для удаления"
    exit 0
fi

echo ""
read -p "Выберите номер клиента для удаления (или 0 для отмены): " CHOICE

if [ "$CHOICE" -eq 0 ] || [ -z "$CHOICE" ]; then
    echo "Отмена"
    exit 0
fi

if [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -lt $INDEX ]; then
    CLIENT_NAME=${CONFIGS[$CHOICE]}
    
    echo -e "${YELLOW}Удаление клиента: $CLIENT_NAME${NC}"
    echo "Это удалит конфиг из сервера и файлы из папки clients_configs"
    read -p "Вы уверены? (y/n): " CONFIRM
    
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        # Удаляем из конфига сервера
        if [ -f "/etc/wireguard/wg0.conf" ]; then
            sed -i "/### Client ${CLIENT_NAME}/,/### End Client ${CLIENT_NAME}/d" /etc/wireguard/wg0.conf
            echo "Удалено из конфига сервера"
            
            # Перезагружаем конфиг
            wg syncconf wg0 <(wg-quick strip wg0 2>/dev/null)
        fi
        
        # Удаляем ключи клиента
        rm -f "/etc/wireguard/clients/${CLIENT_NAME}_private.key" 2>/dev/null
        rm -f "/etc/wireguard/clients/${CLIENT_NAME}_public.key" 2>/dev/null
        
        # Удаляем файлы из папки clients_configs
        rm -f "$CLIENTS_CONFIGS_DIR/wg_${CLIENT_NAME}.conf" 2>/dev/null
        rm -f "$CLIENTS_CONFIGS_DIR/wg_${CLIENT_NAME}_qrcode.png" 2>/dev/null
        rm -f "$CLIENTS_CONFIGS_DIR/download_${CLIENT_NAME}.sh" 2>/dev/null
        
        echo -e "${GREEN}Клиент $CLIENT_NAME успешно удален${NC}"
    else
        echo "Отмена удаления"
    fi
else
    echo "Неверный выбор"
fi