#!/bin/bash

# ============================================
#   🔧 FIX ALL — WEB PANEL AUTO REPAIR
#   Fix MySQL + Database + Admin User
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Harus root bro!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${MAGENTA}🔧 FIX ALL — WEB PANEL REPAIR TOOL${NC}        ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============ AUTO DETECT ============
echo -e "${CYAN}[1/8] Auto-detect konfigurasi...${NC}"

# Cari folder webpanel yang ada config.php
WEB_ROOT=""
CONFIG_FILE=""

for dir in /var/www/*/; do
    if [[ -f "${dir}includes/config.php" ]]; then
        WEB_ROOT="${dir%/}"
        CONFIG_FILE="${dir}includes/config.php"
        break
    fi
done

if [[ -z "$WEB_ROOT" ]]; then
    echo -e "${RED}  ✗ Tidak ada web panel yang ditemukan di /var/www/${NC}"
    read -p "  Masukkan path manual (contoh /var/www/web.domain.com): " WEB_ROOT
    [[ -z "$WEB_ROOT" ]] && exit 1
    CONFIG_FILE="$WEB_ROOT/includes/config.php"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}  ✗ File config.php tidak ditemukan!${NC}"
    exit 1
fi

# Extract info dari config.php
DB_NAME=$(grep "define('DB_NAME'" "$CONFIG_FILE" | cut -d"'" -f4)
DB_USER=$(grep "define('DB_USER'" "$CONFIG_FILE" | cut -d"'" -f4)
DB_PASS=$(grep "define('DB_PASS'" "$CONFIG_FILE" | cut -d"'" -f4)
SITE_URL=$(grep "define('SITE_URL'" "$CONFIG_FILE" | cut -d"'" -f4)

echo -e "${GREEN}  ✓ Web Root : $WEB_ROOT${NC}"
echo -e "${GREEN}  ✓ Database : $DB_NAME${NC}"
echo -e "${GREEN}  ✓ DB User  : $DB_USER${NC}"
echo -e "${GREEN}  ✓ Site URL : $SITE_URL${NC}"

# ============ STEP 2: FIX MYSQL ============
echo ""
echo -e "${CYAN}[2/8] Memperbaiki MySQL...${NC}"

# Hapus file FROZEN kalau ada
if [[ -f /etc/mysql/FROZEN ]]; then
    rm -f /etc/mysql/FROZEN
    echo -e "${GREEN}  ✓ File FROZEN dihapus${NC}"
fi

# Cek status mysql
if ! systemctl is-active --quiet mysql; then
    echo -e "${YELLOW}  → MySQL tidak aktif, mencoba start...${NC}"
    systemctl enable mysql >/dev/null 2>&1
    systemctl start mysql >/dev/null 2>&1
    sleep 3
fi

# Kalau masih mati, reinstall
if ! systemctl is-active --quiet mysql; then
    echo -e "${YELLOW}  → MySQL gagal start, melakukan reinstall...${NC}"
    systemctl stop mysql >/dev/null 2>&1
    
    DEBIAN_FRONTEND=noninteractive apt purge mysql-server mysql-server-8.0 mysql-client mysql-common -y >/dev/null 2>&1
    rm -rf /var/lib/mysql /etc/mysql /var/log/mysql
    
    DEBIAN_FRONTEND=noninteractive apt install mysql-server -y -qq >/dev/null 2>&1
    
    systemctl enable mysql >/dev/null 2>&1
    systemctl start mysql >/dev/null 2>&1
    sleep 5
fi

# Tunggu socket ready
for i in {1..15}; do
    [[ -S /var/run/mysqld/mysqld.sock ]] && break
    sleep 1
done

if systemctl is-active --quiet mysql && [[ -S /var/run/mysqld/mysqld.sock ]]; then
    echo -e "${GREEN}  ✓ MySQL aktif & socket ready${NC}"
else
    echo -e "${RED}  ✗ MySQL masih bermasalah!${NC}"
    echo -e "${YELLOW}  Coba cek manual: journalctl -xe | grep mysql${NC}"
    exit 1
fi

# ============ STEP 3: RESET DATABASE ============
echo -e "${CYAN}[3/8] Reset database & user...${NC}"

mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}  ✓ Database & user dibuat${NC}"

# ============ STEP 4: BIKIN TABEL ============
echo -e "${CYAN}[4/8] Membuat tabel database...${NC}"

mysql "$DB_NAME" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    avatar VARCHAR(255) DEFAULT NULL,
    status ENUM('active','banned') DEFAULT 'active',
    last_login DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(255),
    ip VARCHAR(45),
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS settings (
    key_name VARCHAR(50) PRIMARY KEY,
    value TEXT
);

INSERT IGNORE INTO settings VALUES ('site_name', 'Web Panel');
INSERT IGNORE INTO settings VALUES ('site_desc', 'Panel modern dengan fitur lengkap');
SQLEOF

echo -e "${GREEN}  ✓ Tabel dibuat${NC}"

# ============ STEP 5: BIKIN ADMIN ============
echo -e "${CYAN}[5/8] Setup akun admin...${NC}"

read -p "  Username admin [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -p "  Email admin [admin@domain.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@domain.com}

read -s -p "  Password admin [123123123]: " ADMIN_PASS
echo ""
ADMIN_PASS=${ADMIN_PASS:-123123123}

ADMIN_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);")

mysql "$DB_NAME" -e "DELETE FROM users WHERE username='$ADMIN_USER' OR email='$ADMIN_EMAIL';"
mysql "$DB_NAME" -e "INSERT INTO users (username, email, password, role, status) VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', '$ADMIN_HASH', 'admin', 'active');"

echo -e "${GREEN}  ✓ Admin dibuat: $ADMIN_USER${NC}"

# ============ STEP 6: FIX PERMISSION ============
echo -e "${CYAN}[6/8] Fix permissions...${NC}"

# Detect user web server
WEB_USER="www-data"
if ps aux | grep -q "[a]pache"; then WEB_USER="www-data"; fi
if ps aux | grep -q "[n]ginx"; then WEB_USER="www-data"; fi

chown -R "$WEB_USER:$WEB_USER" "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
chmod 640 "$CONFIG_FILE"

echo -e "${GREEN}  ✓ Permission OK${NC}"

# ============ STEP 7: TEST DB CONNECTION ============
echo -e "${CYAN}[7/8] Test koneksi database...${NC}"

TEST=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) FROM users;" 2>&1)

if [[ $? -eq 0 ]]; then
    USER_COUNT=$(echo "$TEST" | tail -1)
    echo -e "${GREEN}  ✓ Koneksi OK! Total user: $USER_COUNT${NC}"
else
    echo -e "${RED}  ✗ Koneksi gagal: $TEST${NC}"
    exit 1
fi

# Test PHP-FPM
if systemctl is-active --quiet php8.3-fpm; then
    echo -e "${GREEN}  ✓ PHP-FPM aktif4${NC}"
else
    system.ctl restart php8.3-fpm
    echo -e "${GREEN}  ✓ PHP-FPM direstart${NC}"
fi

# Restart nginx
systemctl reload nginx 2>/dev/null
echo -e "${GREEN}  ✓ Nginx reloaded${NC}"

# ============ STEP 8: SELESAI ============
echo -e "${CYAN}[8/8] Selesai!${NC}"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ FIX BERHASIL!                       ${NC}  ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 AKSES:${NC}"
echo -e "  Home     : ${YELLOW}$SITE_URL${NC}"
echo -e "  Login    : ${YELLOW}$SITE_URL/login.php${NC}"
echo -e "  Admin    : ${YELLOW}$SITE_URL/admin/${NC}"
echo ""
echo -e "${MAGENTA}🔑 LOGIN ADMIN:${NC}"
echo -e "  Username : ${YELLOW}$ADMIN_USER${NC}"
echo -e "  Password : ${YELLOW}$ADMIN_PASS${NC}"
echo -e "  Email    : ${YELLOW}$ADMIN_EMAIL${NC}"
echo ""
echo -e "${CYAN}📊 INFO:${NC}"
echo -e "  Database : $DB_NAME"
echo -e "  DB User  : $DB_USER"
echo -e "  MySQL    : ${GREEN}$(systemctl is-active mysql)${NC}"
echo -e "  PHP-FPM  : ${GREEN}$(systemctl is-active php8.3-fpm)${NC}"
echo -e "  Nginx    : ${GREEN}$(systemctl is-active nginx)${NC}"
echo ""
echo -e "${GREEN}🎉 Coba buka di browser sekarang!${NC}"
