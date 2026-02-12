import os, json, time
import telebot
from telebot import types

TOKEN = "{{BOT_TOKEN}}"
ADMIN_ID = int("{{ADMIN_ID}}")

BUSINESS_NAME = "{{BUSINESS_NAME}}"
CURRENCY = "{{CURRENCY}}"
SUPPORT_USERNAME = "{{SUPPORT_USERNAME}}"

bot = telebot.TeleBot(TOKEN)

DATA_DIR = "data"
PRODUCTS_PATH = os.path.join(DATA_DIR, "products.json")
ORDERS_PATH = os.path.join(DATA_DIR, "orders.json")

os.makedirs(DATA_DIR, exist_ok=True)

# ---------- storage ----------
def load_json(path, default):
    if not os.path.isfile(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def export_bytes(path):
    with open(path, "rb") as f:
        return f.read()

def import_bytes(path, b):
    with open(path, "wb") as f:
        f.write(b)

# ---------- keyboards ----------
def kb_main(user_id: int):
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.add(types.KeyboardButton("📦 Каталог"), types.KeyboardButton("🔎 Поиск"))
    kb.add(types.KeyboardButton("🛒 Заказать"), types.KeyboardButton("📞 Контакты"))
    if user_id == ADMIN_ID:
        kb.add(types.KeyboardButton("🛠 Админка"))
    return kb

def kb_admin():
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.add(types.KeyboardButton("➕ Добавить товар"), types.KeyboardButton("🗑 Удалить товар"))
    kb.add(types.KeyboardButton("✏️ Изменить цену"), types.KeyboardButton("📥 Заказы"))
    kb.add(types.KeyboardButton("📤 Экспорт базы"), types.KeyboardButton("📥 Импорт базы"))
    kb.add(types.KeyboardButton("🏠 Меню"))
    return kb

def kb_back():
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.add(types.KeyboardButton("🏠 Меню"))
    return kb

# ---------- helpers ----------
def fmt_product(p, i=None):
    idx = f"{i}. " if i is not None else ""
    cat = f"[{p.get('category','-')}] " if p.get("category") else ""
    stock = p.get("stock", "")
    stock_s = f" | Остаток: {stock}" if str(stock).strip() != "" else ""
    return f"{idx}{cat}{p['name']} — {p['price']} {CURRENCY}{stock_s}"

def is_admin(chat_id: int) -> bool:
    return chat_id == ADMIN_ID

# ---------- bot ----------
@bot.message_handler(commands=["start"])
def start(m):
    bot.send_message(
        m.chat.id,
        f"👋 {BUSINESS_NAME}\nВыберите действие:",
        reply_markup=kb_main(m.chat.id)
    )

@bot.message_handler(content_types=["text"])
def on_text(m):
    txt = (m.text or "").strip()

    if txt == "🏠 Меню":
        bot.send_message(m.chat.id, "Меню.", reply_markup=kb_main(m.chat.id))
        return

    if txt == "📞 Контакты":
        bot.send_message(
            m.chat.id,
            f"Связь: {SUPPORT_USERNAME}\nЗаказ: нажми «🛒 Заказать»",
            reply_markup=kb_main(m.chat.id)
        )
        return

    if txt == "📦 Каталог":
        products = load_json(PRODUCTS_PATH, [])
        if not products:
            bot.send_message(m.chat.id, "Каталог пуст.", reply_markup=kb_main(m.chat.id))
            return
        lines = [fmt_product(p, i+1) for i, p in enumerate(products)]
        bot.send_message(m.chat.id, "📦 Каталог:\n\n" + "\n".join(lines), reply_markup=kb_main(m.chat.id))
        return

    if txt == "🔎 Поиск":
        bot.send_message(m.chat.id, "Напиши слово для поиска (название/категория).", reply_markup=kb_back())
        bot.register_next_step_handler(m, search_step)
        return

    if txt == "🛒 Заказать":
        bot.send_message(
            m.chat.id,
            "Напиши заказ одним сообщением.\n"
            "Например:\n"
            "Товар: Масло 5W30\n"
            "Кол-во: 2\n"
            "Тел: +992...\n"
            "Адрес/город: ...",
            reply_markup=kb_back()
        )
        bot.register_next_step_handler(m, order_step)
        return

    if txt == "🛠 Админка":
        if not is_admin(m.chat.id):
            bot.send_message(m.chat.id, "Нет доступа 🙂", reply_markup=kb_main(m.chat.id))
            return
        bot.send_message(m.chat.id, "Админка:", reply_markup=kb_admin())
        return

    # admin actions
    if is_admin(m.chat.id):
        if txt == "➕ Добавить товар":
            bot.send_message(
                m.chat.id,
                "Отправь 4 строки:\n"
                "Название\nКатегория\nЦена\nОстаток (или 0)\n\n"
                "Пример:\nФильтр масляный\nToyota\n120\n5",
                reply_markup=kb_admin()
            )
            bot.register_next_step_handler(m, admin_add_product)
            return

        if txt == "🗑 Удалить товар":
            bot.send_message(m.chat.id, "Отправь номер товара из каталога (например 3).", reply_markup=kb_admin())
            bot.register_next_step_handler(m, admin_delete_product)
            return

        if txt == "✏️ Изменить цену":
            bot.send_message(m.chat.id, "Отправь 2 строки:\nНомер товара\nНовая цена", reply_markup=kb_admin())
            bot.register_next_step_handler(m, admin_change_price)
            return

        if txt == "📥 Заказы":
            show_orders(m.chat.id)
            return

        if txt == "📤 Экспорт базы":
            send_export(m.chat.id)
            return

        if txt == "📥 Импорт базы":
            bot.send_message(
                m.chat.id,
                "Отправь сюда файлы products.json и/или orders.json (как документ).",
                reply_markup=kb_admin()
            )
            return

    bot.send_message(m.chat.id, "Не понял. Выбери кнопку 🙂", reply_markup=kb_main(m.chat.id))

# ---------- steps ----------
def search_step(m):
    q = (m.text or "").strip().lower()
    products = load_json(PRODUCTS_PATH, [])
    found = []
    for p in products:
        hay = (p.get("name","") + " " + p.get("category","")).lower()
        if q and q in hay:
            found.append(p)

    if not found:
        bot.send_message(m.chat.id, "Ничего не найдено.", reply_markup=kb_main(m.chat.id))
        return
    lines = [fmt_product(p, i+1) for i, p in enumerate(found)]
    bot.send_message(m.chat.id, "🔎 Найдено:\n\n" + "\n".join(lines), reply_markup=kb_main(m.chat.id))

def order_step(m):
    text = (m.text or "").strip()
    if not text:
        bot.send_message(m.chat.id, "Нужно текстом 🙂", reply_markup=kb_main(m.chat.id))
        return

    orders = load_json(ORDERS_PATH, [])
    order = {
        "ts": int(time.time()),
        "user_id": m.chat.id,
        "text": text
    }
    orders.append(order)
    save_json(ORDERS_PATH, orders)

    bot.send_message(m.chat.id, "Заказ принят ✅ Мы свяжемся с тобой.", reply_markup=kb_main(m.chat.id))
    bot.send_message(ADMIN_ID, f"🛒 Новый заказ от {m.chat.id}:\n\n{text}")

def admin_add_product(m):
    parts = [x.strip() for x in (m.text or "").split("\n") if x.strip()]
    if len(parts) < 4:
        bot.send_message(m.chat.id, "Нужно 4 строки. Попробуй ещё раз.", reply_markup=kb_admin())
        return

    name, category, price, stock = parts[0], parts[1], parts[2], parts[3]
    products = load_json(PRODUCTS_PATH, [])
    products.append({"name": name, "category": category, "price": price, "stock": stock})
    save_json(PRODUCTS_PATH, products)
    bot.send_message(m.chat.id, "Товар добавлен ✅", reply_markup=kb_admin())

def admin_delete_product(m):
    n = (m.text or "").strip()
    if not n.isdigit():
        bot.send_message(m.chat.id, "Нужно число (номер товара).", reply_markup=kb_admin())
        return
    idx = int(n) - 1
    products = load_json(PRODUCTS_PATH, [])
    if idx < 0 or idx >= len(products):
        bot.send_message(m.chat.id, "Нет такого номера.", reply_markup=kb_admin())
        return
    deleted = products.pop(idx)
    save_json(PRODUCTS_PATH, products)
    bot.send_message(m.chat.id, f"Удалено ✅ {deleted.get('name')}", reply_markup=kb_admin())

def admin_change_price(m):
    parts = [x.strip() for x in (m.text or "").split("\n") if x.strip()]
    if len(parts) < 2 or not parts[0].isdigit():
        bot.send_message(m.chat.id, "Нужно 2 строки: номер и цена.", reply_markup=kb_admin())
        return
    idx = int(parts[0]) - 1
    new_price = parts[1]
    products = load_json(PRODUCTS_PATH, [])
    if idx < 0 or idx >= len(products):
        bot.send_message(m.chat.id, "Нет такого номера.", reply_markup=kb_admin())
        return
    products[idx]["price"] = new_price
    save_json(PRODUCTS_PATH, products)
    bot.send_message(m.chat.id, "Цена обновлена ✅", reply_markup=kb_admin())

def show_orders(chat_id):
    orders = load_json(ORDERS_PATH, [])
    if not orders:
        bot.send_message(chat_id, "Заказов пока нет.", reply_markup=kb_admin())
        return
    last = orders[-10:]  # последние 10
    lines = []
    for o in last:
        lines.append(f"• {o['user_id']} | {o['ts']}\n{o['text']}\n")
    bot.send_message(chat_id, "📥 Последние заказы:\n\n" + "\n".join(lines), reply_markup=kb_admin())

def send_export(chat_id):
    try:
        bot.send_document(chat_id, ("products.json", export_bytes(PRODUCTS_PATH)))
        bot.send_document(chat_id, ("orders.json", export_bytes(ORDERS_PATH)))
        bot.send_message(chat_id, "Экспорт готов ✅", reply_markup=kb_admin())
    except Exception as e:
        bot.send_message(chat_id, f"Экспорт не вышел: {e}", reply_markup=kb_admin())

# ---------- import handler (documents) ----------
@bot.message_handler(content_types=["document"])
def on_doc(m):
    if not is_admin(m.chat.id):
        bot.send_message(m.chat.id, "Документы может импортировать только админ.", reply_markup=kb_main(m.chat.id))
        return

    doc = m.document
    if doc.file_name not in ("products.json", "orders.json"):
        bot.send_message(m.chat.id, "Принимаю только products.json или orders.json", reply_markup=kb_admin())
        return

    file_info = bot.get_file(doc.file_id)
    downloaded = bot.download_file(file_info.file_path)

    # простая проверка JSON
    try:
        json.loads(downloaded.decode("utf-8"))
    except Exception:
        bot.send_message(m.chat.id, "Файл не похож на JSON.", reply_markup=kb_admin())
        return

    target = PRODUCTS_PATH if doc.file_name == "products.json" else ORDERS_PATH
    import_bytes(target, downloaded)
    bot.send_message(m.chat.id, f"Импорт {doc.file_name} выполнен ✅", reply_markup=kb_admin())

bot.polling(none_stop=True)
