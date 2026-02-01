Simnple Wireguard VPN installer with custom DNS picker.

After install in dir:
chmod +x install_wireguard.sh generate_client.sh list_clients.sh remove_client.sh

If have a problem with nginx:

      sudo iptables -L -n -v
      
      # Если правил нет, добавьте минимальный набор для WireGuard
      sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
      sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH
      sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT  # HTTP
      sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT # HTTPS
      sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      sudo iptables -A INPUT -i lo -j ACCEPT
      sudo iptables -P INPUT DROP  # Блокируем всё остальное
      
      # Правила для форвардинга трафика WireGuard
      sudo iptables -A FORWARD -i wg0 -j ACCEPT
      sudo iptables -A FORWARD -o wg0 -j ACCEPT
      sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      
      # Сохраните правила
      sudo apt-get install iptables-persistent -y
      sudo netfilter-persistent save
