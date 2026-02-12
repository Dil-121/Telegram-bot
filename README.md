# Telegram-bot

## Available blueprints
- `blueprints/business_catalog_bot`
- `blueprints/booking_bot`

## How to connect to constructor
Add both blueprint directories to `blueprints/` and provide build-time template variables:

```python
variables = {
  "BOT_TOKEN": token_user_bot,
  "ADMIN_ID": chat_id,
  "BUSINESS_NAME": "Название бизнеса",
  "CURRENCY": "сомони",
  "SUPPORT_USERNAME": "@username"
}
```

### Notes
- `booking_bot` ignores `CURRENCY` and only uses `BOT_TOKEN`, `ADMIN_ID`, `BUSINESS_NAME`, `SUPPORT_USERNAME`.
- `business_catalog_bot` uses all variables shown above.

## Recommended upgrades
- Add category buttons in catalog bot.
- Add an explicit "Подтвердить заказ" action in order flow.
- Add "отмена записи" and "показать мои записи" in booking flow.
