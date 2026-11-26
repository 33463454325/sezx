from PIL import Image, ImageDraw, ImageFont
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _brand import apply_watermark, header_logo

W, H = 900, 1100
BG       = (14, 5, 7)
PANEL    = (26, 9, 13)
PANEL2   = (36, 12, 18)
HAIR     = (70, 20, 30)
LABEL    = (238, 230, 232)
SECOND   = (170, 130, 140)
TERTIARY = (110, 80, 90)
RED      = (235, 55, 72)
RED_HI   = (255, 95, 110)
RED_DIM  = (120, 20, 30)
GREEN    = (90, 220, 130)
WHITE    = (245, 230, 232)

TABS = [
    ("Прицел", "цель · триггер · нож", "aim"),
    ("ESP", "игроки · мир · бой", "esp"),
    ("Оружие", "отдача, разброс, стрельба", "weapon"),
    ("Движение", "прыжки, скорость, слайды", "move"),
    ("Камера", "FOV и обзор", "view"),
    ("HUD", "прицел · радар · оверлей", "hud"),
    ("Утилиты", "гранаты, объектив, чат", "util"),
    ("Скины", "каталог и применение", "skins"),
    ("Защита", "античит · скрытие", "guard"),
    ("Профили", "сохранение и загрузка", "profiles"),
    ("Лицензия", "ключ, HWID, срок", "license"),
]

def font(paths, size):
    for p in paths:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero  = font(SFB, 28)
f_title = font(SFB, 18)
f_sec   = font(SFB, 13)
f_row   = font(SF,  16)
f_desc  = font(SF,  12)
f_small = font(SF,  11)
f_badge = font(SFB, 10)

def rrect(d, xy, r, fill, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def switch(d, x, y, on):
    w, h = 44, 26
    track = RED if on else (60, 30, 36)
    rrect(d, (x, y, x+w, y+h), h//2, track)
    kx = x + (w - h + 2) if on else x + 2
    d.ellipse((kx, y+2, kx+h-4, y+h-2), fill=WHITE)

def slider(d, x, y, w, val, label_right):
    d.rounded_rectangle((x, y, x+w, y+6), 3, fill=(60, 30, 36))
    fx = x + w * val
    d.rounded_rectangle((x, y, fx, y+6), 3, fill=RED)
    d.ellipse((fx-10, y-6, fx+10, y+12), fill=WHITE)
    d.text((x + w + 14, y - 6), label_right, font=f_row, fill=LABEL)

def draw_header(d):
    d.rectangle((0, 0, W, 70), fill=(20, 7, 10))
    d.text((80, 16), "VEKTOR", font=f_hero, fill=RED_HI)
    d.text((80, 44), "тёмно-красная · v2.4 · arm64", font=f_desc, fill=SECOND)
    chip_x = W - 220
    rrect(d, (chip_x, 20, W-20, 46), 13, (34, 12, 16), outline=RED_DIM, width=1)
    d.ellipse((chip_x+10, 27, chip_x+22, 39), fill=GREEN)
    d.text((chip_x+30, 26), "Лицензия OK  63д", font=f_desc, fill=LABEL)

def draw_sidebar(d, active_idx):
    SB_X, SB_Y, SB_W = 16, 88, 180
    rrect(d, (SB_X, SB_Y, SB_X+SB_W, H-20), 14, PANEL)
    for i, (name, _, _) in enumerate(TABS):
        ry = SB_Y + 14 + i*44
        if i == active_idx:
            rrect(d, (SB_X+6, ry-2, SB_X+SB_W-6, ry+32), 9, (60, 15, 22))
            d.rectangle((SB_X+6, ry-2, SB_X+10, ry+32), fill=RED)
        d.text((SB_X+26, ry+8), name, font=f_row,
               fill=RED_HI if i == active_idx else LABEL)

def section_header(d, x, y, text):
    d.text((x, y), text, font=f_sec, fill=SECOND)
    return y + 22

def row(d, px, pw, y, label, desc, control):
    d.text((px, y), label, font=f_row, fill=LABEL)
    d.text((px, y+22), desc, font=f_desc, fill=TERTIARY)
    control(px + pw + 120, y + 10)
    d.line((px, y+50, px+pw+120, y+50), fill=HAIR, width=1)
    return y + 60

def draw_main(d, idx):
    MX = 16 + 180 + 14
    MW = W - MX - 20
    MY = 88
    name, sub, key = TABS[idx]
    d.text((MX+2, MY-2), name, font=f_hero, fill=LABEL)
    d.text((MX+2, MY+36), sub, font=f_desc, fill=SECOND)

    card_y = MY + 74
    rrect(d, (MX, card_y, MX+MW, H-20), 14, PANEL)
    px = MX + 18
    pw = MW - 170
    y = card_y + 18

    def sw(on):
        return lambda x, yy: switch(d, x - 46, yy - 10, on)
    def sl(val, lbl):
        return lambda x, yy: slider(d, x - 300, yy, 220, val, lbl)

    if key == "aim":
        y = section_header(d, px, y, "ЦЕЛЬ")
        y = row(d, px, pw, y, "Аимбот",          "Наводит прицел на ближайшего врага при зажатии огня", sw(True))
        y = row(d, px, pw, y, "Тихий аим",       "Пули идут в цель, курсор визуально не смещается",      sw(True))
        y = row(d, px, pw, y, "Только видимые",  "Игнорирует врагов за стенами и дымом",                 sw(True))
        y = row(d, px, pw, y, "Мульти-точка",    "Проверяет несколько точек на модели и бьёт лучшую",    sw(False))
        y = row(d, px, pw, y, "Упреждение",      "Компенсирует скорость цели и сетевую задержку",        sw(True))
        y = row(d, px, pw, y, "Радиус FOV (px)", "Размер зоны захвата в пикселях экрана", sl(0.42, "248"))
        y = row(d, px, pw, y, "Плавность",       "0.02 — мгновенно, 1.00 — очень плавно",  sl(0.23, "0.25"))
        y = section_header(d, px, y+2, "ТРИГГЕР")
        y = row(d, px, pw, y, "Триггер-бот",     "Автоматический выстрел, когда прицел на враге",        sw(True))
        y = row(d, px, pw, y, "Только в прицеле","Срабатывает только при прицеливании правой",           sw(False))
        y = row(d, px, pw, y, "Задержка (мс)",   "Пауза между захватом и выстрелом",                     sl(0.12, "24"))

    elif key == "esp":
        y = section_header(d, px, y, "ИГРОКИ")
        for label, desc, on in [
            ("Коробка",      "Рамка вокруг модели врага", True),
            ("Скелет",       "Линии между костями: голова–шея–руки–ноги", False),
            ("Имя",          "Ник игрока над головой", True),
            ("Полоса HP",    "Полоска здоровья сбоку от коробки", True),
            ("Дистанция",    "Расстояние до врага в метрах", True),
            ("Союзники",     "Рисовать своих голубым цветом", False),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))
        y = row(d, px, pw, y, "Макс. радиус", "Дальше этого расстояния игроков не отображать", sl(0.35, "420m"))
        y = section_header(d, px, y+2, "МИР")
        for label, desc, on in [
            ("Оружие на земле", "Подсветка дропнутого оружия и его типа", True),
            ("Гранаты",         "Летящие гранаты, тип и остаток времени", True),
            ("Бомба",           "Позиция C4 после плантинга или на земле", True),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))
        y = section_header(d, px, y+2, "БОЙ")
        for label, desc, on in [
            ("Маркер попадания","Крестик в центре при засчитанном уроне", True),
            ("Звук попадания",  "Короткий тик при каждом хите", False),
            ("Лог урона",       "Список входящих и исходящих хитов сбоку", True),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))

    elif key == "weapon":
        for label, desc, on in [
            ("Без отдачи",       "Обнуляет подкидывание прицела при стрельбе", True),
            ("Без разброса",     "Пули летят точно в прицел, без разлёта",     True),
            ("Рапид",            "Максимальный темп стрельбы оружия",          False),
            ("Magic bullet",     "Пробивает одну стену любой пулей",           False),
            ("Беск. патроны",    "Магазин не уменьшается при стрельбе",        False),
            ("Авто-перезарядка", "Перезарядка срабатывает при пустом магазине",True),
            ("Быстрая смена",    "Мгновенное переключение между оружиями",     False),
            ("Без флешки",       "Убирает белую засветку от флэш-гранат",      True),
            ("Без дыма",         "Удаляет рендер дымовых гранат",              False),
            ("Chams по стенам",  "Модели врагов видны сквозь стены",           False),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))

    elif key == "move":
        y = row(d, px, pw, y, "Банни-хоп",     "Автоматический прыжок при зажатом пробеле", sw(True))
        y = row(d, px, pw, y, "Идеальный BH",  "Прыжок в кадр касания земли без задержки",  sw(True))
        y = row(d, px, pw, y, "Авто-страйф",   "Автоматические A/D в воздухе для набора скорости", sw(False))
        y = row(d, px, pw, y, "Slide jump",    "Совмещает слайд и прыжок для длинного скачка", sw(False))
        y = row(d, px, pw, y, "Speed hack",    "Умножает горизонтальную скорость",          sw(False))
        y = row(d, px, pw, y, "Множитель",     "Во сколько раз быстрее двигаешься",         sl(0.30, "1.60x"))
        y = row(d, px, pw, y, "No fall",       "Обнуляет урон от падения с высоты",          sw(True))
        y = row(d, px, pw, y, "Jump boost",    "Увеличивает высоту прыжка",                  sw(False))
        y = row(d, px, pw, y, "Полёт",         "Убирает гравитацию: свободное перемещение по Y", sw(False))

    elif key == "view":
        y = row(d, px, pw, y, "Переопределить FOV", "Ставит свой угол обзора вместо игрового", sw(True))
        y = row(d, px, pw, y, "FOV (градусы)",      "60 — узкий, 90 — стандарт, 120 — широкий", sl(0.62, "110"))
        y = row(d, px, pw, y, "FOV оружия",         "Отдельный угол обзора для модели оружия", sw(False))
        y = row(d, px, pw, y, "Значение",           "Чем больше, тем меньше оружие на экране", sl(0.42, "80"))
        y = row(d, px, pw, y, "Третье лицо",        "Камера переносится за спину персонажа", sw(False))

    elif key == "hud":
        y = section_header(d, px, y, "ПРИЦЕЛ")
        y = row(d, px, pw, y, "Включить прицел",  "Свой кастомный прицел поверх игрового", sw(True))
        y = row(d, px, pw, y, "Размер",           "Длина штрихов в пикселях",               sl(0.30, "10"))
        y = row(d, px, pw, y, "Зазор",            "Расстояние от центра до начала штрихов", sl(0.15, "3"))
        y = row(d, px, pw, y, "Точка",            "Точка ровно в центре прицела", sw(False))
        y = section_header(d, px, y+2, "РАДАР")
        y = row(d, px, pw, y, "Показать",         "Мини-карта в верхнем правом углу", sw(True))
        y = row(d, px, pw, y, "Масштаб",          "Размер круга радара", sl(0.50, "1.00"))
        y = row(d, px, pw, y, "Конусы врагов",    "Треугольники направления взгляда противников", sw(True))
        y = section_header(d, px, y+2, "ОВЕРЛЕЙ")
        for label, desc, on in [
            ("Список наблюдателей","Кто сейчас смотрит на тебя в режиме спектейта", True),
            ("FPS",               "Счётчик кадров в секунду", True),
            ("Пинг",              "Задержка до сервера в миллисекундах", True),
            ("Таймер бомбы",      "Обратный отсчёт после плантинга C4",   True),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))

    elif key == "util":
        y = section_header(d, px, y, "ГРАНАТЫ")
        y = row(d, px, pw, y, "Предсказание", "Рассчитывает траекторию броска от прицела", sw(True))
        y = row(d, px, pw, y, "Траектория",   "Рисует линию полёта гранаты",                sw(True))
        y = section_header(d, px, y+2, "ОБЪЕКТИВ")
        y = row(d, px, pw, y, "Авто-дефьюз",  "Начинает разминирование как только возможно", sw(False))
        y = row(d, px, pw, y, "Авто-плант",   "Ставит бомбу на точке автоматически",         sw(False))
        y = section_header(d, px, y+2, "ЧАТ")
        y = row(d, px, pw, y, "Спам",         "Повторяет сообщение в общий чат по таймеру",  sw(False))
        d.text((px, y), "Сообщение", font=f_row, fill=LABEL)
        d.text((px, y+22), "Текст, который отправляется по кругу", font=f_desc, fill=TERTIARY)
        rrect(d, (px, y+46, px+pw+120, y+78), 7, PANEL2)
        d.text((px+10, y+54), "gl hf", font=f_row, fill=LABEL)
        y += 92
        y = row(d, px, pw, y, "Период (мс)", "Пауза между сообщениями", sl(0.30, "3000"))

    elif key == "skins":
        y = row(d, px, pw, y, "Смена скинов", "Подменяет скин оружия локально, сервер не видит", sw(True))
        rrect(d, (px, y, px+170, y+230), 10, PANEL2)
        weps = ["AKR","M4","AWM","Desert Eagle","USP","Glock-18","Karambit","M9 Bayonet","Butterfly"]
        for i, w in enumerate(weps):
            ry = y + 10 + i*24
            if i == 0: rrect(d, (px+6, ry-2, px+164, ry+20), 6, (60,15,22))
            d.text((px+16, ry), w, font=f_desc, fill=LABEL if i == 0 else SECOND)
        rrect(d, (px+180, y, px+pw+120, y+230), 10, PANEL2)
        skins = [("Steel Grip", True, False), ("Tiger", True, True), ("Sport", True, False),
                 ("2Years Red", True, True), ("Treasure Hunter", True, True),
                 ("Galaxy", False, False), ("Neon Tiger", False, False), ("Dragon", False, True)]
        for i, (n, ver, st) in enumerate(skins):
            ry = y + 10 + i*24
            if i == 3: rrect(d, (px+186, ry-2, px+pw+114, ry+20), 6, (60,15,22))
            d.text((px+198, ry), n, font=f_desc, fill=LABEL if ver else TERTIARY)
            if st: d.text((px+pw+70, ry), "ST", font=f_badge, fill=RED_HI)
        y += 242
        y = row(d, px, pw, y, "StatTrak", "Счётчик фрагов на корпусе оружия", sw(True))
        y = row(d, px, pw, y, "Износ",    "0.00 — заводское, 1.00 — поношенное", sl(0.07, "0.070"))
        rrect(d, (px, y+10, px+pw+120, y+54), 10, RED)
        tx = px + (pw+120)/2 - 90
        d.text((tx, y+20), "Применить к инвентарю", font=f_title, fill=WHITE)

    elif key == "guard":
        for label, desc, on in [
            ("Строгий фильтр",     "Глушит SIGKILL/SIGTERM, посланные нам детектором", True),
            ("Скрытие в /proc",    "Вырезает наш модуль из maps/status/smaps",         True),
            ("Блок ptrace",        "Отказывает в прикреплении отладчика",              True),
            ("Заморозка потоков",  "SIGSTOP на треды с именами Fairplay/AntiCheat",    True),
            ("Shadow-flip CRC",    "Переключает байты хуков между clean/patched",     True),
            ("Нейтрализация FP",   "Заменяет Toolkit.Fairplay.Validate на return 1",   True),
            ("Размытие скринов",   "Заглушка: будущий блок захвата экрана детектором", False),
        ]:
            y = row(d, px, pw, y, label, desc, sw(on))

    elif key == "profiles":
        y = section_header(d, px, y, "ТЕКУЩИЙ")
        d.text((px, y), "Активный профиль: comp_ak", font=f_row, fill=LABEL)
        y += 32
        y = section_header(d, px, y, "СОХРАНЁННЫЕ")
        for n in ["comp_ak", "retake_awp", "casual_fun", "default"]:
            rrect(d, (px, y, px+pw+120, y+40), 8, PANEL2)
            d.text((px+14, y+10), n, font=f_row, fill=LABEL)
            rrect(d, (px+pw-30, y+6, px+pw+30, y+34), 7, (60, 15, 22))
            d.text((px+pw-20, y+10), "Загр.", font=f_desc, fill=LABEL)
            rrect(d, (px+pw+40, y+6, px+pw+110, y+34), 7, PANEL)
            d.text((px+pw+54, y+10), "Удал.", font=f_desc, fill=SECOND)
            y += 50
        y = section_header(d, px, y+4, "НОВЫЙ / ПЕРЕЗАПИСЬ")
        d.text((px, y), "Имя профиля", font=f_row, fill=LABEL)
        d.text((px, y+22), "Латиница, цифры, _ и -. До 40 символов.", font=f_desc, fill=TERTIARY)
        rrect(d, (px, y+46, px+pw+120, y+80), 7, PANEL2)
        y += 96
        rrect(d, (px, y, px+pw+120, y+42), 8, RED)
        d.text((px + (pw+120)/2 - 40, y+12), "Сохранить", font=f_title, fill=WHITE)

    elif key == "license":
        y = section_header(d, px, y, "ЛИЦЕНЗИЯ")
        d.text((px, y), "Статус: OK", font=f_row, fill=GREEN)
        d.text((px, y+22), "Актуально при каждом запуске", font=f_desc, fill=TERTIARY)
        y += 52
        d.text((px, y), "HWID устройства", font=f_row, fill=LABEL)
        d.text((px, y+22), "Отпечаток железа: ro.serialno + fingerprint + abilist", font=f_desc, fill=TERTIARY)
        rrect(d, (px, y+46, px+pw+120, y+80), 7, PANEL2)
        d.text((px+10, y+54), "1a2c47e3b0...85fb98d1cc", font=f_desc, fill=SECOND)
        y += 96
        d.text((px, y), "Владелец: user_4421", font=f_row, fill=LABEL)
        d.text((px, y+22), "Осталось: 63 дней", font=f_desc, fill=TERTIARY)
        y += 52
        d.text((px, y), "Путь к ключу", font=f_row, fill=LABEL)
        d.text((px, y+22), "Подписанный ed25519 файл лицензии", font=f_desc, fill=TERTIARY)
        rrect(d, (px, y+46, px+pw+120, y+80), 7, PANEL2)
        d.text((px+10, y+54), "/sdcard/.so2mm/license.key", font=f_desc, fill=SECOND)
        y += 96
        rrect(d, (px, y, px+pw+120, y+42), 8, RED)
        d.text((px + (pw+120)/2 - 70, y+12), "Перечитать ключ", font=f_title, fill=WHITE)

OUT_DIR = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT_DIR, exist_ok=True)
paths = []
for i, (name, _, key) in enumerate(TABS):
    img = Image.new("RGBA", (W, H), BG + (255,))
    apply_watermark(img, size_frac=0.85, alpha=30)
    d = ImageDraw.Draw(img)
    draw_header(d)
    header_logo(img, 12, 6, 60)
    draw_sidebar(d, i)
    draw_main(d, i)
    p = f"{OUT_DIR}/so2mm_{i+1:02d}_{key}.png"
    img.convert("RGB").save(p, "PNG")
    paths.append(p)

for p in paths: print(p)
