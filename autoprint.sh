sudo bash -c 'cat <<"EOF" > /home/proxyuser/autoprint.sh
#!/bin/bash

echo "[$(date "+%Y-%m-%d %H:%M:%S")] Запуск скрипта" >> /tmp/autoprint.log

# Проверяем, не выполнялась ли уже печать сегодня
if [[ -f /tmp/autoprint_$(date +"%Y.%m.%d") ]]; then
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Печать уже выполнена сегодня" >> /tmp/autoprint.log
    exit 0
fi

R_FILE=$(ls -t /var/opt/sst-iiko/slip/*R* 2>/dev/null | head -1)

# Проверяем наличие ошибки в логах
if tail -n10000 $(ls -1td /var/log/sst-iiko/* 2>/dev/null) | grep "Failed to start operation" | grep $(date "+%Y.%m.%d")
then
    # Определяем, какой принтер доступен
    if lpstat -p REXOD 2>/dev/null | grep -q "enabled"; then PRINTER="REXOD"
    elif lpstat -p SAM4S 2>/dev/null | grep -q "enabled"; then PRINTER="SAM4S"
    elif lpstat -p SAM4S_VCOM 2>/dev/null | grep -q "enabled"; then PRINTER="SAM4S_VCOM"
    elif lpstat -p VKP80 2>/dev/null | grep -q "enabled"; then PRINTER="VKP80"
    elif lpstat -p VKPII_VCOM 2>/dev/null | grep -q "enabled"; then PRINTER="VKPII_VCOM"
    elif lpstat -p VKPIII_VCOM 2>/dev/null | grep -q "enabled"; then PRINTER="VKPIII_VCOM"
    elif lpstat -p RP326 2>/dev/null | grep -q "enabled"; then PRINTER="RP326"
    else
        echo "Ошибка: ни один принтер не доступен" >> /tmp/autoprint.log
        exit 1
    fi
    
    lp -d ${PRINTER} "${R_FILE}"
    echo "Печать успешно отправлена" >> /tmp/autoprint.log
    touch /tmp/autoprint_$(date +"%Y.%m.%d") # СОЗДАЕМ ФЛАГОВЫЙ ФАЙЛ!
else
    #echo "Ошибка Failed to start operation не найдена в логах" >> /tmp/autoprint.log
    exit 1
fi

echo "[$(date "+%Y-%m-%d %H:%M:%S")] Скрипт завершен" >> /tmp/autoprint.log
EOF'

chmod +x /home/proxyuser/autoprint.sh
chown proxyuser:proxyuser /home/proxyuser/autoprint.sh

echo '* 21-23 * * * proxyuser bash -c '\''[ ! -f "/tmp/autoprint_$(date +\%Y.\%m.\%d)" ] \
&& [ -f /home/proxyuser/autoprint.sh ] && /home/proxyuser/autoprint.sh'\'' | sudo tee /etc/cron.d/print-job
sudo systemctl restart cron
