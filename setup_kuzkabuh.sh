#!/bin/bash
set -e

echo "Обновляем систему и ставим зависимости..."
apt update && apt upgrade -y
apt install -y python3 python3-venv python3-pip git nginx certbot python3-certbot-nginx sqlite3

echo "Создаём директории..."
mkdir -p /root/kuzkabuh/bots/kuzkabuh_bot
mkdir -p /root/kuzkabuh/bots/kuzkainfo_bot
mkdir -p /root/kuzkabuh/admin

echo "Создаём Python venv..."
cd /root/kuzkabuh
python3 -m venv venv
source venv/bin/activate

echo "Устанавливаем Python-пакеты..."
pip install --upgrade pip
pip install aiogram flask flask-admin sqlalchemy aiosqlite python-dotenv

echo "Клонируем репозиторий (создай свой или вручную перенеси исходники)..."
# git clone https://github.com/majestictech-git/kuzkabuh_bot/kuzkabot.git . || echo "Пропусти если репозиторий не создан"

echo "Создаём файл .env ..."
cat > /root/kuzkabuh/.env << EOF
ADMIN_ID=7544110392
DADATA_API_KEY=1e0cd0aa87855845cc582b0a4fc297e1dcafebde
KUZKABUH_BOT_TOKEN=8063258205:AAGOpmm12a9OIzoQg7K9s6dpHuRnmyhq0RY
KUZKAINFO_BOT_TOKEN=7669930857:AAGxw5McWTQzMEN4_qJJZIXh0rI7_b7hsDc
EOF

echo "Создаём models.py (общая для всех ботов и админки)..."
cat > /root/kuzkabuh/models.py << 'EOF'
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func

DATABASE_URL = "sqlite+aiosqlite:///kuzkabuh.db"
engine = create_async_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    telegram_id = Column(Integer, unique=True, nullable=False)
    name = Column(String)
    email = Column(String)
    phone = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Request(Base):
    __tablename__ = "requests"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer)
    inn = Column(String)
    services = Column(String)
    urgent = Column(Boolean, default=False)
    status = Column(String, default="new")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Admin(Base):
    __tablename__ = "admins"
    id = Column(Integer, primary_key=True)
    username = Column(String, unique=True, nullable=False)
    password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
EOF

echo "Создаём database.py..."
cat > /root/kuzkabuh/database.py << 'EOF'
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from models import Base, engine

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
SessionLocal = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
EOF

echo "Инициализируем базу данных..."
python3 -c "import asyncio; from database import init_db; asyncio.run(init_db())"

echo "Создаём простой bot.py для kuzkabuh_bot..."
cat > /root/kuzkabuh/bots/kuzkabuh_bot/bot.py << 'EOF'
import asyncio
import logging
import os
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from dotenv import load_dotenv

load_dotenv('../../.env')
API_TOKEN = os.getenv("KUZKABUH_BOT_TOKEN")

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

@dp.message(Command("start"))
async def start(message: types.Message):
    await message.answer("Привет! Это BUH.KUZ'KA бот. Задавайте вопросы!")

async def main():
    logging.basicConfig(level=logging.INFO)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

echo "Создаём bot.py для kuzkainfo_bot (информатор)..."
cat > /root/kuzkabuh/bots/kuzkainfo_bot/bot.py << 'EOF'
import asyncio
import logging
import os
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from dotenv import load_dotenv

load_dotenv('../../.env')
API_TOKEN = os.getenv("KUZKAINFO_BOT_TOKEN")

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

@dp.message(Command("start"))
async def start(message: types.Message):
    await message.answer("Привет! Это KUZKAINFO бот. Новости и важная информация для селлеров и турагентов!")

async def main():
    logging.basicConfig(level=logging.INFO)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

echo "Создаём flask_admin_app.py (админка)..."
cat > /root/kuzkabuh/admin/flask_admin_app.py << 'EOF'
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from flask import Flask
from flask_admin import Admin
from flask_admin.contrib.sqla import ModelView
from sqlalchemy.orm import sessionmaker
from models import User, Request, Admin
from database import engine

app = Flask(__name__)
app.secret_key = 'kuzkabuhsupersecret'
admin = Admin(app)

Session = sessionmaker(bind=engine.sync_engine)
session = Session()

admin.add_view(ModelView(User, session))
admin.add_view(ModelView(Request, session))
admin.add_view(ModelView(Admin, session))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9000)
EOF

echo "Создаём systemd-сервис для kuzkabuh_bot..."
cat > /etc/systemd/system/kuzkabuh_bot.service << EOF
[Unit]
Description=KUZKABUH Telegram Bot
After=network.target

[Service]
WorkingDirectory=/root/kuzkabuh/bots/kuzkabuh_bot
ExecStart=/root/kuzkabuh/venv/bin/python3 /root/kuzkabuh/bots/kuzkabuh_bot/bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Создаём systemd-сервис для kuzkainfo_bot..."
cat > /etc/systemd/system/kuzkainfo_bot.service << EOF
[Unit]
Description=KUZKAINFO Telegram Bot
After=network.target

[Service]
WorkingDirectory=/root/kuzkabuh/bots/kuzkainfo_bot
ExecStart=/root/kuzkabuh/venv/bin/python3 /root/kuzkabuh/bots/kuzkainfo_bot/bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Создаём systemd-сервис для Flask-Admin..."
cat > /etc/systemd/system/kuzkabuh_admin.service << EOF
[Unit]
Description=KUZKABUH Flask Admin
After=network.target

[Service]
WorkingDirectory=/root/kuzkabuh/admin
ExecStart=/root/kuzkabuh/venv/bin/python3 /root/kuzkabuh/admin/flask_admin_app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Настраиваем автозапуск сервисов..."
systemctl daemon-reload
systemctl enable kuzkabuh_bot.service
systemctl enable kuzkainfo_bot.service
systemctl enable kuzkabuh_admin.service

echo "Запускаем сервисы..."
systemctl start kuzkabuh_bot.service
systemctl start kuzkainfo_bot.service
systemctl start kuzkabuh_admin.service

echo "Готовим Nginx конфиг..."
cat > /etc/nginx/sites-available/bot.kuzkabuh.ru << EOF
server {
    listen 80;
    server_name bot.kuzkabuh.ru;

    location /admin/ {
        proxy_pass http://127.0.0.1:9000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location / {
        return 444;
    }
}
EOF

ln -sf /etc/nginx/sites-available/bot.kuzkabuh.ru /etc/nginx/sites-enabled/bot.kuzkabuh.ru

echo "Перезапускаем Nginx..."
systemctl restart nginx

echo "Настраиваем Let's Encrypt SSL..."
certbot --nginx -d bot.kuzkabuh.ru --agree-tos --register-unsafely-without-email --redirect

echo "Готово! Всё установлено и запущено."
echo "Проверь:"
echo "- Бот: работает ли в Telegram (@kuzkabuh_bot и @kuzkainfo_bot)"
echo "- Админка: https://bot.kuzkabuh.ru/admin/"
