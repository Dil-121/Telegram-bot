import os, json, time
import telebot
from telebot import types

TOKEN = "{{BOT_TOKEN}}"
ADMIN_ID = int("{{ADMIN_ID}}")
BUSINESS_NAME = "{{BUSINESS_NAME}}"
SUPPORT_USERNAME = "{{SUPPORT_USERNAME}}"

bot = telebot.TeleBot(TOKEN)

DATA_DIR = "data"
SLOTS_PATH = os.path.join(DATA_DIR, "slots.json")
BOOKINGS_PATH = os.path.join(DATA_DIR, "bookings.json")
os.makedirs(DATA_DIR, exist_ok=True)

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

def is_admin(uid): return uid == ADMIN_ID

def kb_main(uid):
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.add(types.KeyboardButton("📅 Свободные слоты"), types.KeyboardButton("📝 Записаться"))
    kb.add(types.KeyboardButton("📞 Контакты"))
    if is_admin(uid):
        kb.add(types.KeyboardButton("🛠 Админка"))
    return kb

def kb_admin():
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.add(types.KeyboardButton("➕ Добавить слот"), types.KeyboardButton("🗑 Удалить слот"))
    kb.add(types.KeyboardButton("📥 Записи"), types.KeyboardButton("📤 Экспорт"))
    kb.add(types.KeyboardButton("🏠 Меню"))
    return kb

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
        bot.send_message(m.chat.id, f"Связь: {SUPPORT_USERNAME}", reply_markup=kb_main(m.chat.id))
        return

    if txt == "📅 Свободные слоты":
        show_slots(m.chat.id, for_admin=is_admin(m.chat.id))
        return

    if txt == "📝 Записаться":
        slots = load_json(SLOTS_PATH, [])
        free = [s for s in slots if not s.get("booked")]
        if not free:
            bot.send_message(m.chat.id, "Свободных слотов нет. Напишите в поддержку.", reply_markup=kb_main(m.chat.id))
            return
        msg = "Выберите номер слота и отправьте одним сообщением:\n\n" + "\n".join(
            [f"{i+1}) {s['slot']}" for i, s in enumerate(free)]
        )
        bot.send_message(m.chat.id, msg, reply_markup=types.ReplyKeyboardRemove())
        bot.register_next_step_handler(m, booking_step, free)
        return

    if txt == "🛠 Админка":
        if not is_admin(m.chat.id):
            bot.send_message(m.chat.id, "Нет доступа 🙂", reply_markup=kb_main(m.chat.id))
            return
        bot.send_message(m.chat.id, "Админка:", reply_markup=kb_admin())
        return

    if is_admin(m.chat.id):
        if txt == "➕ Добавить слот":
            bot.send_message(m.chat.id, "Отправь слот текстом. Пример:\n12.02 16:30", reply_markup=kb_admin())
            bot.register_next_step_handler(m, admin_add_slot)
            return

        if txt == "🗑 Удалить слот":
            bot.send_message(m.chat.id, "Отправь номер слота для удаления.", reply_markup=kb_admin())
            bot.register_next_step_handler(m, admin_delete_slot)
            return

        if txt == "📥 Записи":
            show_bookings(m.chat.id)
            return

        if txt == "📤 Экспорт":
            export_data(m.chat.id)
            return

    bot.send_message(m.chat.id, "Не понял. Выбери кнопку 🙂", reply_markup=kb_main(m.chat.id))

def show_slots(chat_id, for_admin=False):
    slots = load_json(SLOTS_PATH, [])
    if not slots:
        bot.send_message(chat_id, "Слотов пока нет.", reply_markup=kb_main(chat_id))
        return
    lines = []
    for i, s in enumerate(slots):
        status = "✅ свободно" if not s.get("booked") else "⛔ занято"
        if for_admin:
            lines.append(f"{i+1}) {s['slot']} — {status}")
        else:
            if not s.get("booked"):
                lines.append(f"• {s['slot']}")
    if not lines:
        bot.send_message(chat_id, "Свободных слотов нет.", reply_markup=kb_main(chat_id))
        return
    bot.send_message(chat_id, "📅 Слоты:\n\n" + "\n".join(lines), reply_markup=kb_main(chat_id))

def booking_step(m, free_slots):
    t = (m.text or "").strip()
    if not t.isdigit():
        bot.send_message(m.chat.id, "Нужно номер слота (число). Попробуй снова: /start")
        return
    idx = int(t) - 1
    if idx < 0 or idx >= len(free_slots):
        bot.send_message(m.chat.id, "Нет такого номера. Попробуй снова: /start")
        return

    chosen = free_slots[idx]["slot"]
    bot.send_message(m.chat.id, f"Ок, слот {chosen}.\nТеперь отправь:\nИмя\nТелефон\nКомментарий (можно пусто)")
    bot.register_next_step_handler(m, booking_details_step, chosen)

def booking_details_step(m, chosen_slot):
    parts = [x.strip() for x in (m.text or "").split("\n")]
    name = parts[0] if len(parts) > 0 else ""
    phone = parts[1] if len(parts) > 1 else ""
    comment = parts[2] if len(parts) > 2 else ""

    if not name or not phone:
        bot.send_message(m.chat.id, "Нужно минимум имя и телефон. Попробуй снова: /start")
        return

    # mark slot booked
    slots = load_json(SLOTS_PATH, [])
    for s in slots:
        if s["slot"] == chosen_slot and not s.get("booked"):
            s["booked"] = True
            s["booked_by"] = m.chat.id
            break
    save_json(SLOTS_PATH, slots)

    bookings = load_json(BOOKINGS_PATH, [])
    bookings.append({
        "ts": int(time.time()),
        "slot": chosen_slot,
        "user_id": m.chat.id,
        "name": name,
        "phone": phone,
        "comment": comment
    })
    save_json(BOOKINGS_PATH, bookings)

    bot.send_message(m.chat.id, "Запись подтверждена ✅", reply_markup=kb_main(m.chat.id))
    bot.send_message(
        ADMIN_ID,
        f"📝 Новая запись:\nСлот: {chosen_slot}\nОт: {name} ({phone})\nID: {m.chat.id}\nКомментарий: {comment}"
    )

def admin_add_slot(m):
    slot = (m.text or "").strip()
    if not slot:
        bot.send_message(m.chat.id, "Нужно текстом.", reply_markup=kb_admin())
        return
    slots = load_json(SLOTS_PATH, [])
    slots.append({"slot": slot, "booked": False})
    save_json(SLOTS_PATH, slots)
    bot.send_message(m.chat.id, "Слот добавлен ✅", reply_markup=kb_admin())

def admin_delete_slot(m):
    t = (m.text or "").strip()
    if not t.isdigit():
        bot.send_message(m.chat.id, "Нужно число.", reply_markup=kb_admin())
        return
    idx = int(t) - 1
    slots = load_json(SLOTS_PATH, [])
    if idx < 0 or idx >= len(slots):
        bot.send_message(m.chat.id, "Нет такого номера.", reply_markup=kb_admin())
        return
    deleted = slots.pop(idx)
    save_json(SLOTS_PATH, slots)
    bot.send_message(m.chat.id, f"Удалено ✅ {deleted['slot']}", reply_markup=kb_admin())

def show_bookings(chat_id):
    b = load_json(BOOKINGS_PATH, [])
    if not b:
        bot.send_message(chat_id, "Записей нет.", reply_markup=kb_admin())
        return
    last = b[-10:]
    lines = []
    for x in last:
        lines.append(f"• {x['slot']} | {x['name']} {x['phone']} | id {x['user_id']}\n{(x.get('comment') or '')}\n")
    bot.send_message(chat_id, "📥 Последние записи:\n\n" + "\n".join(lines), reply_markup=kb_admin())

def export_data(chat_id):
    try:
        with open(SLOTS_PATH, "rb") as f:
            bot.send_document(chat_id, ("slots.json", f.read()))
        with open(BOOKINGS_PATH, "rb") as f:
            bot.send_document(chat_id, ("bookings.json", f.read()))
        bot.send_message(chat_id, "Экспорт готов ✅", reply_markup=kb_admin())
    except Exception as e:
        bot.send_message(chat_id, f"Экспорт не вышел: {e}", reply_markup=kb_admin())

bot.polling(none_stop=True)
