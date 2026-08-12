#!/bin/bash
# ============================================================
# Управление киосками через Ansible
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_INI=""
TARGET_HOST=""
TARGET_GROUP=""

# ============================================================
# Функция: Выбор INI файла
# ============================================================
select_ini_file() {
    clear
    echo "============================================================"
    echo "                   ВЫБЕРИ INI ФАЙЛ"
    echo "============================================================"
    
    # Находим все .ini файлы
    mapfile -t ini_files < <(find . -maxdepth 1 -name "*.ini" -type f | sed 's/^\.\///' | sort)
    
    if [[ ${#ini_files[@]} -eq 0 ]]; then
        echo "❌ Нет .ini файлов в текущей директории!"
        sleep 3
        return 1
    fi
    
    local total=${#ini_files[@]}
    for i in "${!ini_files[@]}"; do
        local num=$((i+1))
        local size=$(du -h "${ini_files[$i]}" 2>/dev/null | cut -f1)
        local groups=$(grep -c "^\[[^:]" "${ini_files[$i]}" 2>/dev/null || echo "0")
        local hosts=$(grep -c "^[0-9]" "${ini_files[$i]}" 2>/dev/null || echo "0")
        printf "  %2d) %-30s (групп: %3d, хостов: %4d, размер: %s)\n" \
            "$num" "${ini_files[$i]}" "$groups" "$hosts" "$size"
    done
    
    echo "============================================================"
    echo "  0) Выход"
    echo "============================================================"
    read -p "Введите номер (1-${#ini_files[@]}, 0-выход): " ini_num
    
    if ! [[ "$ini_num" =~ ^[0-9]+$ ]]; then
        echo "Ошибка: введите число!"
        sleep 1
        return 1
    fi
    
    if [[ $ini_num -eq 0 ]]; then
        echo "Выход..."
        exit 0
    elif [[ $ini_num -ge 1 && $ini_num -le ${#ini_files[@]} ]]; then
        TARGET_INI="${ini_files[$((ini_num-1))]}"
        echo "✅ Выбран INI файл: $TARGET_INI"
        return 0
    else
        echo "Ошибка: неверный выбор!"
        sleep 1
        return 1
    fi
}

# ============================================================
# Функция: Выбор хоста/группы с древовидной структурой
# ============================================================
select_host_or_group() {
    if [[ ! -f "$TARGET_INI" ]]; then
        echo "❌ INI файл не найден!"
        return 1
    fi
    
    clear
    echo "============================================================"
    echo "              ВЫБЕРИ ХОСТ ИЛИ ГРУППУ"
    echo "============================================================"
    echo "  INI файл: $TARGET_INI"
    echo "============================================================"
    
    # Собираем все группы с хостами
    local groups=()
    local group_hosts=()
    local option_num=1
    local option_map=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            local group_name="${BASH_REMATCH[1]}"
            # Пропускаем служебные группы
            if [[ "$group_name" == "all:vars" || "$group_name" == "all_hosts" ]]; then
                continue
            fi
            # Проверяем, есть ли хосты в группе
            local has_hosts=$(sed -n "/^\[${group_name}\]/,/^\[/p" "$TARGET_INI" 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || echo "0")
            if [[ $has_hosts -gt 0 ]]; then
                groups+=("$group_name")
                group_hosts+=("$has_hosts")
            fi
        fi
    done < "$TARGET_INI"
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        echo "❌ В INI файле нет групп с хостами!"
        return 1
    fi
    
    # Показываем группы
    echo "📊 ДОСТУПНЫЕ ГРУППЫ:"
    echo "============================================================"
    
    for i in "${!groups[@]}"; do
        local group="${groups[$i]}"
        local count="${group_hosts[$i]}"
        printf "  %4d) %-50s (%d хостов)\n" "$((i+1))" "$group" "$count"
        option_map+=("$group")
    done
    
    echo "============================================================"
    echo "  0) Выход"
    echo "  F) Выбрать другой INI файл"
    echo "============================================================"
    read -p "Введите номер (1-${#groups[@]}, 0-выход, F-сменить INI): " choice
    
    if [[ "$choice" == "F" || "$choice" == "f" ]]; then
        select_ini_file
        if [[ $? -eq 0 ]]; then
            select_host_or_group
        fi
        return
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Ошибка: введите число!"
        sleep 1
        select_host_or_group
        return
    fi
    
    if [[ $choice -eq 0 ]]; then
        echo "Выход..."
        exit 0
    elif [[ $choice -ge 1 && $choice -le ${#groups[@]} ]]; then
        local selected="${option_map[$((choice-1))]}"
        TARGET_GROUP="$selected"
        TARGET_HOST="$selected"
        echo "✅ Выбрана группа: $selected"
        sleep 2
        return 0
    else
        echo "Ошибка: неверный выбор!"
        sleep 1
        select_host_or_group
    fi
}

# ============================================================
# Функции управления
# ============================================================

ping_hosts() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo "============================================================"
    echo "📡 Пинг: $TARGET_HOST"
    echo "============================================================"
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m ping
}

view_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo "============================================================"
    echo "📂 Просмотр директории на $TARGET_HOST"
    echo "============================================================"
    read -p "Введите путь (или '0' для отмены): " dest_dir
    
    if [[ "$dest_dir" == "0" ]]; then
        return 0
    fi
    if [[ -z "$dest_dir" ]]; then
        echo "Ошибка: Путь не может быть пустым!"
        return 1
    fi
    [[ ! "$dest_dir" =~ /$ ]] && dest_dir="$dest_dir/"
    
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "ls -lth $dest_dir 2>/dev/null || echo '❌ Директория не найдена'" --become
}

copy_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    echo "============================================================"
    echo "📁 ФАЙЛЫ В ~/WORK/FILES/:"
    echo "============================================================"
    ls -lth ~/WORK/FILES/ 2>/dev/null || echo "❌ ~/WORK/FILES/ не существует"
    echo "============================================================"
    read -p "Введите имя файла: " filename
    
    if [[ -z "$filename" ]]; then
        echo "Ошибка: Имя не может быть пустым!"
        return 1
    fi
    
    local source_path="$HOME/WORK/FILES/$filename"
    if [[ ! -e "$source_path" ]]; then
        echo "❌ $source_path не найден!"
        return 1
    fi
    
    read -p "Введите путь для копирования (или '0' для отмены): " dest_dir
    [[ "$dest_dir" == "0" ]] && return 0
    [[ -z "$dest_dir" ]] && echo "Ошибка: Путь не может быть пустым!" && return 1
    [[ ! "$dest_dir" =~ /$ ]] && dest_dir="$dest_dir/"
    
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m copy -a "src=$source_path dest=$dest_dir" --become
}

delete_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    echo "============================================================"
    echo "🗑️ УДАЛЕНИЕ ФАЙЛОВ"
    echo "============================================================"
    read -p "Введите путь (или '0' для отмены): " dest_dir
    
    [[ "$dest_dir" == "0" ]] && return 0
    [[ -z "$dest_dir" ]] && echo "Ошибка: Путь не может быть пустым!" && return 1
    [[ ! "$dest_dir" =~ /$ ]] && dest_dir="$dest_dir/"
    
    echo "Выберите способ удаления:"
    echo " 1) По имени файла"
    echo " 2) По MD5 сумме"
    echo " 0) Отмена"
    read -p "Введите номер (0-2): " method
    
    case $method in
        0) return 0 ;;
        1) read -p "Введите имя файла: " filename
           [[ -z "$filename" ]] && echo "Ошибка: Имя не может быть пустым!" && return 1
           local full_path="${dest_dir}${filename}"
           read -p "Удалить '$full_path'? (y/n): " confirm
           [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
           ansible -i "$TARGET_INI" "$TARGET_HOST" -m file -a "path='$full_path' state=absent" --become
           ;;
        2) read -p "Введите MD5 сумму: " md5sum
           [[ -z "$md5sum" ]] && echo "Ошибка: MD5 не может быть пустым!" && return 1
           local found_file=$(ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "find '$dest_dir' -type f -exec md5sum {} \; | grep '^$md5sum ' | head -1 | awk '{print \$2}'" --become 2>/dev/null | grep -v "changed" | tail -1)
           [[ -z "$found_file" ]] && echo "❌ Файл не найден!" && return 1
           echo "Найден файл: $found_file"
           read -p "Удалить? (y/n): " confirm
           [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
           ansible -i "$TARGET_INI" "$TARGET_HOST" -m file -a "path='$found_file' state=absent" --become
           ;;
        *) echo "Неверный выбор!" ;;
    esac
}

view_config() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    echo "============================================================"
    echo "📄 ПРОСМОТР КОНФИГА /etc/sst-iiko/settings.ini"
    echo "============================================================"
    echo " 1) Весь конфиг"
    echo " 2) Конкретные параметры"
    echo " 0) Назад"
    read -p "Введите номер (0-2): " mode
    
    case $mode in
        0) return 0 ;;
        1) ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '❌ Файл не найден'" --become ;;
        2) read -p "Введите параметры через пробел: " params
           [[ -z "$params" ]] && echo "Ошибка: Параметры не могут быть пустыми!" && return 1
           local grep_pattern=$(echo "$params" | tr ' ' '|')
           ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "grep -E '^($grep_pattern)=' /etc/sst-iiko/settings.ini 2>/dev/null || echo '❌ Параметры не найдены'" --become ;;
        *) echo "Неверный выбор!" ;;
    esac
}

restart_sst() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    echo "============================================================"
    echo -e "\033[1;33m⚠️ ВНИМАНИЕ! Перезапуск SST!\033[0m"
    echo "============================================================"
    read -p "Вы уверены? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "❌ Отменено" && return 0
    
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "
if systemctl is-enabled sst-iiko 2>/dev/null | grep -q enabled; then
    sudo systemctl restart sst-iiko
    echo '✅ sst-iiko перезапущен'
elif systemctl is-enabled xsst-iiko 2>/dev/null | grep -q enabled; then
    sudo systemctl restart xsst-iiko
    echo '✅ xsst-iiko перезапущен'
else
    echo '❌ Сервис SST не найден'
fi" --become
}

status_sst() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "
echo '--- Статус сервисов ---'
systemctl status sst-iiko xsst-iiko 2>/dev/null | grep -E 'Loaded|Active|Main PID' || echo '❌ Сервисы не найдены'
echo ''
echo '--- Проверка порта 10000 ---'
curl -s -o /dev/null -w 'HTTP Code: %{http_code}\n' localhost:10000 2>/dev/null || echo '❌ Порт 10000 недоступен'" --become
}

# ============================================================
# Главное меню
# ============================================================

main_menu() {
    while true; do
        clear
        echo "============================================================"
        echo "              🖥️ УПРАВЛЕНИЕ КИОСКАМИ"
        echo "============================================================"
        echo "  INI файл: ${TARGET_INI:-не выбран}"
        echo "  Точка:    ${TARGET_HOST:-не выбрана}"
        echo "============================================================"
        echo "  1) Пинг хоста/группы"
        echo "  2) Просмотр директории"
        echo "  3) Копировать файлы"
        echo "  4) Удалить файлы"
        echo "  5) Просмотр конфига"
        echo "  6) 🔄 RESTART SST (ОСТОРОЖНО!)"
        echo "  7) 📊 Статус SST"
        echo "  8) 🔄 Сменить точку"
        echo "  I) 🔄 Сменить INI файл"
        echo "  0) Выход"
        echo "============================================================"
        read -p "Введите номер (0-8, I): " choice

        case $choice in
            1) ping_hosts ;;
            2) view_files ;;
            3) copy_files ;;
            4) delete_files ;;
            5) view_config ;;
            6) restart_sst ;;
            7) status_sst ;;
            8) select_host_or_group ;;
            I|i) select_ini_file ;;
            0) echo "Выход..."; exit 0 ;;
            *) echo "❌ Неверный выбор!"; sleep 1 ;;
        esac
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# ============================================================
# Запуск
# ============================================================

select_ini_file
if [[ -n "$TARGET_INI" ]]; then
    select_host_or_group
fi

if [[ -n "$TARGET_HOST" ]]; then
    main_menu
else
    echo "❌ Не удалось выбрать точку!"
    exit 1
fi
