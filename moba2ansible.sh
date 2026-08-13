#!/bin/bash

#==================================================================
# Kiosk Manager - управление киосками через Ansible
#==================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
INI_FILE="inventory.ini"
TARGET_HOST=""
ANSIBLE_CMD=""

#==================================================================
# function find_ansible()
#==================================================================
find_ansible() {
    if command -v ansible &> /dev/null; then
        ANSIBLE_CMD="ansible"
        return 0
    elif [ -f "/usr/bin/ansible" ]; then
        ANSIBLE_CMD="/usr/bin/ansible"
        return 0
    elif [ -f "/usr/local/bin/ansible" ]; then
        ANSIBLE_CMD="/usr/local/bin/ansible"
        return 0
    elif [ -n "$VIRTUAL_ENV" ] && [ -f "$VIRTUAL_ENV/bin/ansible" ]; then
        ANSIBLE_CMD="$VIRTUAL_ENV/bin/ansible"
        return 0
    else
        echo -e "${RED}[ERROR] Ansible не найден в системе!${NC}"
        echo "Проверьте, что Ansible установлен и доступен в PATH"
        return 1
    fi
}

#==================================================================
# function parse_ini()
#==================================================================
parse_ini() {
    if [ ! -f "$INI_FILE" ]; then
        echo -e "${RED}[ERROR] Файл $INI_FILE не найден!${NC}"
        return 1
    fi
    
    # Извлекаем все группы (секции без :children)
    GROUPS=$(grep -E '^\[.*\]$' "$INI_FILE" | grep -v ':children' | sed 's/\[//g' | sed 's/\]//g' | grep -v 'all:vars' | grep -v 'all_hosts')
    
    if [ -z "$GROUPS" ]; then
        echo -e "${RED}[ERROR] Не найдено групп в $INI_FILE${NC}"
        return 1
    fi
    
    return 0
}

#==================================================================
# function get_hosts_count()
#==================================================================
get_hosts_count() {
    local group=$1
    # Считаем количество IP адресов в группе
    local count=$(grep -A 100 "\[$group\]" "$INI_FILE" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l)
    echo "$count"
}

#==================================================================
# function get_host_names()
#==================================================================
get_host_names() {
    local group=$1
    # Извлекаем IP и имена хостов из группы
    grep -A 100 "\[$group\]" "$INI_FILE" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | while read line; do
        local ip=$(echo "$line" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        local name=$(echo "$line" | sed 's/^[0-9.]*#\?//' | sed 's/#.*//' | xargs)
        if [ -z "$name" ] || [ "$name" = "$ip" ]; then
            echo "$ip"
        else
            echo "$ip ($name)"
        fi
    done
}

#==================================================================
# function select_host()
#==================================================================
select_host() {
    clear
    echo "============================================================"
    echo "              ВЫБЕРИ ХОСТ ИЛИ ГРУППУ"
    echo "============================================================"
    echo "  INI файл: $INI_FILE"
    echo "============================================================"
    
    parse_ini || return 1
    
    echo ""
    echo "AVAILABLE GROUPS:"
    echo "------------------------------------------------------------"
    
    local i=1
    declare -a GROUP_ARRAY
    
    while read -r group; do
        if [ -n "$group" ]; then
            local count=$(get_hosts_count "$group")
            GROUP_ARRAY[$i]="$group"
            printf "  %3d) [HOST] %s (%d hosts)\n" "$i" "$group" "$count"
            ((i++))
        fi
    done <<< "$GROUPS"
    
    echo "------------------------------------------------------------"
    echo "  0) Выход"
    echo "============================================================"
    
    read -p "Введите номер (1-$((i-1)), 0-выход): " choice
    
    if [ -z "$choice" ]; then
        return 1
    fi
    
    if [ "$choice" = "0" ]; then
        exit 0
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((i-1)) ]; then
        TARGET_HOST="${GROUP_ARRAY[$choice]}"
        local count=$(get_hosts_count "$TARGET_HOST")
        echo ""
        echo -e "${GREEN}[OK] Выбрана группа: $TARGET_HOST${NC}"
        echo "   Хостов: $count"
        return 0
    else
        echo -e "${RED}[ERROR] Неверный выбор!${NC}"
        return 1
    fi
}

#==================================================================
# function run_ansible()
#==================================================================
run_ansible() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    local args="$1"
    local cmd="$ANSIBLE_CMD -i $INI_FILE $TARGET_HOST $args"
    
    echo ""
    echo -e "${BLUE}[RUN] Выполняю: $cmd${NC}"
    echo "------------------------------------------------------------"
    eval "$cmd"
    echo "------------------------------------------------------------"
}

#==================================================================
# function ping()
#==================================================================
ping_hosts() {
    run_ansible "-m ping"
}

#==================================================================
# function view_files()
#==================================================================
view_files() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo "ПРОСМОТР ДИРЕКТОРИИ"
    echo "============================================================"
    echo "Пример: /etc/sst-iiko/  /opt/sst-iiko/img/"
    echo "============================================================"
    
    read -p "Введите путь (или '0' для отмены): " path
    if [ "$path" = "0" ] || [ -z "$path" ]; then
        return 0
    fi
    
    if [[ "$path" != */ ]]; then
        path="${path}/"
    fi
    
    run_ansible "-m shell -a \"ls -lth $path 2>/dev/null || echo '[ERROR] Директория не найдена'\" --become"
}

#==================================================================
# function copy_files()
#==================================================================
copy_files() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo "ФАЙЛЫ В ~/WORK/FILES/:"
    echo "============================================================"
    ls -lth ~/WORK/FILES/ 2>/dev/null || echo "[ERROR] ~/WORK/FILES/ не существует"
    echo "============================================================"
    
    read -p "Введите имя файла для копирования (или '0' для отмены): " filename
    if [ "$filename" = "0" ] || [ -z "$filename" ]; then
        return 0
    fi
    
    local source="$HOME/WORK/FILES/$filename"
    if [ ! -f "$source" ]; then
        echo -e "${RED}[ERROR] $source не найден!${NC}"
        return 1
    fi
    
    read -p "Введите путь для копирования (или '0' для отмены): " dest
    if [ "$dest" = "0" ] || [ -z "$dest" ]; then
        return 0
    fi
    
    if [[ "$dest" != */ ]]; then
        dest="${dest}/"
    fi
    
    run_ansible "-m copy -a \"src=$source dest=$dest\" --become"
}

#==================================================================
# function delete_files()
#==================================================================
delete_files() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo "УДАЛЕНИЕ ФАЙЛОВ"
    echo "============================================================"
    echo "Введите путь для поиска:"
    echo "Пример: /etc/sst-iiko/  /opt/sst-iiko/"
    echo "============================================================"
    
    read -p "Введите путь (или '0' для отмены): " path
    if [ "$path" = "0" ] || [ -z "$path" ]; then
        return 0
    fi
    
    if [[ "$path" != */ ]]; then
        path="${path}/"
    fi
    
    echo "Выберите способ удаления:"
    echo "  1) По имени файла"
    echo "  2) По MD5 сумме"
    echo "  0) Отмена"
    
    read -p "Введите номер (0-2): " method
    if [ "$method" = "0" ] || [ -z "$method" ]; then
        return 0
    fi
    
    if [ "$method" = "1" ]; then
        read -p "Введите имя файла для удаления: " filename
        if [ -z "$filename" ]; then
            return 1
        fi
        local full_path="${path}${filename}"
        read -p "Удалить '$full_path'? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            run_ansible "-m file -a \"path='$full_path' state=absent\" --become"
        fi
    elif [ "$method" = "2" ]; then
        read -p "Введите MD5 сумму файла: " md5
        if [ -z "$md5" ]; then
            return 1
        fi
        run_ansible "-m shell -a \"find '$path' -type f -exec md5sum {} \\; | grep '^$md5 ' | head -1 | awk '{print \$2}' | xargs rm -f\" --become"
    else
        echo -e "${RED}[ERROR] Неверный выбор!${NC}"
    fi
}

#==================================================================
# function view_config()
#==================================================================
view_config() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo "ПРОСМОТР КОНФИГА /etc/sst-iiko/settings.ini"
    echo "============================================================"
    echo "  1) Весь конфиг"
    echo "  2) Конкретные параметры"
    echo "  3) Изменить параметры"
    echo "  0) Назад"
    echo "============================================================"
    
    read -p "Введите номер (0-3): " choice
    
    case $choice in
        1)
            run_ansible "-m shell -a \"cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Файл не найден'\" --become"
            ;;
        2)
            read -p "Введите параметры через пробел: " params
            if [ -n "$params" ]; then
                local pattern=$(echo "$params" | tr ' ' '|')
                run_ansible "-m shell -a \"grep -E '^($pattern)=' /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Параметры не найдены'\" --become"
            fi
            ;;
        3)
            edit_config
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}[ERROR] Неверный выбор!${NC}"
            ;;
    esac
}

#==================================================================
# function edit_config()
#==================================================================
edit_config() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo "ИЗМЕНЕНИЕ ПАРАМЕТРОВ КОНФИГА"
    echo "============================================================"
    echo "Введите параметр и новое значение"
    echo "Пример: productDescriptionTypes=card, info"
    echo "Пример: showFoodValues=Never"
    echo "============================================================"
    
    read -p $'\n'"Введите параметр и значение (параметр=значение) или '0' для отмены: " param_input
    if [ "$param_input" = "0" ] || [ -z "$param_input" ]; then
        echo "[CANCEL] Отменено"
        return 0
    fi
    
    if [[ ! "$param_input" =~ = ]]; then
        echo -e "${RED}[ERROR] Неверный формат! Используйте: параметр=значение${NC}"
        return 1
    fi
    
    local param=$(echo "$param_input" | cut -d'=' -f1 | xargs)
    local value=$(echo "$param_input" | cut -d'=' -f2- | xargs)
    
    if [ -z "$param" ] || [ -z "$value" ]; then
        echo -e "${RED}[ERROR] Параметр и значение не могут быть пустыми!${NC}"
        return 1
    fi
    
    echo ""
    echo "============================================================"
    echo "Будет изменен параметр: $param=$value"
    echo "============================================================"
    read -p "Продолжить? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "[CANCEL] Отменено"
        return 0
    fi
    
    local cmd="grep -q '^$param=' /etc/sst-iiko/settings.ini && sed -i 's/^$param=.*/$param=$value/' /etc/sst-iiko/settings.ini || echo '$param=$value' >> /etc/sst-iiko/settings.ini && echo '[OK] $param=$value'"
    
    run_ansible "-m shell -a \"$cmd\" --become"
}

#==================================================================
# function restart_sst()
#==================================================================
restart_sst() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    echo "============================================================"
    echo -e "${YELLOW}ВНИМАНИЕ! Перезапуск SST!${NC}"
    echo "============================================================"
    echo ""
    
    read -p "Перезапустить SST на всех хостах группы? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "[CANCEL] Отменено"
        return 0
    fi
    
    echo ""
    echo "Перезапуск SST..."
    echo "------------------------------------------------------------"
    
    local cmd="if systemctl status sst-iiko 2>/dev/null | grep -q 'Active: active'; then sudo systemctl restart sst-iiko && echo '[OK] sst-iiko restarted'; elif systemctl status xsst-iiko 2>/dev/null | grep -q 'Active: active'; then sudo systemctl restart xsst-iiko && echo '[OK] xsst-iiko restarted'; else echo '[WARN] No active SST service found'; fi"
    
    run_ansible "-m shell -a \"$cmd\" --become"
}

#==================================================================
# function status_sst()
#==================================================================
status_sst() {
    if [ -z "$INI_FILE" ] || [ -z "$TARGET_HOST" ]; then
        echo -e "${RED}[ERROR] Не выбрана точка!${NC}"
        return 1
    fi
    
    local cmd='echo "=== SST STATUS ===" && sst_status=$(systemctl status sst-iiko 2>/dev/null | grep -E "Active:" | sed "s/^.*Active: //") && xsst_status=$(systemctl status xsst-iiko 2>/dev/null | grep -E "Active:" | sed "s/^.*Active: //") && echo "    sst-iiko - $sst_status" && echo "    xsst-iiko - $xsst_status" && echo "" && echo "=== API INFO ===" && curl -sw "HTTP: %{http_code}\n" localhost:10000 2>/dev/null | grep -E "Current state|Hardware|Fiscal|Network|Terminal|deviceName|Theme|Version|HTTP:" || echo "[ERROR] Port 10000 unavailable"'
    
    run_ansible "-m shell -a '$cmd' --become"
}

#==================================================================
# function main_menu()
#==================================================================
main_menu() {
    while true; do
        clear
        echo "============================================================"
        echo "              УПРАВЛЕНИЕ КИОСКАМИ"
        echo "============================================================"
        echo "  INI файл: $INI_FILE"
        echo "  Точка:    ${TARGET_HOST:-не выбрана}"
        if [ -n "$TARGET_HOST" ]; then
            local count=$(get_hosts_count "$TARGET_HOST")
            echo "  Хостов:   $count"
        fi
        echo "============================================================"
        echo "  1) Пинг хоста/группы"
        echo "  2) Просмотр директории"
        echo "  3) Копировать файлы"
        echo "  4) Удалить файлы"
        echo "  5) Просмотр/изменение конфига"
        echo "  6) RESTART SST (ОСТОРОЖНО!)"
        echo "  7) Статус SST"
        echo "  8) Сменить точку"
        echo "  0) Выход"
        echo "============================================================"
        
        read -p "Введите номер (0-8): " choice
        
        case $choice in
            0)
                echo "Выход..."
                exit 0
                ;;
            1)
                ping_hosts
                ;;
            2)
                view_files
                ;;
            3)
                copy_files
                ;;
            4)
                delete_files
                ;;
            5)
                view_config
                ;;
            6)
                restart_sst
                ;;
            7)
                status_sst
                ;;
            8)
                select_host
                ;;
            *)
                echo -e "${RED}[ERROR] Неверный выбор!${NC}"
                ;;
        esac
        
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

#==================================================================
# MAIN
#==================================================================
main() {
    # Очищаем экран при старте
    clear
    
    echo "============================================================"
    echo "              ЗАПУСК УПРАВЛЕНИЯ КИОСКАМИ"
    echo "============================================================"
    echo ""
    
    # Находим Ansible
    if ! find_ansible; then
        exit 1
    fi
    
    # Проверяем наличие inventory.ini
    if [ ! -f "$INI_FILE" ]; then
        echo -e "${RED}[ERROR] Файл $INI_FILE не найден!${NC}"
        exit 1
    fi
    
    # Очищаем переменные окружения, мешающие SSH
    unset ANSIBLE_SSH_ARGS
    unset GIT_SSH_COMMAND
    unset SSH_CONFIG
    
    # Проверяем ~/.ssh/config на наличие ссылки на config_mobaxterm
    if [ -f ~/.ssh/config ] && grep -q "config_mobaxterm" ~/.ssh/config; then
        echo -e "${YELLOW}[WARN] В ~/.ssh/config найдена ссылка на config_mobaxterm${NC}"
        echo "[INFO] Создаем резервную копию и исправляем..."
        cp ~/.ssh/config ~/.ssh/config.bak
        echo "# Clean config created by KioskManager" > ~/.ssh/config
        echo "Host *" >> ~/.ssh/config
        echo "    StrictHostKeyChecking no" >> ~/.ssh/config
        echo "    UserKnownHostsFile /dev/null" >> ~/.ssh/config
        echo -e "${GREEN}[INFO] Создан бэкап: ~/.ssh/config.bak${NC}"
    fi
    
    # Выбор хоста/группы
    if ! select_host; then
        echo -e "${RED}[ERROR] Не удалось выбрать точку!${NC}"
        exit 1
    fi
    
    # Запуск главного меню
    main_menu
}

# Запуск
main
