#!/usr/bin/env bash
# PR GRAM Helper - نصب‌کننده (Ubuntu/Debian/Fedora/Rocky ... روی VPS مثل Doprax)
# استفاده:  sudo bash install.sh
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/prgram}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_ok=$'\e[32m'; c_err=$'\e[31m'; c_inf=$'\e[36m'; c_off=$'\e[0m'
ok()  { echo "${c_ok}✔${c_off} $*"; }
inf() { echo "${c_inf}➜${c_off} $*"; }
die() { echo "${c_err}✖ $*${c_off}" >&2; exit 1; }
trap 'die "خطا در خط $LINENO"' ERR

[[ $EUID -eq 0 ]] || die "با root اجرا کن: sudo bash install.sh"

# ---------- 1) پیش‌نیازها ----------
inf "نصب پیش‌نیازها..."
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y curl ca-certificates openssl tar gzip
elif command -v dnf >/dev/null; then
  dnf install -y curl ca-certificates openssl tar gzip
elif command -v yum >/dev/null; then
  yum install -y curl ca-certificates openssl tar gzip
else
  die "پکیج‌منیجر پشتیبانی نمی‌شه"
fi

if ! command -v docker >/dev/null; then
  inf "نصب Docker..."
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker compose version >/dev/null 2>&1 || die "docker compose v2 پیدا نشد (پکیج docker-compose-plugin رو نصب کن)"
ok "Docker آماده است"

# ---------- 2) فایل‌ها ----------
mkdir -p "$INSTALL_DIR/data"
for f in app.py panel_ui.html requirements.txt Dockerfile docker-compose.yml .dockerignore .env.example; do
  [[ -f "$SRC_DIR/$f" ]] || die "فایل $f کنار install.sh نیست"
  cp -f "$SRC_DIR/$f" "$INSTALL_DIR/$f"
done
chown -R 1000:1000 "$INSTALL_DIR/data"   # کاربر داخل کانتینر uid 1000 است
ok "فایل‌ها در $INSTALL_DIR کپی شد"

# ---------- 3) تنظیمات .env ----------
ENV_FILE="$INSTALL_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  ok ".env موجود است؛ دست نمی‌خورد"
else
  cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
  read -rp "BOT_TOKEN (از BotFather): " BOT_TOKEN
  read -rp "OWNER_ID (آیدی عددی تلگرام خودت): " OWNER_ID
  read -rp "API_ID (خالی = پیش‌فرض عمومی، پیشنهاد نمی‌شه): " API_ID || true
  API_HASH=""; [[ -n "${API_ID:-}" ]] && read -rp "API_HASH: " API_HASH
  read -rp "WEB_BASE_URL (مثلا https://panel.example.com ، خالی = بعدا): " WEB_BASE_URL || true
  [[ -n "$BOT_TOKEN" && "$OWNER_ID" =~ ^[0-9]+$ ]] || die "BOT_TOKEN یا OWNER_ID نامعتبر است"
  SESSION_KEY="$(head -c32 /dev/urandom | base64 | tr '+/' '-_')"   # فرمت کلید Fernet
  sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=$BOT_TOKEN|;s|^OWNER_ID=.*|OWNER_ID=$OWNER_ID|;s|^SESSION_KEY=.*|SESSION_KEY=$SESSION_KEY|;s|^API_ID=.*|API_ID=${API_ID:-}|;s|^API_HASH=.*|API_HASH=${API_HASH:-}|;s|^WEB_BASE_URL=.*|WEB_BASE_URL=${WEB_BASE_URL:-}|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok ".env ساخته شد"
  echo "${c_err}⚠ SESSION_KEY داخل $ENV_FILE است. یک نسخه از آن را جای امن (بیرون از سرور) نگه دار؛ بدون آن نشست‌ها قابل بازیابی نیستند.${c_off}"
fi

# ---------- 4) selfpanel ----------
if [[ -f "$SRC_DIR/selfpanel" ]]; then
  install -m 0755 "$SRC_DIR/selfpanel" /usr/local/bin/selfpanel
  ok "دستور selfpanel نصب شد"
fi

# ---------- 5) swap برای سرور کم‌رم ----------
mem_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
if (( mem_mb < 1500 )) && ! swapon --show | grep -q .; then
  inf "RAM کم است (${mem_mb}MB)؛ ساخت 1GB swap..."
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "swap فعال شد"
fi

# ---------- 6) بیلد و اجرا ----------
inf "بیلد و اجرا..."
cd "$INSTALL_DIR"
docker compose up -d --build
sleep 6
docker compose ps
echo
ok "نصب تمام شد. برای مدیریت تایپ کن:  ${c_inf}selfpanel${c_off}"
echo "لینک ادمین: selfpanel  ←  گزینه Admin link"
