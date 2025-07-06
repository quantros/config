#!/bin/bash

read -p "Введите домен (например, site.com): " DOMAIN

# Обновление системы и установка необходимых пакетов
sudo apt update && sudo apt install -y ufw nginx certbot python3-certbot-nginx

# Установка и проверка зависимостей вручную
if ! command -v fail2ban-client &> /dev/null; then
    echo "\n[!] Устанавливаю fail2ban..."
    sudo apt install -y fail2ban
fi

if ! command -v netfilter-persistent &> /dev/null; then
    echo "\n[!] Устанавливаю iptables-persistent..."
    sudo apt install -y iptables-persistent netfilter-persistent
fi

# Создание директории если она отсутствует
sudo mkdir -p /etc/nginx/sites-enabled

# Настройка UFW
sudo ufw allow 22
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3001/tcp
sudo ufw --force enable

# Отключение IPv6
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
if ! grep -q disable_ipv6 /etc/sysctl.conf; then
  echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
  echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Настройка Fail2Ban
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 50

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 3600

[nginx-botsearch]
enabled = true
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 100
bantime = 7200
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

# Правила iptables
sudo iptables -A INPUT -p tcp --syn -m limit --limit 10/s --limit-burst 20 -j ACCEPT
sudo iptables -A INPUT -p tcp --syn -j DROP
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
sudo netfilter-persistent save

# Настройка nginx HTTP-конфига
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root /var/www/html;

    location /.well-known/acme-challenge/ {
        allow all;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF


# Подключение конфига
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Проверка nginx и перезагрузка
sudo nginx -t && sudo systemctl reload nginx

# Инструкция для сертификата
echo -e "\n✅ Настройка завершена. Теперь запусти сертификацию командой:\n"
echo "  sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN"
echo -e "\n⚠️ Certbot сам добавит HTTPS конфигурацию (443) и пропишет SSL.\n"
