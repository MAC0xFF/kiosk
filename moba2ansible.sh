#!/bin/bash
# ============================================================
# Управление киосками через Ansible
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE=""
TARGET_INI=""
TARGET_HOST=""
TARGET_GROUP=""

# ============================================================
# Функция: Определение INI файла по .txt файлу
# ============================================================
get_ini_from_txt() {
    local txt_file="$1"
    local base_name="${txt_file%.txt}"
    local ini_file="${base_name}.ini"
    
    if [[ -f "$ini_file" ]]; then
        echo "$ini_file"
    else
        # Ищем любой INI файл в директории
        local first_ini=$(find . -maxdepth 1 -name "*.ini" -type f | head -1 | sed 's/^\.\///')
        if [[ -n "$first_ini" ]]; then
            echo "$first_ini"
        else
            echo ""
        fi
    fi
}

# ============================================================
# Функция: Парсинг INI файла и показ иерархии
# ============================================================
parse_ini_structure() {
    local ini_file="$1"
    
    if [[ ! -f "$ini_file" ]]; then
        echo "❌ INI файл не найден: $ini_file"
        return 1
    fi
    
    echo "📊 Структура групп в $ini_file:"
    echo "============================================================"
    
    # Извлекаем все группы
    local groups=()
    local current_group=""
    local in_section=0
    local section_type=""
    local parent_groups=()
    
    # Первый проход: собираем все группы
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            local group_name="${BASH_REMATCH[1]}"
            if [[ "$group_name" != "all:vars" && "$group_name" != "all_hosts" ]]; then
                groups+=("$group_name")
            fi
        fi
    done < "$ini_file"
    
    # Показываем группы с иерархией
    local indent=""
    local prev_depth=0
    local group_list=()
    
    for group in "${groups[@]}"; do
        # Проверяем, есть ли children для этой группы
        local has_children=$(grep -c "^\[${group}:children\]" "$ini_file")
        local host_count=$(grep -c "^${group}$" "$ini_file" 2>/dev/null || echo "0")
        
        if [[ $has_children -gt 0 ]]; then
            echo "  📁 $group/ (родительская группа)"
            # Находим дочерние группы
            local children=$(sed -n "/^\[${group}:children\]/,/^\[/p" "$ini_file" | grep -v "^\[" | grep -v "^$" | head -n -1)
            for child in $children; do
                echo "    └── $child"
            done
        else
            # Подсчитываем хосты в группе
            local count=$(grep -c "^[0-9]" "$ini_file" 2>/dev/null || echo "0")
            echo "  📄 $group ($count хостов)"
        fi
    done
    
    echo "============================================================"
}

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
        echo "   Создайте inventory файл или используйте существующий."
        sleep 3
        return 1
    fi
    
    local total=${#ini_files[@]}
    for i in "${!ini_files[@]}"; do
        local num=$((i+1))
        local size=$(du -h "${ini_files[$i]}" | cut -f1)
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
        
        # Показываем структуру
        parse_ini_structure "$TARGET_INI"
        sleep 2
        return 0
    else
        echo "Ошибка: неверный выбор!"
        sleep 1
        return 1
    fi
}

# ============================================================
# Функция: Выбор хоста или группы из INI
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
    
    # Собираем все группы
    local groups=()
    local group_hosts=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            local group_name="${BASH_REMATCH[1]}"
            if [[ "$group_name" != "all:vars" && "$group_name" != "all_hosts" ]]; then
                # Проверяем, есть ли хосты в этой группе
                local has_hosts=$(sed -n "/^\[${group_name}\]/,/^\[/p" "$TARGET_INI" | grep -c "^[0-9]")
                if [[ $has_hosts -gt 0 ]]; then
                    groups+=("$group_name")
                    group_hosts+=("$has_hosts")
                fi
            fi
        fi
    done < "$TARGET_INI"
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        echo "❌ В INI файле нет групп с хостами!"
        return 1
    fi
    
    echo "📊 ДОСТУПНЫЕ ГРУППЫ И ХОСТЫ:"
    echo "============================================================"
    
    local option_num=1
    local option_map=()
    
    for i in "${!groups[@]}"; do
        local group="${groups[$i]}"
        local count="${group_hosts[$i]}"
        
        # Проверяем, является ли группа родительской
        local is_parent=$(grep -c "^\[${group}:children\]" "$TARGET_INI")
        if [[ $is_parent -gt 0 ]]; then
            echo "  📁 $option_num) $group/ (родительская, содержит $count хостов в дочерних группах)"
        else
            echo "  📄 $option_num) $group (хостов: $count)"
        fi
        option_map+=("group:$group")
        ((option_num++))
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
        local type="${selected%%:*}"
        local name="${selected#*:}"
        
        if [[ "$type" == "group" ]]; then
            # Проверяем, есть ли хосты в группе
            local has_hosts=$(sed -n "/^\[${name}\]/,/^\[/p" "$TARGET_INI" | grep -c "^[0-9]")
            
            if [[ $has_hosts -gt 0 ]]; then
                # Группа с хостами - используем как цель
                TARGET_GROUP="$name"
                TARGET_HOST="$name"
                echo "✅ Выбрана группа: $name ($has_hosts хостов)"
                sleep 2
                return 0
            else
                # Родительская группа - показываем дочерние
                echo "📁 Родительская группа: $name"
                echo "   Доступные дочерние группы:"
                local children=$(sed -n "/^\[${name}:children\]/,/^\[/p" "$TARGET_INI" | grep -v "^\[" | grep -v "^$" | head -n -1)
                
                local child_options=()
                local child_num=1
                for child in $children; do
                    local child_hosts=$(sed -n "/^\[${child}\]/,/^\[/p" "$TARGET_INI" | grep -c "^[0-9]")
                    echo "     $child_num) $child ($child_hosts хостов)"
                    child_options+=("$child")
                    ((child_num++))
                done
                
                read -p "Выберите дочернюю группу (1-${#child_options[@]}, 0-отмена): " child_choice
                if [[ $child_choice -ge 1 && $child_choice -le ${#child_options[@]} ]]; then
                    TARGET_GROUP="${child_options[$((child_choice-1))]}"
                    TARGET_HOST="$TARGET_GROUP"
                    echo "✅ Выбрана группа: $TARGET_GROUP"
                    sleep 2
                    return 0
                else
                    select_host_or_group
                    return
                fi
            fi
        fi
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
    echo "📡 Пинг хостов: $TARGET_HOST"
    echo "============================================================"
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m ping
}

view_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo
    echo "============================================================"
    echo "📂 Просмотр директории на $TARGET_HOST..."
    echo "============================================================"
    echo "Пример: /etc/sst-iiko/  /opt/sst-iiko/img/  и т.д."
    echo "============================================================"
    read -p "Введите путь (или '0' для отмены): " dest_dir
    
    if [[ "$dest_dir" == "0" ]]; then
        echo "Операция отменена"
        return 0
    fi
    
    if [[ -z "$dest_dir" ]]; then
        echo "Ошибка: Путь не может быть пустым!"
        return 1
    fi
    
    if [[ ! "$dest_dir" =~ /$ ]]; then
        dest_dir="$dest_dir/"
    fi
    
    echo
    echo "============================================================"
    echo "Просматриваю $dest_dir..."
    echo "============================================================"
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "ls -lth $dest_dir 2>/dev/null || echo '❌ Директория не найдена'" --become
}

copy_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    
    echo "============================================================"
    echo "📁 ДОСТУПНЫЕ ФАЙЛЫ В ~/WORK/FILES/:"
    echo "============================================================"
    ls -lth ~/WORK/FILES/ 2>/dev/null || echo "❌ ~/WORK/FILES/ не существует"
    echo "============================================================"
    read -p "Введите имя файла/папки для копирования: " filename
    
    if [[ -z "$filename" ]]; then
        echo "Ошибка: Имя не может быть пустым!"
        return 1
    fi
    
    local source_path="$HOME/WORK/FILES/$filename"
    if [[ ! -e "$source_path" ]]; then
        echo "❌ $source_path не найден!"
        return 1
    fi
    
    echo "============================================================"
    echo "Введите путь для копирования на удаленный хост:"
    echo "Пример: /etc/sst-iiko/  /opt/sst-iiko/  и т.д."
    echo "============================================================"
    read -p "Введите путь (или '0' для отмены): " dest_dir
    
    if [[ "$dest_dir" == "0" ]]; then
        echo "Операция отменена"
        return 0
    fi
    
    if [[ -z "$dest_dir" ]]; then
        echo "Ошибка: Путь не может быть пустым!"
        return 1
    fi
    
    if [[ ! "$dest_dir" =~ /$ ]]; then
        dest_dir="$dest_dir/"
    fi
    
    echo
    echo "============================================================"
    echo "📤 Копирую '$filename' в $dest_dir..."
    echo "============================================================"
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m copy -a "src=$source_path dest=$dest_dir" --become
}

delete_files() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo
    echo "============================================================"
    echo "🗑️ УДАЛЕНИЕ ФАЙЛОВ НА $TARGET_HOST"
    echo "============================================================"
    echo "Введите путь для поиска:"
    echo "Пример: /etc/sst-iiko/  /opt/sst-iiko/  и т.д."
    echo "============================================================"
    read -p "Введите путь (или '0' для отмены): " dest_dir
    
    if [[ "$dest_dir" == "0" ]]; then
        echo "Операция отменена"
        return 0
    fi
    if [[ -z "$dest_dir" ]]; then
        echo "Ошибка: Путь не может быть пустым!"
        return 1
    fi
    if [[ ! "$dest_dir" =~ /$ ]]; then
        dest_dir="$dest_dir/"
    fi
    
    echo
    echo "============================================================"
    echo "Выберите способ удаления:"
    echo " 1) Удалить по имени файла"
    echo " 2) Удалить по контрольной сумме (MD5)"
    echo " 0) Отмена"
    echo "============================================================"
    read -p "Введите номер (0-2): " delete_method
    
    case $delete_method in
        0)  echo "Операция отменена"
            return 0 ;;
        1)  read -p "Введите имя файла для удаления (или '0' для отмены): " filename
            if [[ "$filename" == "0" ]]; then
                echo "Операция отменена"
                return 0
            fi
            if [[ -z "$filename" ]]; then
                echo "Ошибка: Имя файла не может быть пустым!"
                return 1
            fi
            local full_path="${dest_dir}${filename}"
            echo
            read -p "Удалить '$full_path'? (y/n): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Операция отменена"
                return 0
            fi
            echo "Удаляю..."
            ansible -i "$TARGET_INI" "$TARGET_HOST" -m file -a "path='$full_path' state=absent" --become
            ;;
        2)  read -p "Введите MD5 сумму файла: " md5sum
            if [[ -z "$md5sum" ]]; then
                echo "MD5 сумма не может быть пустой!"
                return 1
            fi
            echo "Ищу файл с MD5: $md5sum..."
            local found_file=$(ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "find '$dest_dir' -type f -exec md5sum {} \; | grep '^$md5sum ' | head -1 | awk '{print \$2}'" --become 2>/dev/null | grep -v "changed" | tail -1)
            if [[ -z "$found_file" ]]; then
                echo "❌ Файл с MD5 $md5sum не найден!"
                return 1
            fi
            echo "Найден файл: $found_file"
            read -p "Удалить этот файл? (y/n): " confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Отмена" && return 0
            ansible -i "$TARGET_INI" "$TARGET_HOST" -m file -a "path='$found_file' state=absent" --become
            ;;
        *)  echo "Неверный выбор!"
            return 1 ;;
    esac
}

view_config() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo
    echo "============================================================"
    echo "📄 ПРОСМОТР КОНФИГА /etc/sst-iiko/settings.ini"
    echo "============================================================"
    echo " 1) Весь конфиг"
    echo " 2) Конкретные параметры"
    echo " 0) Назад"
    echo "============================================================"
    read -p "Введите номер (0-2): " mode
    
    case $mode in
        0) return 0 ;;
        1) ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '❌ Файл не найден'" --become ;;
        2) read -p "Введите параметры через пробел: " params
            if [[ -z "$params" ]]; then
                echo "Ошибка: Параметры не могут быть пустыми!"
                return 1
            fi
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
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Перезапуск отменен"
        return 0
    fi
    
    echo "🔄 Перезапускаю SST..."
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "$(cat <<'EOF'
if systemctl is-enabled sst-iiko >/dev/null 2>&1; then
    sudo systemctl restart sst-iiko
    echo "✅ sst-iiko перезапущен"
elif systemctl is-enabled xsst-iiko >/dev/null 2>&1; then
    sudo systemctl restart xsst-iiko
    echo "✅ xsst-iiko перезапущен"
else
    echo "❌ Сервис SST не найден"
fi
EOF
)" --become
}

status_sst() {
    if [[ -z "$TARGET_HOST" ]]; then
        echo "❌ Не выбран хост или группа!"
        return 1
    fi
    echo "============================================================"
    echo "📊 СТАТУС SST НА $TARGET_HOST"
    echo "============================================================"
    ansible -i "$TARGET_INI" "$TARGET_HOST" -m shell -a "$(cat <<'EOF'
echo "--- Статус сервисов ---"
systemctl status sst-iiko xsst-iiko 2>/dev/null | grep -E "Loaded|Active|Main PID" || echo "❌ Сервисы не найдены"
echo ""
echo "--- Проверка порта 10000 ---"
curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" localhost:10000 2>/dev/null || echo "❌ Порт 10000 недоступен"
EOF
)" --become
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
        echo "  3) Копировать файлы (~/WORK/FILES/ → хост)"
        echo "  4) Удалить файлы"
        echo "  5) Просмотр конфига (/etc/sst-iiko/settings.ini)"
        echo "  6) Редактирование конфига (в разработке)"
        echo "  7) 🔄 RESTART SST (ОСТОРОЖНО!)"
        echo "  8) 📊 Статус SST"
        echo "  9) 🔄 Сменить точку"
        echo "  I) 🔄 Сменить INI файл"
        echo "  0) Выход"
        echo "============================================================"
        read -p "Введите номер (0-9, I): " choice

        case $choice in
            1) ping_hosts ;;
            2) view_files ;;
            3) copy_files ;;
            4) delete_files ;;
            5) view_config ;;
            6) echo "⏳ В разработке..." ;;
            7) restart_sst ;;
            8) status_sst ;;
            9) select_host_or_group ;;
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

# Сначала выбираем INI файл
select_ini_file

# Затем выбираем хост/группу
if [[ -n "$TARGET_INI" ]]; then
    select_host_or_group
fi

# Запускаем главное меню
if [[ -n "$TARGET_HOST" ]]; then
    main_menu
else
    echo "❌ Не удалось выбрать точку!"
    exit 1
fi
