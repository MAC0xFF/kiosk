#!/bin/bash

echo "[$(date "+%Y-%m-%d %H:%M:%S")] Запуск скрипта" >> /tmp/autoprint.log

# Проверяем, не выполнялась ли уже печать сегодня
if [[ -f /tmp/autoprint_$(date +"%Y.%m.%d") ]]; then
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Печать уже выполнена сегодня" >> /tmp/autoprint.log
    exit 0
fi

# Проверяем наличие ошибки в логах
if tail -n10000 $(ls -1td /var/log/sst-iiko/* 2>/dev/null) 2>/dev/null | grep -q "Failed to start operation"; then
    # Находим самый свежий R-файл
    R_FILE=$(ls -t /var/opt/sst-iiko/slip/*R* 2>/dev/null | head -1)
    
    if [[ -z "$R_FILE" ]]; then
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] R-файл не найден" >> /tmp/autoprint.log
        exit 1
    fi
    
    # Создаем временный файл с отформатированным содержимым
    TEMP_FILE="/tmp/autoprint_formatted_$(date +%s)"
    
    width=30
    
    cat "$R_FILE" | while IFS= read -r line; do
        # Удаляем начальные пробелы
        line=$(echo "$line" | sed 's/^[[:space:]]*//')

        # Определяем первый символ
        first_char="${line:0:1}"

        # Проверяем, что строка состоит в основном из одинаковых символов
        if [[ "$first_char" == "-" ]] && [[ $(echo "$line" | tr -d '-') == "" ]]; then
            printf '%.0s-' $(seq 1 $width); echo
        elif [[ "$first_char" == "*" ]] && [[ $(echo "$line" | tr -d '*') == "" ]]; then
            printf '%.0s*' $(seq 1 $width); echo
        elif [[ "$first_char" == "=" ]] && [[ $(echo "$line" | tr -d '=') == "" ]]; then
            printf '%.0s=' $(seq 1 $width); echo
        elif [[ "$line" == ~Q* ]] && [[ $(echo "${line:2}" | tr -d '=') == "" ]]; then
            echo "~Q$(printf '%.0s=' $(seq 1 $(($width-2))))"
        elif [[ "$line" == *"Отчет закончен"* ]]; then
            # Фиксируем строку "Отчет закончен" как 30 символов
            current="********* Отчет закончен *********"
            if [ ${#current} -lt $width ]; then
                # Добавляем звездочки справа
                echo "$current$(printf '*%.0s' $(seq 1 $(($width - ${#current}))))"
            elif [ ${#current} -gt $width ]; then
                # Обрезаем справа
                echo "${current:0:$width}"
            else
                echo "$current"
            fi
        else
            # Обычный текст - сжимаем пробелы и обрезаем
            line=$(echo "$line" | sed 's/[[:space:]][[:space:]]*/ /g; s/ *: */: /g')
            if [ ${#line} -gt $width ]; then
                echo "${line:0:$width}"
            else
                echo "$line"
            fi
        fi
    done > "$TEMP_FILE"
    
    # Определяем, какой принтер доступен
    PRINTER=""
    if lpstat -p REXOD 2>/dev/null | grep -q "enabled"; then 
        PRINTER="REXOD"
    elif lpstat -p SAM4S 2>/dev/null | grep -q "enabled"; then 
        PRINTER="SAM4S"
    elif lpstat -p SAM4S_VCOM 2>/dev/null | grep -q "enabled"; then 
        PRINTER="SAM4S_VCOM"
    elif lpstat -p VKP80 2>/dev/null | grep -q "enabled"; then 
        PRINTER="VKP80"
    elif lpstat -p VKPII_VCOM 2>/dev/null | grep -q "enabled"; then 
        PRINTER="VKPII_VCOM"
    elif lpstat -p VKPIII_VCOM 2>/dev/null | grep -q "enabled"; then 
        PRINTER="VKPIII_VCOM"
    elif lpstat -p RP326 2>/dev/null | grep -q "enabled"; then 
        PRINTER="RP326"
    else
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Ошибка: ни один принтер не доступен" >> /tmp/autoprint.log
        rm -f "$TEMP_FILE"
        exit 1
    fi
    
    # Отправляем на печать отформатированный файл
    lp -d "${PRINTER}" "$TEMP_FILE"
    
    # Очищаем временный файл
    rm -f "$TEMP_FILE"
    
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Печать успешно отправлена на принтер $PRINTER" >> /tmp/autoprint.log
    touch "/tmp/autoprint_$(date +"%Y.%m.%d")" # СОЗДАЕМ ФЛАГОВЫЙ ФАЙЛ!
else
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Ошибка Failed to start operation не найдена в логах" >> /tmp/autoprint.log
    exit 1
fi

echo "[$(date "+%Y-%m-%d %H:%M:%S")] Скрипт завершен" >> /tmp/autoprint.log
