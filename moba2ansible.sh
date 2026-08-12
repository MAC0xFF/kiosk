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
        local first_ini=$(find . -maxdepth 1 -name "*.ini" -type f | head -1 | sed 's/^\.\///')
        if [[ -n "$first_ini" ]]; then
            echo "$first_ini"
        else
            echo ""
        fi
    fi
}

# ============================================================
# Функция: Парсинг INI файла и построение дерева
# ============================================================
parse_ini_tree() {
    local ini_file="$1"
    
    if [[ ! -f "$ini_file" ]]; then
        echo "❌ INI файл не найден: $ini_file"
        return 1
    fi
    
    # Собираем все группы и их детей
    declare -A group_children
    declare -A group_hosts
    declare -A group_is_parent
    
    # Первый проход: собираем все группы
    local current_group=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            current_group="${BASH_REMATCH[1]}"
            if [[ "$current_group" != "all:vars" && "$current_group" != "all_hosts" ]]; then
                # Проверяем, есть ли у этой группы children
                local has_children=$(grep -c "^\[${current_group}:children\]" "$ini_file" 2>/dev/null || echo "0")
                if [[ $has_children -gt 0 ]]; then
                    group_is_parent["$current_group"]=1
                else
                    group_is_parent["$current_group"]=0
                    # Считаем хосты в группе
                    local count=$(sed -n "/^\[${current_group}\]/,/^\[/p" "$ini_file" | grep -c "^[0-9]" 2>/dev/null || echo "0")
                    group_hosts["$current_group"]="$count"
                fi
            fi
        fi
    done < "$ini_file"
    
    # Второй проход: собираем детей для родительских групп
    for group in "${!group_is_parent[@]}"; do
        if [[ ${group_is_parent[$group]} -eq 1 ]]; then
            local children=$(sed -n "/^\[${group}:children\]/,/^\[/p" "$ini_file" | grep -v "^\[" | grep -v "^$" | head -n -1)
            group_children["$group"]="$children"
        fi
    done
    
    # Выводим дерево
    echo "📊 ДЕРЕВО ГРУПП:"
    echo "============================================================"
    
    # Находим корневые группы (те, у которых нет родителей)
    local all_groups=()
    for group in "${!group_is_parent[@]}"; do
        all_groups+=("$group")
    done
    
    # Простая рекурсивная функция для вывода дерева
    print_tree() {
        local group="$1"
        local prefix="$2"
        local is_last="$3"
        local children="${group_children[$group]}"
        
        if [[ ${group_is_parent[$group]} -eq 1 ]]; then
            # Родительская группа
            if [[ -n "$children" ]]; then
                local child_count=$(echo "$children" | wc -w)
                echo "${prefix}${is_last:+└── }📁 $group/ ($child_count дочерних групп)"
                
                local new_prefix="${prefix}${is_last:+    }"
                local child_array=($children)
                local total=${#child_array[@]}
                local counter=0
                
                for child in "${child_array[@]}"; do
                    ((counter++))
                    if [[ $counter -eq $total ]]; then
                        print_tree "$child" "$new_prefix" "true"
                    else
                        print_tree "$child" "$new_prefix" "false"
                    fi
                done
            else
                echo "${prefix}${is_last:+└── }📁 $group/ (пустая)"
            fi
        else
            # Листовая группа с хостами
            local host_count=${group_hosts[$group]:-0}
            echo "${prefix}${is_last:+└── }📄 $group ($host_count хостов)"
        fi
    }
    
    # Находим корневые группы (те, у которых нет родителей)
    # Сначала найдем все группы, которые являются чьими-то детьми
    local all_children=""
    for group in "${!group_children[@]}"; do
        all_children="$all_children ${group_children[$group]}"
    done
    
    local root_groups=()
    for group in "${!group_is_parent[@]}"; do
        if [[ ! " $all_children " =~ " $group " ]]; then
            root_groups+=("$group")
        fi
    done
    
    # Если нет корневых групп, берем все
    if [[ ${#root_groups[@]} -eq 0 ]]; then
        root_groups=("${!group_is_parent[@]}")
    fi
    
    # Выводим дерево
    local total=${#root_groups[@]}
    local counter=0
    for root in "${root_groups[@]}"; do
        ((counter++))
        if [[ $counter -eq $total ]]; then
            print_tree "$root" "" "true"
        else
            print_tree "$root" "" "false"
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
    
    mapfile -t ini_files < <(find . -maxdepth 1 -name "*.ini" -type f | sed 's/^\.\///' | sort)
    
    if [[ ${#ini_files[@]} -eq 0 ]]; then
        echo "❌ Нет .ini файлов в текущей директории!"
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
        
        # Показываем дерево
        parse_ini_tree "$TARGET_INI"
        echo ""
        read -p "Нажмите Enter для продолжения..."
        return 0
    else
        echo "Ошибка: неверный выбор!"
        sleep 1
        return 1
    fi
}

# ============================================================
# Функция: Выбор хоста или группы из INI (с древовидным выводом)
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
    
    # Собираем структуру
    declare -A group_children
    declare -A group_hosts
    declare -A group_is_parent
    declare -A group_number
    
    local current_group=""
    local option_num=1
    local option_map=()
    
    # Первый проход: собираем все группы
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            current_group="${BASH_REMATCH[1]}"
            if [[ "$current_group" != "all:vars" && "$current_group" != "all_hosts" ]]; then
                local has_children=$(grep -c "^\[${current_group}:children\]" "$TARGET_INI" 2>/dev/null || echo "0")
                if [[ $has_children -gt 0 ]]; then
                    group_is_parent["$current_group"]=1
                else
                    group_is_parent["$current_group"]=0
                    local count=$(sed -n "/^\[${current_group}\]/,/^\[/p" "$TARGET_INI" | grep -c "^[0-9]" 2>/dev/null || echo "0")
                    group_hosts["$current_group"]="$count"
                fi
            fi
        fi
    done < "$TARGET_INI"
    
    # Второй проход: собираем детей
    for group in "${!group_is_parent[@]}"; do
        if [[ ${group_is_parent[$group]} -eq 1 ]]; then
            local children=$(sed -n "/^\[${group}:children\]/,/^\[/p" "$TARGET_INI" | grep -v "^\[" | grep -v "^$" | head -n -1)
            group_children["$group"]="$children"
        fi
    done
    
    # Функция для вывода дерева с номерами
    print_tree_with_numbers() {
        local group="$1"
        local prefix="$2"
        local is_last="$3"
        local children="${group_children[$group]}"
        
        if [[ ${group_is_parent[$group]} -eq 1 ]]; then
            # Родительская группа
            echo "${prefix}${is_last:+└── }📁 $group/"
            local new_prefix="${prefix}${is_last:+    }"
            local child_array=($children)
            local total=${#child_array[@]}
            local counter=0
            
            for child in "${child_array[@]}"; do
                ((counter++))
                if [[ $counter -eq $total ]]; then
                    print_tree_with_numbers "$child" "$new_prefix" "true"
                else
                    print_tree_with_numbers "$child" "$new_prefix" "false"
                fi
            done
        else
            # Листовая группа с хостами
            local host_count=${group_hosts[$group]:-0}
            group_number["$group"]="$option_num"
            option_map+=("$group")
            printf "%s%s%4d) 📄 %s (%d хостов)\n" \
                "$prefix" "${is_last:+└── }" "$option_num" "$group" "$host_count"
            ((option_num++))
        fi
    }
    
    # Находим корневые группы
    local all_children=""
    for group in "${!group_children[@]}"; do
        all_children="$all_children ${group_children[$group]}"
    done
    
    local root_groups=()
    for group in "${!group_is_parent[@]}"; do
        if [[ ! " $all_children " =~ " $group " ]]; then
            root_groups+=("$group")
        fi
    done
    
    if [[ ${#root_groups[@]} -eq 0 ]]; then
        root_groups=("${!group_is_parent[@]}")
    fi
    
    echo "📊 ДЕРЕВО ГРУПП С НОМЕРАМИ:"
    echo "============================================================"
    
    local total=${#root_groups[@]}
    local counter=0
    for root in "${root_groups[@]}"; do
        ((counter++))
        if [[ $counter -eq $total ]]; then
            print_tree_with_numbers "$root" "" "true"
        else
            print_tree_with_numbers "$root" "" "false"
        fi
    done
    
    echo "============================================================"
    echo "  0) Выход"
    echo "  F) Выбрать другой INI файл"
    echo "============================================================"
    read -p "Введите номер (1-$((option_num-1)), 0-выход, F-сменить INI): " choice
    
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
    elif [[ $choice -ge 1 && $choice -le ${#option_map[@]} ]]; then
        local selected_group="${option_map[$((choice-1))]}"
        TARGET_GROUP="$selected_group"
        TARGET_HOST="$selected_group"
        
        local host_count=${group_hosts[$selected_group]:-0}
        echo "✅ Выбрана группа: $selected_group ($host_count хостов)"
        sleep 2
        return 0
    else
        echo "Ошибка: неверный выбор!"
        sleep 1
        select_host_or_group
    fi
}

# ============================================================
# Функции управления (остаются без изменений)
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
