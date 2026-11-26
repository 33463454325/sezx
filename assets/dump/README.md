# Standoff 2 статический дамп

Источник: `com.axlebolt.standoff2-203982.xapk` (ver 203982, 2026-10-30),
SHA256 XAPK `4457ec4ef59f0d8f186b680192e64dda14c359b48fa75a39b85ec3cb0c4e55cb`.

## Главное открытие

AxleBolt переименовал `libil2cpp.so` → `libunity.so` (207 МБ, с теми же
IL2CPP-строками внутри), экспорты удалены (`strip`), `global-metadata.dat`
НЕ лежит отдельным файлом — зашифрована и упакована внутрь
`assets/bin/Data/data.unity3d` (UnityFS, Unity 6000.3.13f1).

## Что из этого следует

1. Стандартный `Il2CppDumper` не справится без рантайм-дампа ключа
   дешифрования метадаты.
2. Нужен Zygisk-companion, который:
   - вешается на `libunity.so` при `dlopen`
   - ждёт завершения `il2cpp_init` (сигнатура находится в `.text`)
   - читает `g_CodeRegistration` + `g_MetadataRegistration` из RAM
   - сериализует классы/поля в `/sdcard/.so2mm/dump.json`
3. До получения рантайм-дампа все оффсеты в `src/offsets.hpp` остаются
   UNCERTIFIED, а соответствующие `has_*` — false.

## Содержимое директории

| Файл                          | Что в нём                          |
|-------------------------------|------------------------------------|
| `libunity.info`               | ELF, разделы, размер, SHA256       |
| `assemblies.txt`              | 512 имён .dll, упомянутых в libunity |
| `il2cpp_strings_top200.txt`   | первые 200 строк с IL2CPP-внутренностями |
| `security_strings_top200.txt` | первые 200 вхождений Guard/Integrity/AntiCheat |
| `standoff_classes_top200.txt` | первые 200 упоминаний Axlebolt-классов |
