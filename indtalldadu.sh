#!/bin/bash

# ============================================
#   🎲 DUELAN DADU GO — INSTALLER v1.0
#   Mode Seru-Seruan (Koin Virtual)
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Harus root bro!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${MAGENTA}🎲 DUELAN DADU GO — INSTALLER v1.0${NC}        ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${YELLOW}Mode Seru-Seruan (Koin Virtual)${NC}           ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============ INPUT ============
read -p "👉 Subdomain yang sudah ada (contoh: rendzz.nebuladnezar.web.id): " SUBDOMAIN
[[ -z "$SUBDOMAIN" ]] && { echo -e "${RED}Kosong!${NC}"; exit 1; }

read -p "👉 Email SSL: " EMAIL
[[ -z "$EMAIL" ]] && { echo -e "${RED}Kosong!${NC}"; exit 1; }

read -p "👉 Username admin: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -s -p "👉 Password admin (min 6): " ADMIN_PASS
echo ""
[[ ${#ADMIN_PASS} -lt 6 ]] && { echo -e "${RED}Minimal 6 karakter!${NC}"; exit 1; }

read -p "👉 Email admin: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@$SUBDOMAIN}

DB_PASS=$(openssl rand -hex 16)
DB_NAME="dadu_$(echo $SUBDOMAIN | tr '.' '_' | cut -c1-20)"
WEB_ROOT="/var/www/$SUBDOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

echo ""
echo -e "${CYAN}📋 Konfigurasi:${NC}"
echo -e "  Subdomain    : ${YELLOW}$SUBDOMAIN${NC}"
echo -e "  Admin User   : ${YELLOW}$ADMIN_USER${NC}"
echo -e "  Admin Email  : ${YELLOW}$ADMIN_EMAIL${NC}"
echo ""
read -p "Lanjut install? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0

# ============ STEP 1: INSTALL PACKAGES ============
echo ""
echo -e "${CYAN}[1/7] Cek & install packages...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Pastikan nginx, php, mysql ada
apt install nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip mysql-server curl wget -y -qq 2>/dev/null

# FIX MySQL dulu
if [[ -f /etc/mysql/FROZEN ]]; then rm -f /etc/mysql/FROZEN; fi
if ! systemctl is-active --quiet mysql; then
    systemctl enable mysql >/dev/null 2>&1
    systemctl start mysql >/dev/null 2>&1
    sleep 3
fi
for i in {1..10}; do
    [[ -S /var/run/mysqld/mysqld.sock ]] && break
    sleep 1
done

systemctl enable nginx php8.3-fpm mysql >/dev/null 2>&1
systemctl start nginx php8.3-fpm mysql >/dev/null 2>&1
echo -e "${GREEN}  ✓ Packages OK${NC}"

# ============ STEP 2: RESET FOLDER (domain tetap) ============
echo -e "${CYAN}[2/7] Setup folder (domain tetap)...${NC}"

# Backup folder lama kalau ada
if [[ -d "$WEB_ROOT" ]]; then
    BACKUP_PATH="/var/www/backup_$(date +%Y%m%d_%H%M%S)"
    mv "$WEB_ROOT" "$BACKUP_PATH"
    echo -e "${YELLOW}  ⚠️  Folder lama di-backup ke: $BACKUP_PATH${NC}"
fi

mkdir -p "$WEB_ROOT"/{admin,user,api,includes,assets/{css,js,img}}
echo -e "${GREEN}  ✓ Folder siap: $WEB_ROOT${NC}"

# ============ STEP 3: DATABASE ============
echo -e "${CYAN}[3/7] Setup database...${NC}"

mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'daduuser'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'daduuser'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << 'SQLEOF'
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    balance BIGINT DEFAULT 1000,
    status ENUM('active','banned') DEFAULT 'active',
    total_bet BIGINT DEFAULT 0,
    total_win BIGINT DEFAULT 0,
    games_played INT DEFAULT 0,
    last_login DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE games (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    bet_amount BIGINT,
    guess ENUM('K','B'),
    dice1 INT, dice2 INT, dice3 INT,
    total INT,
    result ENUM('K','B'),
    win TINYINT(1),
    payout BIGINT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    type ENUM('deposit','withdraw','bonus','bet','win'),
    amount BIGINT,
    status ENUM('pending','approved','rejected') DEFAULT 'pending',
    note VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE settings (
    key_name VARCHAR(50) PRIMARY KEY,
    value TEXT
);

INSERT INTO settings VALUES ('site_name', 'Duellan Dadu GO');
INSERT INTO settings VALUES ('rtp_small', '45');
INSERT INTO settings VALUES ('rtp_big', '45');
INSERT INTO settings VALUES ('payout_multiplier', '2.1');
INSERT INTO settings VALUES ('min_bet', '100');
INSERT INTO settings VALUES ('max_bet', '10000');
INSERT INTO settings VALUES ('daily_bonus', '500');
INSERT INTO settings VALUES ('min_deposit', '10000');
INSERT INTO settings VALUES ('min_withdraw', '10000');

CREATE TABLE activity_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(255),
    ip VARCHAR(45),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQLEOF

echo -e "${GREEN}  ✓ Database & tabel dibuat${NC}"

# ============ STEP 4: CONFIG ============
echo -e "${CYAN}[4/7] Bikin file config...${NC}"

cat > "$WEB_ROOT/includes/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', 'localhost');
define('DB_NAME', '$DB_NAME');
define('DB_USER', 'daduuser');
define('DB_PASS', '$DB_PASS');
define('SITE_URL', 'https://$SUBDOMAIN');
define('SITE_NAME', 'Duellan Dadu GO');

try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }

function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function isAdmin() { return isLoggedIn() && \$_SESSION['role'] === 'admin'; }
function requireLogin() { if (!isLoggedIn()) { header('Location: /login.php'); exit; } }
function requireAdmin() { if (!isAdmin()) { header('Location: /user/'); exit; } }
function csrf() { if (empty(\$_SESSION['csrf'])) \$_SESSION['csrf'] = bin2hex(random_bytes(32)); return \$_SESSION['csrf']; }
function checkCsrf(\$t) { return isset(\$_SESSION['csrf']) && hash_equals(\$_SESSION['csrf'], \$t); }
function getSetting(\$pdo, \$key) { \$s = \$pdo->prepare("SELECT value FROM settings WHERE key_name=?"); \$s->execute([\$key]); return \$s->fetchColumn(); }
function logAct(\$pdo, \$uid, \$action) { \$s = \$pdo->prepare("INSERT INTO activity_log (user_id, action, ip) VALUES (?,?,?)"); \$s->execute([\$uid, \$action, \$_SERVER['REMOTE_ADDR'] ?? '']); }
function rupiah(\$n) { return number_format(\$n, 0, ',', '.'); }
PHPEOF

# Bikin admin
ADMIN_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);")
mysql "$DB_NAME" -e "INSERT INTO users (username, email, password, role, balance, status) VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', '$ADMIN_HASH', 'admin', 999999999, 'active');"

echo -e "${GREEN}  ✓ Config & admin dibuat${NC}"

# ============ STEP 5: HALAMAN ============
echo -e "${CYAN}[5/7] Bikin halaman PHP...${NC}"

# ---------- HEADER ----------
cat > "$WEB_ROOT/includes/header.php" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?= $pageTitle ?? 'Home' ?> - <?= SITE_NAME ?></title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
HTMLEOF

# ---------- NAVBAR ----------
cat > "$WEB_ROOT/includes/navbar.php" << 'HTMLEOF'
<?php $balance = 0; if (isLoggedIn()) { $q = $pdo->prepare("SELECT balance FROM users WHERE id=?"); $q->execute([$_SESSION['user_id']]); $balance = (int)$q->fetchColumn(); } ?>
<nav class="navbar">
    <div class="nav-left">
        <a href="/" class="logo"><i class="fas fa-dice"></i> <?= SITE_NAME ?></a>
    </div>
    <div class="nav-center">
        <a href="/"><i class="fas fa-home"></i> Home</a>
        <?php if (isLoggedIn()): ?>
            <a href="/user/"><i class="fas fa-dice-d6"></i> Main</a>
            <a href="/user/wallet.php"><i class="fas fa-wallet"></i> Wallet</a>
            <?php if (isAdmin()): ?>
                <a href="/admin/"><i class="fas fa-crown"></i> Admin</a>
            <?php endif; ?>
        <?php endif; ?>
    </div>
    <div class="nav-right">
        <?php if (isLoggedIn()): ?>
            <div class="balance-chip"><i class="fas fa-coins"></i> <?= rupiah($balance) ?></div>
            <div class="user-menu">
                <button class="icon-btn user-btn"><i class="fas fa-user-circle"></i> <?= htmlspecialchars($_SESSION['username']) ?></button>
                <div class="dropdown">
                    <a href="/user/"><i class="fas fa-dice"></i> Main</a>
                    <a href="/user/wallet.php"><i class="fas fa-wallet"></i> Wallet</a>
                    <a href="/user/history.php"><i class="fas fa-history"></i> Riwayat</a>
                    <a href="/logout.php"><i class="fas fa-sign-out-alt"></i> Logout</a>
                </div>
            </div>
        <?php else: ?>
            <a href="/login.php" class="btn btn-primary"><i class="fas fa-sign-in-alt"></i> Login</a>
            <a href="/register.php" class="btn btn-outline"><i class="fas fa-user-plus"></i> Register</a>
        <?php endif; ?>
        <button id="themeToggle" class="icon-btn"><i class="fas fa-sun"></i></button>
    </div>
</nav>
HTMLEOF

# ---------- FOOTER ----------
cat > "$WEB_ROOT/includes/footer.php" << 'HTMLEOF'
<footer class="footer"><p><i class="fas fa-dice"></i> <?= date('Y') ?> <?= SITE_NAME ?> — Mode Seru-Seruan 🎲</p></footer>
<script src="/assets/js/main.js"></script>
</body>
</html>
HTMLEOF

# ---------- INDEX ----------
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require_once __DIR__ . '/includes/config.php'; $pageTitle = 'Home'; include __DIR__ . '/includes/header.php'; include __DIR__ . '/includes/navbar.php'; ?>
<section class="hero">
    <div class="hero-content">
        <h1><i class="fas fa-dice"></i> Duellan Dadu GO</h1>
        <p>Tebak Kecil atau Besar, menang dapat <strong>x2.1</strong>! Mode seru-seruan pakai koin virtual 🎲</p>
        <div class="btn-group">
            <?php if (isLoggedIn()): ?>
                <a href="/user/" class="btn btn-primary btn-lg"><i class="fas fa-dice-d6"></i> Main Sekarang</a>
            <?php else: ?>
                <a href="/register.php" class="btn btn-primary btn-lg"><i class="fas fa-user-plus"></i> Daftar Gratis</a>
                <a href="/login.php" class="btn btn-outline btn-lg"><i class="fas fa-sign-in-alt"></i> Login</a>
            <?php endif; ?>
        </div>
        <p style="margin-top:20px;font-size:0.9em;opacity:0.8"><i class="fas fa-gift"></i> Bonus 1000 koin gratis untuk user baru!</p>
    </div>
</section>
<section class="features">
    <h2><i class="fas fa-star"></i> Cara Main</h2>
    <div class="feature-grid">
        <div class="feature-card"><i class="fas fa-user-plus"></i><h3>1. Daftar Gratis</h3><p>Dapat 1000 koin langsung</p></div>
        <div class="feature-card"><i class="fas fa-hand-holding-usd"></i><h3>2. Isi Koin</h3><p>Minta admin atau daily bonus</p></div>
        <div class="feature-card"><i class="fas fa-dice"></i><h3>3. Tebak K/B</h3><p>Pilih Kecil (3-10) atau Besar (11-18)</p></div>
        <div class="feature-card"><i class="fas fa-trophy"></i><h3>4. Menang!</h3><p>Bet dikali 2.1 masuk ke saldo</p></div>
    </div>
</section>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- LOGIN ----------
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /user/'); exit; }
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) { $error = 'Invalid CSRF'; }
    else {
        $u = trim($_POST['username'] ?? '');
        $p = $_POST['password'] ?? '';
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username=? OR email=? LIMIT 1");
        $stmt->execute([$u, $u]);
        $user = $stmt->fetch();
        if ($user && password_verify($p, $user['password'])) {
            if ($user['status'] === 'banned') { $error = 'Akun kamu dibanned!'; }
            else {
                $_SESSION['user_id'] = $user['id'];
                $_SESSION['username'] = $user['username'];
                $_SESSION['role'] = $user['role'];
                $pdo->prepare("UPDATE users SET last_login=NOW() WHERE id=?")->execute([$user['id']]);
                logAct($pdo, $user['id'], 'Login');
                header('Location: ' . ($user['role'] === 'admin' ? '/admin/' : '/user/'));
                exit;
            }
        } else { $error = 'Username/password salah'; }
    }
}
$pageTitle = 'Login'; include __DIR__ . '/includes/header.php'; include __DIR__ . '/includes/navbar.php';
?>
<div class="auth-wrap"><div class="auth-card">
    <h1><i class="fas fa-sign-in-alt"></i> Login</h1>
    <p class="subtitle">Masuk buat mulai main</p>
    <?php if ($error): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $error ?></div><?php endif; ?>
    <form method="POST">
        <input type="hidden" name="csrf" value="<?= csrf() ?>">
        <div class="form-group"><label><i class="fas fa-user"></i> Username/Email</label><input type="text" name="username" required autofocus></div>
        <div class="form-group"><label><i class="fas fa-lock"></i> Password</label><input type="password" name="password" required></div>
        <button class="btn btn-primary btn-block"><i class="fas fa-sign-in-alt"></i> Login</button>
    </form>
    <p class="auth-footer">Belum punya akun? <a href="/register.php">Daftar (gratis 1000 koin)</a></p>
</div></div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- REGISTER ----------
cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /user/'); exit; }
$error = ''; $success = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) { $error = 'Invalid CSRF'; }
    else {
        $u = trim($_POST['username'] ?? '');
        $e = trim($_POST['email'] ?? '');
        $p = $_POST['password'] ?? '';
        $c = $_POST['confirm'] ?? '';
        if (strlen($u) < 3) $error = 'Username min 3 karakter';
        elseif (!filter_var($e, FILTER_VALIDATE_EMAIL)) $error = 'Email invalid';
        elseif (strlen($p) < 6) $error = 'Password min 6 karakter';
        elseif ($p !== $c) $error = 'Konfirmasi password beda';
        else {
            $s = $pdo->prepare("SELECT id FROM users WHERE username=? OR email=?");
            $s->execute([$u, $e]);
            if ($s->fetch()) $error = 'Username/email sudah ada';
            else {
                $h = password_hash($p, PASSWORD_BCRYPT);
                $pdo->prepare("INSERT INTO users (username,email,password,balance) VALUES (?,?,?,1000)")->execute([$u, $e, $h]);
                $success = 'Daftar berhasil! Dapat 1000 koin gratis 🎁 Silakan login.';
            }
        }
    }
}
$pageTitle = 'Register'; include __DIR__ . '/includes/header.php'; include __DIR__ . '/includes/navbar.php';
?>
<div class="auth-wrap"><div class="auth-card">
    <h1><i class="fas fa-user-plus"></i> Register</h1>
    <p class="subtitle">Bonus 1000 koin buat member baru 🎁</p>
    <?php if ($error): ?><div class="alert alert-error"><?= $error ?></div><?php endif; ?>
    <?php if ($success): ?><div class="alert alert-success"><?= $success ?></div><?php endif; ?>
    <form method="POST">
        <input type="hidden" name="csrf" value="<?= csrf() ?>">
        <div class="form-group"><label><i class="fas fa-user"></i> Username</label><input type="text" name="username" required></div>
        <div class="form-group"><label><i class="fas fa-envelope"></i> Email</label><input type="email" name="email" required></div>
        <div class="form-group"><label><i class="fas fa-lock"></i> Password</label><input type="password" name="password" required></div>
        <div class="form-group"><label><i class="fas fa-lock"></i> Konfirmasi</label><input type="password" name="confirm" required></div>
        <button class="btn btn-primary btn-block"><i class="fas fa-user-plus"></i> Daftar</button>
    </form>
    <p class="auth-footer">Sudah punya akun? <a href="/login.php">Login</a></p>
</div></div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- LOGOUT ----------
cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php require_once __DIR__ . '/includes/config.php'; if (isLoggedIn()) logAct($pdo, $_SESSION['user_id'], 'Logout'); session_destroy(); header('Location: /login.php'); exit;
PHPEOF

# ---------- USER DASHBOARD (GAME) ----------
cat > "$WEB_ROOT/user/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireLogin();
$pageTitle = 'Main Dadu';
$user = $pdo->prepare("SELECT * FROM users WHERE id=?"); $user->execute([$_SESSION['user_id']]); $user = $user->fetch();
$minBet = getSetting($pdo, 'min_bet');
$maxBet = getSetting($pdo, 'max_bet');
$multiplier = getSetting($pdo, 'payout_multiplier');
$recent = $pdo->prepare("SELECT * FROM games WHERE user_id=? ORDER BY id DESC LIMIT 5"); $recent->execute([$_SESSION['user_id']]); $recent = $recent->fetchAll();
include __DIR__ . '/../includes/header.php'; include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="game-header">
        <h1><i class="fas fa-dice"></i> Duelan Dadu</h1>
        <p>Tebak <strong>KECIL</strong> (3-10) atau <strong>BESAR</strong> (11-18) — menang dapat <strong>x<?= $multiplier ?></strong>!</p>
    </div>
    
    <div class="game-layout">
        <div class="game-board">
            <div class="dice-container" id="diceContainer">
                <div class="dice" id="d1">🎲</div>
                <div class="dice" id="d2">🎲</div>
                <div class="dice" id="d3">🎲</div>
            </div>
            <div class="total-display" id="totalDisplay">-</div>
            <div class="result-display" id="resultDisplay">Pilih & pasang bet!</div>
        </div>
        
        <div class="bet-panel">
            <div class="balance-big"><i class="fas fa-coins"></i> <?= rupiah($user['balance']) ?> koin</div>
            <div class="form-group">
                <label>Jumlah Bet (<?= rupiah($minBet) ?> - <?= rupiah($maxBet) ?>)</label>
                <input type="number" id="betAmount" value="<?= $minBet ?>" min="<?= $minBet ?>" max="<?= $maxBet ?>">
            </div>
            <div class="quick-bet">
                <button onclick="setBet(100)">100</button>
                <button onclick="setBet(500)">500</button>
                <button onclick="setBet(1000)">1K</button>
                <button onclick="setBet(5000)">5K</button>
                <button onclick="setBet(<?= $user['balance'] ?>)">ALL</button>
            </div>
            <div class="bet-buttons">
                <button class="bet-btn small" onclick="play('K')"><i class="fas fa-arrow-down"></i> KECIL</button>
                <button class="bet-btn big" onclick="play('B')"><i class="fas fa-arrow-up"></i> BESAR</button>
            </div>
        </div>
    </div>
    
    <div class="card">
        <h2><i class="fas fa-history"></i> 5 Game Terakhir</h2>
        <table class="table">
            <thead><tr><th>Waktu</th><th>Bet</th><th>Tebak</th><th>Dadu</th><th>Total</th><th>Hasil</th></tr></thead>
            <tbody>
                <?php if (empty($recent)): ?><tr><td colspan="6" style="text-align:center;color:#888">Belum ada game</td></tr>
                <?php else: foreach ($recent as $g): ?>
                    <tr>
                        <td><small><?= date('d/m H:i', strtotime($g['created_at'])) ?></small></td>
                        <td><?= rupiah($g['bet_amount']) ?></td>
                        <td><span class="badge badge-<?= $g['guess'] === 'K' ? 'info' : 'warning' ?>"><?= $g['guess'] === 'K' ? 'KECIL' : 'BESAR' ?></span></td>
                        <td><?= $g['dice1'] ?>+<?= $g['dice2'] ?>+<?= $g['dice3'] ?></td>
                        <td><strong><?= $g['total'] ?></strong></td>
                        <td><?= $g['win'] ? '<span class="badge badge-active">WIN +'.rupiah($g['payout']).'</span>' : '<span class="badge badge-banned">LOSE</span>' ?></td>
                    </tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>

<script>
function setBet(n) { document.getElementById('betAmount').value = Math.min(n, <?= $user['balance'] ?>); }

async function play(guess) {
    const bet = parseInt(document.getElementById('betAmount').value);
    if (!bet || bet < <?= $minBet ?>) { alert('Bet minimal <?= rupiah($minBet) ?>'); return; }
    if (bet > <?= $maxBet ?>) { alert('Bet maksimal <?= rupiah($maxBet) ?>'); return; }
    if (bet > <?= $user['balance'] ?>) { alert('Saldo kurang!'); return; }
    
    // Reset display
    document.querySelectorAll('.dice').forEach(d => d.textContent = '🎲');
    document.getElementById('totalDisplay').textContent = '...';
    document.getElementById('resultDisplay').textContent = 'Mengocok dadu...';
    document.getElementById('resultDisplay').className = 'result-display';
    
    // Animasi
    let spins = 0;
    const spinInterval = setInterval(() => {
        document.querySelectorAll('.dice').forEach(d => d.textContent = ['⚀','⚁','⚂','⚃','⚄','⚅'][Math.floor(Math.random()*6)]);
        spins++;
        if (spins > 15) clearInterval(spinInterval);
    }, 80);
    
    try {
        const res = await fetch('/api/play.php', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({guess, bet})
        });
        const data = await res.json();
        
        setTimeout(() => {
            clearInterval(spinInterval);
            document.getElementById('d1').textContent = data.dice_emoji[0];
            document.getElementById('d2').textContent = data.dice_emoji[1];
            document.getElementById('d3').textContent = data.dice_emoji[2];
            document.getElementById('totalDisplay').textContent = 'Total: ' + data.total + ' (' + (data.total <= 10 ? 'KECIL' : 'BESAR') + ')';
            
            if (data.win) {
                document.getElementById('resultDisplay').textContent = '🎉 MENANG! +' + data.payout.toLocaleString();
                document.getElementById('resultDisplay').className = 'result-display win';
            } else {
                document.getElementById('resultDisplay').textContent = '😢 KALAH. Coba lagi!';
                document.getElementById('resultDisplay').className = 'result-display lose';
            }
            
            if (data.error) {
                document.getElementById('resultDisplay').textContent = '❌ ' + data.error;
                document.getElementById('resultDisplay').className = 'result-display lose';
            }
            
            setTimeout(() => location.reload(), 2000);
        }, 1400);
    } catch (e) {
        clearInterval(spinInterval);
        document.getElementById('resultDisplay').textContent = '❌ Error: ' + e.message;
    }
}
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- API PLAY ----------
cat > "$WEB_ROOT/api/play.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
header('Content-Type: application/json');

if (!isLoggedIn()) { echo json_encode(['error'=>'Login dulu']); exit; }

$input = json_decode(file_get_contents('php://input'), true);
$guess = $input['guess'] ?? '';
$bet = (int)($input['bet'] ?? 0);

if (!in_array($guess, ['K','B'])) { echo json_encode(['error'=>'Tebakan invalid']); exit; }

$minBet = (int)getSetting($pdo, 'min_bet');
$maxBet = (int)getSetting($pdo, 'max_bet');
$mult = (float)getSetting($pdo, 'payout_multiplier');
$rtpK = (int)getSetting($pdo, 'rtp_small');
$rtpB = (int)getSetting($pdo, 'rtp_big');

if ($bet < $minBet || $bet > $maxBet) { echo json_encode(['error'=>'Bet di luar limit']); exit; }

$user = $pdo->prepare("SELECT * FROM users WHERE id=?");
$user->execute([$_SESSION['user_id']]);
$user = $user->fetch();

if ($user['balance'] < $bet) { echo json_encode(['error'=>'Saldo tidak cukup']); exit; }

// Tentukan hasil berdasarkan RTP
$rtp = $guess === 'K' ? $rtpK : $rtpB;
$win = (mt_rand(1, 100) <= $rtp);

// Generate dadu sesuai hasil
do {
    $d1 = mt_rand(1,6); $d2 = mt_rand(1,6); $d3 = mt_rand(1,6);
    $total = $d1 + $d2 + $d3;
    $resultIsSmall = $total <= 10;
    $resultIsBig = $total >= 11;
    $isWin = ($guess === 'K' && $resultIsSmall) || ($guess === 'B' && $resultIsBig);
} while ($isWin !== $win);

$payout = $win ? (int)($bet * $mult) : 0;
$balanceChange = $payout - $bet;

// Update balance
$newBalance = $user['balance'] + $balanceChange;
$pdo->prepare("UPDATE users SET balance=?, total_bet=total_bet+?, total_win=total_win+?, games_played=games_played+1 WHERE id=?")
    ->execute([$newBalance, $bet, $payout, $user['id']]);

// Catat game
$pdo->prepare("INSERT INTO games (user_id, bet_amount, guess, dice1, dice2, dice3, total, result, win, payout) VALUES (?,?,?,?,?,?,?,?,?,?)")
    ->execute([$user['id'], $bet, $guess, $d1, $d2, $d3, $total, $resultIsSmall ? 'K' : 'B', $win ? 1 : 0, $payout]);

// Log
logAct($pdo, $user['id'], "Main dadu: bet $bet, tebak $guess, hasil $total ($win)");

$emojis = ['⚀','⚁','⚂','⚃','⚄','⚅'];
echo json_encode([
    'dice' => [$d1, $d2, $d3],
    'dice_emoji' => [$emojis[$d1-1], $emojis[$d2-1], $emojis[$d3-1]],
    'total' => $total,
    'result' => $resultIsSmall ? 'K' : 'B',
    'win' => $win,
    'payout' => $payout,
    'balance' => $newBalance,
]);
PHPEOF

# ---------- USER WALLET ----------
cat > "$WEB_ROOT/user/wallet.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireLogin();

$msg = ''; $err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    $type = $_POST['type'] ?? '';
    $amount = (int)($_POST['amount'] ?? 0);
    $note = trim($_POST['note'] ?? '');
    $minDep = (int)getSetting($pdo, 'min_deposit');
    $minWd = (int)getSetting($pdo, 'min_withdraw');
    
    if (!in_array($type, ['deposit','withdraw'])) $err = 'Tipe invalid';
    elseif ($type === 'deposit' && $amount < $minDep) $err = "Min deposit ".rupiah($minDep);
    elseif ($type === 'withdraw' && $amount < $minWd) $err = "Min withdraw ".rupiah($minWd);
    else {
        if ($type === 'withdraw') {
            $bal = $pdo->prepare("SELECT balance FROM users WHERE id=?"); $bal->execute([$_SESSION['user_id']]); $bal = (int)$bal->fetchColumn();
            if ($bal < $amount) { $err = 'Saldo tidak cukup'; }
        }
        if (!$err) {
            $pdo->prepare("INSERT INTO transactions (user_id, type, amount, note) VALUES (?,?,?,?)")->execute([$_SESSION['user_id'], $type, $amount, $note]);
            $msg = 'Permintaan ' . $type . ' dikirim! Tunggu approve admin.';
        }
    }
}

$user = $pdo->prepare("SELECT * FROM users WHERE id=?"); $user->execute([$_SESSION['user_id']]); $user = $user->fetch();
$txs = $pdo->prepare("SELECT * FROM transactions WHERE user_id=? ORDER BY id DESC LIMIT 20"); $txs->execute([$_SESSION['user_id']]); $txs = $txs->fetchAll();

$pageTitle = 'Wallet';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header">
        <h1><i class="fas fa-wallet"></i> Wallet</h1>
        <p>Kelola koin kamu</p>
    </div>
    
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#667eea,#764ba2)"><i class="fas fa-coins"></i></div><div class="stat-info"><h3><?= rupiah($user['balance']) ?></h3><p>Saldo Koin</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#4facfe,#00f2fe)"><i class="fas fa-dice"></i></div><div class="stat-info"><h3><?= $user['games_played'] ?></h3><p>Total Main</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#43e97b,#38f9d7)"><i class="fas fa-trophy"></i></div><div class="stat-info"><h3><?= rupiah($user['total_win']) ?></h3><p>Total Menang</p></div></div>
    </div>
    
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
    
    <div class="grid-2">
        <div class="card">
            <h2><i class="fas fa-plus-circle"></i> Deposit Koin</h2>
            <p style="color:#888;margin-bottom:15px">Minta koin ke admin (min <?= rupiah(getSetting($pdo,'min_deposit')) ?>)</p>
            <form method="POST">
                <input type="hidden" name="csrf" value="<?= csrf() ?>">
                <input type="hidden" name="type" value="deposit">
                <div class="form-group"><label>Jumlah Koin</label><input type="number" name="amount" min="<?= getSetting($pdo,'min_deposit') ?>" required></div>
                <div class="form-group"><label>Catatan (opsional)</label><input type="text" name="note" placeholder="contoh: minta koin buat main"></div>
                <button class="btn btn-primary btn-block"><i class="fas fa-paper-plane"></i> Kirim Permintaan Deposit</button>
            </form>
        </div>
        <div class="card">
            <h2><i class="fas fa-hand-holding-usd"></i> Withdraw Koin</h2>
            <p style="color:#888;margin-bottom:15px">Tarik koin dari saldo (min <?= rupiah(getSetting($pdo,'min_withdraw')) ?>)</p>
            <form method="POST">
                <input type="hidden" name="csrf" value="<?= csrf() ?>">
                <input type="hidden" name="type" value="withdraw">
                <div class="form-group"><label>Jumlah Koin</label><input type="number" name="amount" min="<?= getSetting($pdo,'min_withdraw') ?>" required></div>
                <div class="form-group"><label>Catatan (opsional)</label><input type="text" name="note" placeholder="contoh: mau tuker hadiah"></div>
                <button class="btn btn-primary btn-block"><i class="fas fa-paper-plane"></i> Kirim Permintaan Withdraw</button>
            </form>
        </div>
    </div>
    
    <div class="card">
        <h2><i class="fas fa-history"></i> Riwayat Transaksi</h2>
        <table class="table">
            <thead><tr><th>Waktu</th><th>Tipe</th><th>Jumlah</th><th>Status</th><th>Catatan</th></tr></thead>
            <tbody>
                <?php if (empty($txs)): ?><tr><td colspan="5" style="text-align:center;color:#888">Belum ada transaksi</td></tr>
                <?php else: foreach ($txs as $t): ?>
                    <tr>
                        <td><small><?= date('d/m H:i', strtotime($t['created_at'])) ?></small></td>
                        <td><span class="badge badge-<?= $t['type']=='deposit'?'info':($t['type']=='withdraw'?'warning':'active') ?>"><?= strtoupper($t['type']) ?></span></td>
                        <td><?= rupiah($t['amount']) ?></td>
                        <td><span class="badge badge-<?= $t['status']=='approved'?'active':($t['status']=='rejected'?'banned':'user') ?>"><?= $t['status'] ?></span></td>
                        <td><small><?= htmlspecialchars($t['note']) ?></small></td>
                    </tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- USER HISTORY ----------
cat > "$WEB_ROOT/user/history.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireLogin();
$games = $pdo->prepare("SELECT * FROM games WHERE user_id=? ORDER BY id DESC LIMIT 50"); $games->execute([$_SESSION['user_id']]); $games = $games->fetchAll();
$pageTitle = 'Riwayat';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header"><h1><i class="fas fa-history"></i> Riwayat Game</h1><p>50 game terakhir</p></div>
    <div class="card">
        <table class="table">
            <thead><tr><th>Waktu</th><th>Bet</th><th>Tebak</th><th>Dadu</th><th>Total</th><th>Hasil</th><th>Payout</th></tr></thead>
            <tbody>
                <?php if (empty($games)): ?><tr><td colspan="7" style="text-align:center;color:#888">Belum ada</td></tr>
                <?php else: foreach ($games as $g): ?>
                    <tr>
                        <td><small><?= date('d/m H:i', strtotime($g['created_at'])) ?></small></td>
                        <td><?= rupiah($g['bet_amount']) ?></td>
                        <td><span class="badge badge-<?= $g['guess']=='K'?'info':'warning' ?>"><?= $g['guess']=='K'?'KECIL':'BESAR' ?></span></td>
                        <td><?= $g['dice1'] ?>+<?= $g['dice2'] ?>+<?= $g['dice3'] ?></td>
                        <td><strong><?= $g['total'] ?></strong></td>
                        <td><?= $g['win'] ? '<span class="badge badge-active">WIN</span>' : '<span class="badge badge-banned">LOSE</span>' ?></td>
                        <td><?= $g['win'] ? '+'.rupiah($g['payout']) : '-' ?></td>
                    </tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN DASHBOARD ----------
cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$pageTitle = 'Admin';
$totalUsers = (int)$pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalGames = (int)$pdo->query("SELECT COUNT(*) FROM games")->fetchColumn();
$pendingTx = (int)$pdo->query("SELECT COUNT(*) FROM transactions WHERE status='pending'")->fetchColumn();
$totalBalance = (int)$pdo->query("SELECT COALESCE(SUM(balance),0) FROM users WHERE role='user'")->fetchColumn();
$recentTx = $pdo->query("SELECT t.*, u.username FROM transactions t LEFT JOIN users u ON t.user_id=u.id WHERE t.status='pending' ORDER BY t.id DESC LIMIT 10")->fetchAll();
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header"><h1><i class="fas fa-crown"></i> Admin Dashboard</h1></div>
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#667eea,#764ba2)"><i class="fas fa-users"></i></div><div class="stat-info"><h3><?= $totalUsers ?></h3><p>Total User</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#f093fb,#f5576c)"><i class="fas fa-dice"></i></div><div class="stat-info"><h3><?= number_format($totalGames) ?></h3><p>Total Game</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#fa709a,#fee140)"><i class="fas fa-clock"></i></div><div class="stat-info"><h3><?= $pendingTx ?></h3><p>Transaksi Pending</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#43e97b,#38f9d7)"><i class="fas fa-coins"></i></div><div class="stat-info"><h3><?= rupiah($totalBalance) ?></h3><p>Total Saldo User</p></div></div>
    </div>
    
    <div class="quick-actions">
        <a href="/admin/users.php" class="action-btn"><i class="fas fa-users-cog"></i><span>Kelola User</span></a>
        <a href="/admin/transactions.php" class="action-btn"><i class="fas fa-exchange-alt"></i><span>Transaksi <?= $pendingTx > 0 ? "($pendingTx)" : '' ?></span></a>
        <a href="/admin/games.php" class="action-btn"><i class="fas fa-dice"></i><span>Semua Game</span></a>
        <a href="/admin/settings.php" class="action-btn"><i class="fas fa-cog"></i><span>Setting RTP</span></a>
    </div>
    
    <div class="card">
        <h2><i class="fas fa-bell"></i> Transaksi Pending Terbaru</h2>
        <table class="table">
            <thead><tr><th>User</th><th>Tipe</th><th>Jumlah</th><th>Waktu</th><th>Aksi</th></tr></thead>
            <tbody>
                <?php if (empty($recentTx)): ?><tr><td colspan="5" style="text-align:center;color:#888">Tidak ada transaksi pending</td></tr>
                <?php else: foreach ($recentTx as $t): ?>
                    <tr>
                        <td><?= htmlspecialchars($t['username']) ?></td>
                        <td><span class="badge badge-<?= $t['type']=='deposit'?'info':'warning' ?>"><?= strtoupper($t['type']) ?></span></td>
                        <td><?= rupiah($t['amount']) ?></td>
                        <td><small><?= date('d/m H:i', strtotime($t['created_at'])) ?></small></td>
                        <td><a href="/admin/transactions.php" class="btn-icon btn-info"><i class="fas fa-arrow-right"></i></a></td>
                    </tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN USERS ----------
cat > "$WEB_ROOT/admin/users.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    $action = $_POST['action'] ?? '';
    $uid = (int)($_POST['uid'] ?? 0);
    $amount = (int)($_POST['amount'] ?? 0);
    if ($uid && $uid != $_SESSION['user_id']) {
        if ($action === 'ban') { $pdo->prepare("UPDATE users SET status='banned' WHERE id=?")->execute([$uid]); $msg='User dibanned'; }
        elseif ($action === 'unban') { $pdo->prepare("UPDATE users SET status='active' WHERE id=?")->execute([$uid]); $msg='User diaktifkan'; }
        elseif ($action === 'addkoin' && $amount > 0) { $pdo->prepare("UPDATE users SET balance=balance+? WHERE id=?")->execute([$amount, $uid]); $pdo->prepare("INSERT INTO transactions (user_id,type,amount,status,note) VALUES (?,'bonus',?,'approved','Bonus dari admin')")->execute([$uid, $amount]); $msg="Ditambah $amount koin"; }
        elseif ($action === 'resetkoin') { $pdo->prepare("UPDATE users SET balance=1000 WHERE id=?")->execute([$uid]); $msg='Saldo direset ke 1000'; }
        elseif ($action === 'delete') { $pdo->prepare("DELETE FROM users WHERE id=?")->execute([$uid]); $msg='User dihapus'; }
        logAct($pdo, $_SESSION['user_id'], "Admin: $action user $uid");
    }
}
$users = $pdo->query("SELECT * FROM users ORDER BY id DESC")->fetchAll();
$pageTitle = 'Kelola User';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header"><h1><i class="fas fa-users-cog"></i> Kelola User</h1></div>
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <div class="card">
        <table class="table">
            <thead><tr><th>ID</th><th>Username</th><th>Email</th><th>Saldo</th><th>Status</th><th>Main</th><th>Aksi</th></tr></thead>
            <tbody>
                <?php foreach ($users as $u): ?>
                <tr>
                    <td>#<?= $u['id'] ?></td>
                    <td><i class="fas fa-user-circle"></i> <?= htmlspecialchars($u['username']) ?> <?= $u['role']=='admin'?'<i class="fas fa-crown" style="color:gold"></i>':'' ?></td>
                    <td><small><?= htmlspecialchars($u['email']) ?></small></td>
                    <td><strong><?= rupiah($u['balance']) ?></strong></td>
                    <td><span class="badge badge-<?= $u['status']=='active'?'active':'banned' ?>"><?= $u['status'] ?></span></td>
                    <td><?= $u['games_played'] ?></td>
                    <td class="actions">
                        <?php if ($u['id'] != $_SESSION['user_id']): ?>
                        <form method="POST" style="display:inline-flex;gap:3px;flex-wrap:wrap">
                            <input type="hidden" name="csrf" value="<?= csrf() ?>">
                            <input type="hidden" name="uid" value="<?= $u['id'] ?>">
                            <?php if ($u['status']=='active'): ?>
                                <button name="action" value="ban" class="btn-icon btn-warn" title="Ban"><i class="fas fa-ban"></i></button>
                            <?php else: ?>
                                <button name="action" value="unban" class="btn-icon btn-ok" title="Unban"><i class="fas fa-check"></i></button>
                            <?php endif; ?>
                            <input type="number" name="amount" placeholder="koin" style="width:70px;padding:4px;border-radius:4px;border:1px solid var(--border);background:var(--bg);color:var(--text)">
                            <button name="action" value="addkoin" class="btn-icon btn-info" title="Tambah Koin"><i class="fas fa-plus"></i></button>
                            <button name="action" value="resetkoin" class="btn-icon btn-info" title="Reset 1000" onclick="return confirm('Reset saldo ke 1000?')"><i class="fas fa-redo"></i></button>
                            <button name="action" value="delete" class="btn-icon btn-danger" title="Hapus" onclick="return confirm('Hapus user ini?')"><i class="fas fa-trash"></i></button>
                        </form>
                        <?php else: ?><span class="badge badge-info">Kamu</span><?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN TRANSACTIONS ----------
cat > "$WEB_ROOT/admin/transactions.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    $tid = (int)($_POST['tid'] ?? 0);
    $action = $_POST['action'] ?? '';
    if ($tid && in_array($action, ['approve','reject'])) {
        $tx = $pdo->prepare("SELECT * FROM transactions WHERE id=? AND status='pending'"); $tx->execute([$tid]); $tx = $tx->fetch();
        if ($tx) {
            if ($action === 'approve') {
                if ($tx['type'] === 'deposit') {
                    $pdo->prepare("UPDATE users SET balance=balance+? WHERE id=?")->execute([$tx['amount'], $tx['user_id']]);
                } elseif ($tx['type'] === 'withdraw') {
                    $pdo->prepare("UPDATE users SET balance=balance-? WHERE id=?")->execute([$tx['amount'], $tx['user_id']]);
                }
                $pdo->prepare("UPDATE transactions SET status='approved' WHERE id=?")->execute([$tid]);
                $msg = 'Transaksi di-approve';
            } else {
                $pdo->prepare("UPDATE transactions SET status='rejected' WHERE id=?")->execute([$tid]);
                $msg = 'Transaksi di-reject';
            }
            logAct($pdo, $_SESSION['user_id'], "Admin: $action transaksi $tid");
        }
    }
}
$txs = $pdo->query("SELECT t.*, u.username FROM transactions t LEFT JOIN users u ON t.user_id=u.id ORDER BY t.status='pending' DESC, t.id DESC LIMIT 100")->fetchAll();
$pageTitle = 'Transaksi';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header"><h1><i class="fas fa-exchange-alt"></i> Transaksi</h1><p>Approve/reject deposit & withdraw user</p></div>
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <div class="card">
        <table class="table">
            <thead><tr><th>ID</th><th>User</th><th>Tipe</th><th>Jumlah</th><th>Status</th><th>Catatan</th><th>Aksi</th></tr></thead>
            <tbody>
                <?php foreach ($txs as $t): ?>
                <tr>
                    <td>#<?= $t['id'] ?></td>
                    <td><?= htmlspecialchars($t['username'] ?? 'N/A') ?></td>
                    <td><span class="badge badge-<?= $t['type']=='deposit'?'info':($t['type']=='withdraw'?'warning':'active') ?>"><?= strtoupper($t['type']) ?></span></td>
                    <td><strong><?= rupiah($t['amount']) ?></strong></td>
                    <td><span class="badge badge-<?= $t['status']=='approved'?'active':($t['status']=='rejected'?'banned':'user') ?>"><?= $t['status'] ?></span></td>
                    <td><small><?= htmlspecialchars($t['note']) ?></small></td>
                    <td class="actions">
                        <?php if ($t['status'] === 'pending'): ?>
                        <form method="POST" style="display:inline-flex;gap:3px">
                            <input type="hidden" name="csrf" value="<?= csrf() ?>">
                            <input type="hidden" name="tid" value="<?= $t['id'] ?>">
                            <button name="action" value="approve" class="btn-icon btn-ok" title="Approve"><i class="fas fa-check"></i></button>
                            <button name="action" value="reject" class="btn-icon btn-danger" title="Reject"><i class="fas fa-times"></i></button>
                        </form>
                        <?php else: ?>-<?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN GAMES ----------
cat > "$WEB_ROOT/admin/games.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$games = $pdo->query("SELECT g.*, u.username FROM games g LEFT JOIN users u ON g.user_id=u.id ORDER BY g.id DESC LIMIT 100")->fetchAll();
$pageTitle = 'Semua Game';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header"><h1><i class="fas fa-dice"></i> Semua Game</h1><p>100 game terakhir</p></div>
    <div class="card">
        <table class="table">
            <thead><tr><th>Waktu</th><th>User</th><th>Bet</th><th>Tebak</th><th>Dadu</th><th>Total</th><th>Hasil</th><th>Payout</th></tr></thead>
            <tbody>
                <?php foreach ($games as $g): ?>
                <tr>
                    <td><small><?= date('d/m H:i', strtotime($g['created_at'])) ?></small></td>
                    <td><?= htmlspecialchars($g['username'] ?? 'N/A') ?></td>
                    <td><?= rupiah($g['bet_amount']) ?></td>
                    <td><span class="badge badge-<?= $g['guess']=='K'?'info':'warning' ?>"><?= $g['guess']=='K'?'KECIL':'BESAR' ?></span></td>
                    <td><?= $g['dice1'] ?>+<?= $g['dice2'] ?>+<?= $g['dice3'] ?></td>
                    <td><strong><?= $g['total'] ?></strong></td>
                    <td><?= $g['win'] ? '<span class="badge badge-active">WIN</span>' : '<span class="badge badge-banned">LOSE</span>' ?></td>
                    <td><?= $g['win'] ? '+'.rupiah($g['payout']) : '-' ?></td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN SETTINGS (RTP) ----------
cat > "$WEB_ROOT/admin/settings.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    foreach (['site_name','rtp_small','rtp_big','payout_multiplier','min_bet','max_bet','daily_bonus','min_deposit','min_withdraw'] as $k) {
        if (isset($_POST[$k])) {
            $pdo->prepare("UPDATE settings SET value=? WHERE key_name=?")->execute([$_POST[$k], $k]);
        }
    }
    $msg = 'Setting disimpan!';
    logAct($pdo, $_SESSION['user_id'], 'Update setting');
}
$get = function($k) use ($pdo) { return getSetting($pdo, $k); };
$pageTitle = 'Setting';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container-narrow">
    <div class="card">
        <h1><i class="fas fa-cog"></i> Setting Game</h1>
        <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label><i class="fas fa-tag"></i> Nama Website</label><input type="text" name="site_name" value="<?= htmlspecialchars($get('site_name')) ?>"></div>
            <hr style="margin:20px 0;border-color:var(--border)">
            <h3 style="margin-bottom:15px"><i class="fas fa-percentage"></i> RTP (Win Rate)</h3>
            <p style="color:#888;font-size:0.85em;margin-bottom:15px">Persentase menang user. 45 = 45% chance menang. Range: 0-100.</p>
            <div class="form-group"><label>RTP Tebak KECIL (%)</label><input type="number" name="rtp_small" min="0" max="100" value="<?= $get('rtp_small') ?>"></div>
            <div class="form-group"><label>RTP Tebak BESAR (%)</label><input type="number" name="rtp_big" min="0" max="100" value="<?= $get('rtp_big') ?>"></div>
            <hr style="margin:20px 0;border-color:var(--border)">
            <h3 style="margin-bottom:15px"><i class="fas fa-coins"></i> Ekonomi</h3>
            <div class="form-group"><label>Payout Multiplier (menang x berapa)</label><input type="number" step="0.1" name="payout_multiplier" value="<?= $get('payout_multiplier') ?>"></div>
            <div class="form-group"><label>Min Bet</label><input type="number" name="min_bet" value="<?= $get('min_bet') ?>"></div>
            <div class="form-group"><label>Max Bet</label><input type="number" name="max_bet" value="<?= $get('max_bet') ?>"></div>
            <div class="form-group"><label>Daily Bonus Koin</label><input type="number" name="daily_bonus" value="<?= $get('daily_bonus') ?>"></div>
            <div class="form-group"><label>Min Deposit</label><input type="number" name="min_deposit" value="<?= $get('min_deposit') ?>"></div>
            <div class="form-group"><label>Min Withdraw</label><input type="number" name="min_withdraw" value="<?= $get('min_withdraw') ?>"></div>
            <button class="btn btn-primary btn-block"><i class="fas fa-save"></i> Simpan Setting</button>
        </form>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

echo -e "${GREEN}  ✓ Semua halaman dibuat${NC}"

# ============ STEP 6: CSS & JS ============
echo -e "${CYAN}[6/7] Bikin CSS & JS...${NC}"

cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
:root {
    --bg:#0f172a; --bg-card:#1e293b; --bg-nav:#1e293b;
    --text:#e2e8f0; --text-muted:#94a3b8; --border:#334155;
    --primary:#6366f1; --primary-hover:#4f46e5;
    --success:#10b981; --danger:#ef4444; --warning:#f59e0b; --info:#3b82f6;
    --gold:#fbbf24; --shadow:0 2px 12px rgba(0,0,0,0.3);
}
[data-theme="light"] {
    --bg:#f5f7fb; --bg-card:#fff; --bg-nav:#fff;
    --text:#2c3e50; --text-muted:#7f8c8d; --border:#e1e8ed;
    --primary:#4f46e5; --shadow:0 2px 12px rgba(0,0,0,0.06);
}
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',Tahoma,sans-serif; background:var(--bg); color:var(--text); line-height:1.6; transition:.3s; }
a { color:var(--primary); text-decoration:none; }
a:hover { opacity:.85; }

/* NAVBAR */
.navbar { display:flex; justify-content:space-between; align-items:center; padding:12px 30px; background:var(--bg-nav); border-bottom:1px solid var(--border); box-shadow:var(--shadow); position:sticky; top:0; z-index:100; flex-wrap:wrap; gap:12px; }
.nav-left .logo { font-size:1.3em; font-weight:700; color:var(--primary); display:flex; align-items:center; gap:8px; }
.nav-center { display:flex; gap:20px; }
.nav-center a { color:var(--text-muted); font-weight:500; display:flex; align-items:center; gap:5px; }
.nav-center a:hover { color:var(--primary); }
.nav-right { display:flex; align-items:center; gap:10px; }
.balance-chip { background:linear-gradient(135deg,#fbbf24,#f59e0b); color:#1a1a2e; padding:8px 14px; border-radius:20px; font-weight:700; display:flex; align-items:center; gap:6px; font-size:.9em; }
.icon-btn { background:transparent; border:1px solid var(--border); color:var(--text); padding:8px 12px; border-radius:8px; cursor:pointer; transition:.2s; display:inline-flex; align-items:center; gap:6px; }
.icon-btn:hover { background:var(--primary); color:#fff; border-color:var(--primary); }
.user-menu { position:relative; }
.dropdown { display:none; position:absolute; right:0; top:100%; background:var(--bg-card); border:1px solid var(--border); border-radius:10px; min-width:180px; box-shadow:var(--shadow); padding:8px; z-index:200; }
.user-menu:hover .dropdown, .user-menu.open .dropdown { display:block; }
.dropdown a { display:flex; align-items:center; gap:10px; padding:10px 12px; color:var(--text); border-radius:6px; }
.dropdown a:hover { background:var(--bg); color:var(--primary); }

/* BUTTONS */
.btn { padding:10px 20px; border-radius:8px; border:none; cursor:pointer; font-weight:600; display:inline-flex; align-items:center; gap:8px; transition:.2s; text-decoration:none; font-size:.95em; }
.btn-primary { background:var(--primary); color:#fff; }
.btn-primary:hover { background:var(--primary-hover); transform:translateY(-2px); }
.btn-outline { background:transparent; border:2px solid var(--primary); color:var(--primary); }
.btn-outline:hover { background:var(--primary); color:#fff; }
.btn-block { width:100%; justify-content:center; }
.btn-lg { padding:14px 28px; font-size:1.05em; }
.btn-icon { background:transparent; border:1px solid var(--border); padding:6px 10px; border-radius:6px; cursor:pointer; color:var(--text); transition:.2s; }
.btn-icon:hover { color:#fff; }
.btn-warn:hover { background:var(--warning); border-color:var(--warning); }
.btn-ok:hover { background:var(--success); border-color:var(--success); }
.btn-info:hover { background:var(--info); border-color:var(--info); }
.btn-danger:hover { background:var(--danger); border-color:var(--danger); }

/* HERO */
.hero { min-height:60vh; display:flex; align-items:center; justify-content:center; text-align:center; padding:60px 30px; background:linear-gradient(135deg,#4f46e5,#7c3aed,#ec4899); color:#fff; position:relative; overflow:hidden; }
.hero::before { content:'🎲'; position:absolute; font-size:15em; opacity:.05; top:50%; left:50%; transform:translate(-50%,-50%); }
.hero-content { position:relative; z-index:1; }
.hero h1 { font-size:3em; margin-bottom:20px; }
.hero p { font-size:1.15em; max-width:700px; margin:0 auto 30px; }
.btn-group { display:flex; gap:15px; justify-content:center; flex-wrap:wrap; }

/* FEATURES */
.features { padding:60px 30px; max-width:1200px; margin:0 auto; }
.features h2 { text-align:center; font-size:2em; margin-bottom:40px; }
.feature-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(230px,1fr)); gap:20px; }
.feature-card { background:var(--bg-card); padding:25px; border-radius:14px; border:1px solid var(--border); text-align:center; transition:.3s; }
.feature-card:hover { transform:translateY(-5px); box-shadow:var(--shadow); border-color:var(--primary); }
.feature-card i { font-size:2.2em; color:var(--primary); margin-bottom:15px; }
.feature-card h3 { margin-bottom:8px; }
.feature-card p { color:var(--text-muted); font-size:.9em; }

/* AUTH */
.auth-wrap { min-height:70vh; display:flex; align-items:center; justify-content:center; padding:40px 20px; }
.auth-card { background:var(--bg-card); padding:40px; border-radius:16px; box-shadow:var(--shadow); max-width:420px; width:100%; border:1px solid var(--border); }
.auth-card h1 { font-size:1.6em; margin-bottom:8px; display:flex; align-items:center; gap:10px; color:var(--primary); }
.auth-card .subtitle { color:var(--text-muted); margin-bottom:25px; font-size:.9em; }
.auth-footer { text-align:center; margin-top:20px; color:var(--text-muted); font-size:.9em; }

/* FORM */
.form-group { margin-bottom:18px; }
.form-group label { display:block; margin-bottom:6px; font-weight:600; font-size:.9em; }
.form-group label i { color:var(--primary); margin-right:5px; }
.form-group input, .form-group select, .form-group textarea { width:100%; padding:12px 14px; border:1px solid var(--border); border-radius:8px; background:var(--bg); color:var(--text); font-size:.95em; font-family:inherit; }
.form-group input:focus { outline:none; border-color:var(--primary); box-shadow:0 0 0 3px rgba(99,102,241,.15); }

/* ALERTS */
.alert { padding:12px 16px; border-radius:8px; margin-bottom:15px; font-size:.9em; }
.alert-error { background:rgba(239,68,68,.1); color:var(--danger); border-left:4px solid var(--danger); }
.alert-success { background:rgba(16,185,129,.1); color:var(--success); border-left:4px solid var(--success); }

/* CONTAINER */
.container { max-width:1200px; margin:0 auto; padding:30px; }
.container-narrow { max-width:600px; margin:0 auto; padding:30px; }
.page-header { margin-bottom:25px; }
.page-header h1 { font-size:1.8em; display:flex; align-items:center; gap:10px; }
.page-header h1 i { color:var(--primary); }
.page-header p { color:var(--text-muted); margin-top:5px; }

/* GAME */
.game-header { text-align:center; margin-bottom:30px; }
.game-header h1 { font-size:2.2em; color:var(--primary); }
.game-layout { display:grid; grid-template-columns:1.5fr 1fr; gap:25px; margin-bottom:30px; }
.game-board { background:linear-gradient(135deg,#1e293b,#0f172a); border:2px solid var(--border); border-radius:20px; padding:40px 20px; text-align:center; }
.dice-container { display:flex; justify-content:center; gap:20px; margin-bottom:25px; flex-wrap:wrap; }
.dice { font-size:5em; line-height:1; background:var(--bg-card); width:120px; height:120px; border-radius:20px; display:flex; align-items:center; justify-content:center; border:2px solid var(--border); box-shadow:0 8px 25px rgba(0,0,0,.3); transition:.3s; }
.dice.rolling { animation:shake .15s infinite; }
@keyframes shake { 0%{transform:rotate(-10deg)} 50%{transform:rotate(10deg) scale(1.05)} 100%{transform:rotate(-10deg)} }
.total-display { font-size:2em; font-weight:700; color:var(--gold); margin-bottom:15px; }
.result-display { font-size:1.3em; font-weight:700; padding:15px; border-radius:12px; min-height:60px; display:flex; align-items:center; justify-content:center; }
.result-display.win { background:rgba(16,185,129,.15); color:var(--success); }
.result-display.lose { background:rgba(239,68,68,.15); color:var(--danger); }

.bet-panel { background:var(--bg-card); border:2px solid var(--border); border-radius:20px; padding:25px; }
.balance-big { font-size:1.5em; font-weight:700; text-align:center; margin-bottom:20px; color:var(--gold); }
.quick-bet { display:grid; grid-template-columns:repeat(5,1fr); gap:8px; margin-bottom:20px; }
.quick-bet button { padding:10px 5px; background:var(--bg); border:1px solid var(--border); color:var(--text); border-radius:8px; cursor:pointer; font-weight:600; transition:.2s; }
.quick-bet button:hover { background:var(--primary); color:#fff; border-color:var(--primary); }
.bet-buttons { display:grid; grid-template-columns:1fr 1fr; gap:15px; }
.bet-btn { padding:25px 15px; border:none; border-radius:14px; cursor:pointer; font-weight:700; font-size:1.1em; color:#fff; transition:.3s; display:flex; flex-direction:column; align-items:center; gap:8px; }
.bet-btn.small { background:linear-gradient(135deg,#3b82f6,#1d4ed8); }
.bet-btn.big { background:linear-gradient(135deg,#f59e0b,#dc2626); }
.bet-btn:hover { transform:translateY(-3px); box-shadow:0 10px 25px rgba(0,0,0,.3); }
.bet-btn:active { transform:translateY(0); }

/* STATS */
.stats-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:18px; margin-bottom:25px; }
.stat-card { background:var(--bg-card); padding:20px; border-radius:12px; box-shadow:var(--shadow); display:flex; align-items:center; gap:15px; border:1px solid var(--border); }
.stat-icon { width:55px; height:55px; border-radius:12px; display:flex; align-items:center; justify-content:center; color:#fff; font-size:1.5em; flex-shrink:0; }
.stat-info h3 { font-size:1.4em; margin:0; }
.stat-info p { color:var(--text-muted); font-size:.85em; margin:0; }

/* CARD */
.card { background:var(--bg-card); padding:25px; border-radius:14px; box-shadow:var(--shadow); margin-bottom:25px; border:1px solid var(--border); }
.card h1, .card h2 { margin-bottom:20px; display:flex; align-items:center; gap:10px; font-size:1.3em; }
.card h1 i, .card h2 i { color:var(--primary); }
.grid-2 { display:grid; grid-template-columns:repeat(auto-fit,minmax(350px,1fr)); gap:20px; }

/* TABLE */
.table { width:100%; border-collapse:collapse; }
.table th { text-align:left; padding:12px; background:var(--bg); border-bottom:2px solid var(--border); font-size:.8em; text-transform:uppercase; color:var(--text-muted); }
.table td { padding:12px; border-bottom:1px solid var(--border); }
.table tr:hover td { background:var(--bg); }
.table code { background:var(--bg); padding:2px 6px; border-radius:4px; font-size:.85em; }

/* BADGES */
.badge { padding:4px 10px; border-radius:20px; font-size:.72em; font-weight:700; text-transform:uppercase; display:inline-block; }
.badge-admin { background:rgba(245,158,11,.15); color:var(--warning); }
.badge-user { background:rgba(59,130,246,.15); color:var(--info); }
.badge-active { background:rgba(16,185,129,.15); color:var(--success); }
.badge-banned { background:rgba(239,68,68,.15); color:var(--danger); }
.badge-info { background:rgba(99,102,241,.15); color:var(--primary); }
.badge-warning { background:rgba(245,158,11,.15); color:var(--warning); }

/* QUICK ACTIONS */
.quick-actions { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:15px; margin-bottom:25px; }
.action-btn { background:var(--bg-card); padding:22px; border-radius:12px; border:2px solid var(--border); text-align:center; transition:.3s; color:var(--text); display:flex; flex-direction:column; gap:10px; align-items:center; }
.action-btn:hover { border-color:var(--primary); transform:translateY(-3px); box-shadow:var(--shadow); }
.action-btn i { font-size:2em; color:var(--primary); }
.action-btn span { font-weight:600; font-size:.9em; }

/* FOOTER */
.footer { text-align:center; padding:25px; color:var(--text-muted); border-top:1px solid var(--border); margin-top:50px; font-size:.9em; }

/* RESPONSIVE */
@media (max-width:768px) {
    .navbar { padding:12px 15px; }
    .nav-center { order:3; width:100%; justify-content:center; flex-wrap:wrap; gap:12px; }
    .hero h1 { font-size:1.9em; }
    .game-layout { grid-template-columns:1fr; }
    .dice { width:80px; height:80px; font-size:3em; }
    .dice-container { gap:10px; }
    .grid-2 { grid-template-columns:1fr; }
    .table { font-size:.82em; }
    .table th, .table td { padding:8px 6px; }
    .balance-chip { font-size:.8em; padding:6px 10px; }
    .user-btn span { display:none; }
}
CSSEOF

cat > "$WEB_ROOT/assets/js/main.js" << 'JSEOF'
// Theme
const tt = document.getElementById('themeToggle');
const saved = localStorage.getItem('theme') || 'dark';
document.documentElement.setAttribute('data-theme', saved);
updateIcon(saved);
if (tt) tt.addEventListener('click', () => {
    const c = document.documentElement.getAttribute('data-theme');
    const n = c === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', n);
    localStorage.setItem('theme', n);
    updateIcon(n);
});
function updateIcon(t) { const i = tt?.querySelector('i'); if (i) i.className = t === 'dark' ? 'fas fa-sun' : 'fas fa-moon'; }

// User menu
document.querySelectorAll('.user-btn').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); b.parentElement.classList.toggle('open'); }));
document.addEventListener('click', () => document.querySelectorAll('.user-menu').forEach(m => m.classList.remove('open')));
JSEOF

echo -e "${GREEN}  ✓ CSS & JS dibuat${NC}"

# ============ STEP 7: NGINX + SSL ============
echo -e "${CYAN}[7/7] Konfigurasi Nginx & SSL...${NC}"

cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $SUBDOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    client_max_body_size 10M;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
    location ~ /\.(?!well-known).* { deny all; }
    location ~* \.(env|log|sql)\$ { deny all; }
    access_log /var/log/nginx/$SUBDOMAIN.access.log;
    error_log /var/log/nginx/$SUBDOMAIN.error.log;
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
[[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "${GREEN}  ✓ Nginx OK${NC}"
else
    echo -e "${RED}  ✗ Nginx error!${NC}"; nginx -t; exit 1
fi

chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
chmod 640 "$WEB_ROOT/includes/config.php"
systemctl restart php8.3-fpm

# SSL
SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s ifconfig.co 2>/dev/null)
DOMAIN_IP=$(dig +short A "$SUBDOMAIN" @8.8.8.8 2>/dev/null | head -1)
[[ -z "$DOMAIN_IP" ]] && DOMAIN_IP=$(getent ahostsv4 "$SUBDOMAIN" 2>/dev/null | awk '{print $1}' | head -1)

SSL_STATUS="dilewati"
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]] || [[ -f "/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem" ]]; then
    apt install certbot python3-certbot-nginx -y -qq 2>/dev/null
    if certbot --nginx -d "$SUBDOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; then
        SSL_STATUS="aktif ✅"
        echo -e "${GREEN}  ✓ SSL aktif${NC}"
    else
        # Coba existing cert
        if [[ -f "/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem" ]]; then
            SSL_STATUS="aktif (existing) ✅"
        else
            SSL_STATUS="gagal ⚠️"
            echo -e "${YELLOW}  ⚠️  SSL gagal. Coba manual: certbot --nginx -d $SUBDOMAIN${NC}"
        fi
    fi
else
    echo -e "${YELLOW}  ⚠️  DNS: Server=$SERVER_IP Domain=$DOMAIN_IP${NC}"
    [[ -f "/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem" ]] && SSL_STATUS="aktif (existing) ✅"
fi

# Firewall
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
fi

# ============ SELESAI ============
PROTO="https"; [[ "$SSL_STATUS" == *"gagal"* || "$SSL_STATUS" == "dilewati" ]] && PROTO="http"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎲 DUELAN DADU GO — INSTALL BERHASIL!         ${NC} ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 AKSES:${NC}"
echo -e "  Home     : ${YELLOW}$PROTO://$SUBDOMAIN${NC}"
echo -e "  Login    : ${YELLOW}$PROTO://$SUBDOMAIN/login.php${NC}"
echo -e "  Register : ${YELLOW}$PROTO://$SUBDOMAIN/register.php${NC}"
echo -e "  Admin    : ${YELLOW}$PROTO://$SUBDOMAIN/admin/${NC}"
echo ""
echo -e "${MAGENTA}🔑 ADMIN LOGIN:${NC}"
echo -e "  Username : ${YELLOW}$ADMIN_USER${NC}"
echo -e "  Password : ${YELLOW}$ADMIN_PASS${NC}"
echo ""
echo -e "${CYAN}📊 INFO:${NC}"
echo -e "  Web Root  : $WEB_ROOT"
echo -e "  Database  : $DB_NAME"
echo -e "  DB User   : daduuser"
echo -e "  DB Pass   : $DB_PASS"
echo -e "  SSL       : $SSL_STATUS"
echo ""
echo -e "${CYAN}⚙️  DEFAULT SETTING:${NC}"
echo -e "  RTP Kecil : 45%"
echo -e "  RTP Besar : 45%"
echo -e "  Payout    : x2.1"
echo -e "  Min Bet   : 100"
echo -e "  Max Bet   : 10000"
echo -e "  Min Depo  : 10000"
echo -e "  Min WD    : 10000"
echo ""
echo -e "${GREEN}🎉 Tinggal buka di browser & mulai main!${NC}"
