#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import subprocess
import re
from collections import defaultdict

class KioskManager:
    def __init__(self):
        self.ini_file = "inventory.ini"
        self.target_host = None
        self.groups = []
        self.group_hosts = {}
        self.host_names = {}  # Словарь для хранения имен хостов {ip: name}
        self.tree = {}
        self.flat_groups = []
        
    def clear_screen(self):
        """Очищает экран терминала"""
        if os.name == 'nt':
            os.system('cls')
        else:
            os.system('clear')
        
    def parse_ini_with_hierarchy(self, filepath):
        """Парсит INI файл с сохранением иерархии и именами хостов"""
        if not os.path.exists(filepath):
            print(f"[ERROR] Файл {filepath} не найден!")
            return None
        
        groups = {}
        children = defaultdict(list)
        current_group = None
        is_parent = {}
        self.host_names = {}  # Очищаем словарь имен
        
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            
            # Проверяем на секцию
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
                
                # Пропускаем служебные секции
                if section in ['all:vars', 'all_hosts']:
                    i += 1
                    continue
                
                # Проверяем, является ли секция children
                if ':children' in section:
                    parent = section.replace(':children', '')
                    # Читаем детей
                    i += 1
                    while i < len(lines):
                        child_line = lines[i].strip()
                        if child_line.startswith('[') and child_line.endswith(']'):
                            break
                        if child_line and not child_line.startswith('#'):
                            children[parent].append(child_line)
                        i += 1
                    continue
                else:
                    current_group = section
                    if current_group not in groups:
                        groups[current_group] = []
                        is_parent[current_group] = False
                    
                    # Читаем хосты в группе
                    i += 1
                    while i < len(lines):
                        host_line = lines[i].strip()
                        if host_line.startswith('[') and host_line.endswith(']'):
                            break
                        if host_line and not host_line.startswith('#'):
                            # Ищем IP и имя хоста
                            ip_match = re.match(r'^(\d+\.\d+\.\d+\.\d+)', host_line)
                            if ip_match:
                                ip = ip_match.group(1)
                                if ip not in groups[current_group]:
                                    groups[current_group].append(ip)
                                
                                # Ищем имя хоста в комментарии или после IP
                                name_match = re.search(r'^\d+\.\d+\.\d+\.\d+\s*#?\s*(.+?)(?:\s*#|$)', host_line)
                                if name_match:
                                    host_name = name_match.group(1).strip()
                                    if host_name and host_name not in ['', 'ansible', 'ssh']:
                                        self.host_names[ip] = host_name
                                else:
                                    if ip not in self.host_names:
                                        self.host_names[ip] = ip
                        i += 1
                    continue
            i += 1
        
        # Определяем родительские группы
        for parent in children.keys():
            if parent in is_parent:
                is_parent[parent] = True
        
        # Строим дерево
        tree = {}
        for group in groups.keys():
            is_child = False
            for parent, child_list in children.items():
                if group in child_list:
                    is_child = True
                    break
            if not is_child:
                tree[group] = self._build_subtree(group, children, groups)
        
        return tree, groups
    
    def _build_subtree(self, group, children, groups):
        """Рекурсивно строит поддерево"""
        subtree = {
            'hosts': groups.get(group, []),
            'children': {}
        }
        
        for child in children.get(group, []):
            subtree['children'][child] = self._build_subtree(child, children, groups)
        
        return subtree
    
    def _flatten_tree(self, tree, prefix=''):
        """Преобразует дерево в плоский список с путями"""
        result = []
        for name, data in tree.items():
            path = f"{prefix}/{name}" if prefix else name
            host_count = len(data.get('hosts', []))
            child_count = len(data.get('children', {}))
            
            total_hosts = host_count
            for child in data.get('children', {}).values():
                total_hosts += self._count_hosts(child)
            
            result.append({
                'name': name,
                'path': path,
                'hosts': data.get('hosts', []),
                'host_count': host_count,
                'total_hosts': total_hosts,
                'child_count': child_count,
                'children': list(data.get('children', {}).keys())
            })
            
            if data.get('children'):
                result.extend(self._flatten_tree(data['children'], path))
        
        return result
    
    def _count_hosts(self, data):
        """Подсчитывает общее количество хостов в поддереве"""
        count = len(data.get('hosts', []))
        for child in data.get('children', {}).values():
            count += self._count_hosts(child)
        return count
    
    def _get_all_hosts_from_group(self, group_name):
        """Рекурсивно собирает все хосты из группы и ее подгрупп"""
        hosts = []
        
        # Ищем группу в плоском списке
        for g in self.flat_groups:
            if g['name'] == group_name:
                # Добавляем хосты текущей группы
                hosts.extend(g['hosts'])
                # Рекурсивно добавляем хосты из дочерних групп
                for child in g['children']:
                    hosts.extend(self._get_all_hosts_from_group(child))
                break
        
        # Удаляем дубликаты
        return list(dict.fromkeys(hosts))
    
    def select_host(self):
        """Выбор хоста/группы"""
        if not os.path.exists(self.ini_file):
            print(f"[ERROR] Файл {self.ini_file} не найден!")
            return False
        
        tree, groups = self.parse_ini_with_hierarchy(self.ini_file)
        if not tree:
            print("[ERROR] Не удалось разобрать INI файл!")
            return False
        
        self.tree = tree
        self.group_hosts = groups
        
        # Получаем плоский список с путями
        self.flat_groups = self._flatten_tree(tree)
        
        print("=" * 60)
        print("              ВЫБЕРИ ХОСТ ИЛИ ГРУППУ")
        print("=" * 60)
        print(f"  INI файл: {self.ini_file}")
        print("=" * 60)
        
        # Показываем нумерованный список всех групп
        print("\nAVAILABLE GROUPS:")
        print("-" * 60)
        
        sorted_groups = sorted(self.flat_groups, key=lambda x: x['path'])
        
        for i, g in enumerate(sorted_groups, 1):
            indent = "  " * (g['path'].count('/'))
            icon = "[DIR]" if g['child_count'] > 0 else "[HOST]"
            print(f"{indent}{i:3}) {icon} {g['name']} ({g['total_hosts']} hosts)")
        
        print("-" * 60)
        print("  0) Выход")
        print("=" * 60)
        
        try:
            choice = input("Введите номер (1-{}, 0-выход): ".format(len(sorted_groups)))
            
            if not choice:
                return False
            
            choice = int(choice)
            if choice == 0:
                sys.exit(0)
            elif 1 <= choice <= len(sorted_groups):
                selected = sorted_groups[choice - 1]
                self.target_host = selected['name']
                print(f"\n[OK] Выбрана группа: {selected['path']}")
                print(f"   Хостов: {selected['host_count']}")
                print(f"   Всего хостов в поддереве: {selected['total_hosts']}")
                return True
            else:
                print("[ERROR] Неверный выбор!")
                return False
        except ValueError:
            print("[ERROR] Введите число!")
            return False
    
    def cleanup_ssh_env(self):
        """Очищает переменные окружения, мешающие SSH"""
        problematic_vars = ['ANSIBLE_SSH_ARGS', 'GIT_SSH_COMMAND', 'SSH_CONFIG']
        for var in problematic_vars:
            if var in os.environ:
                print(f"[INFO] Удаляем переменную {var}={os.environ[var]}")
                del os.environ[var]
        
        ssh_config = os.path.expanduser('~/.ssh/config')
        if os.path.exists(ssh_config):
            with open(ssh_config, 'r') as f:
                content = f.read()
                if 'config_mobaxterm' in content:
                    print("[WARN] В ~/.ssh/config найдена ссылка на config_mobaxterm")
                    print("[INFO] Создаем резервную копию и исправляем...")
                    backup = ssh_config + '.bak'
                    os.rename(ssh_config, backup)
                    print(f"[INFO] Создан бэкап: {backup}")
                    with open(ssh_config, 'w') as f:
                        f.write("# Clean config created by KioskManager\n")
                        f.write("Host *\n")
                        f.write("    StrictHostKeyChecking no\n")
                        f.write("    UserKnownHostsFile /dev/null\n")
    
    def run_ansible(self, args):
        """Запускает ansible с аргументами"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        cmd = f"ansible -i {self.ini_file} {self.target_host} {args}"
        
        print(f"\n[RUN] Выполняю: {cmd}")
        print("-" * 60)
        
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        output, _ = process.communicate()
        
        lines = output.split('\n')
        i = 0
        host_counter = 0
        
        while i < len(lines):
            line = lines[i]
            
            ip_match = re.search(r'(\d+\.\d+\.\d+\.\d+)', line)
            if ip_match:
                host_counter += 1
                ip = ip_match.group(1)
                host_name = self.host_names.get(ip, ip)
                
                if host_name != ip:
                    line = line.replace(ip, f"{ip} ({host_name})")
                
                if host_counter > 1:
                    print("=" * 60)
                
                print(line)
                
                i += 1
                while i < len(lines):
                    next_line = lines[i]
                    next_ip_match = re.search(r'^(\d+\.\d+\.\d+\.\d+)', next_line)
                    if next_ip_match:
                        break
                    
                    if next_line.strip():
                        print(next_line)
                    i += 1
                
                print()
                continue
            else:
                if line.strip():
                    print(line)
                i += 1
        
        print("-" * 60)
    
    #==================================================================
    # function ping()
    #==================================================================
    def ping(self):
        """Пинг хостов"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        # Получаем все хосты из выбранной группы (включая дочерние)
        hosts = self._get_all_hosts_from_group(self.target_host)
        
        if not hosts:
            print("[ERROR] Нет хостов в выбранной группе!")
            return
        
        print("=" * 60)
        print(f"ПИНГ ХОСТОВ: {self.target_host} (всего: {len(hosts)})")
        print("=" * 60)
        
        # Пингуем каждый хост отдельно для получения детальной информации
        success_hosts = []
        failed_hosts = []
        
        for ip in hosts:
            # Получаем имя хоста
            host_name = self.host_names.get(ip, ip)
            
            # Пингуем хост
            cmd = f"ansible -i {self.ini_file} {ip} -m ping 2>/dev/null"
            process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            output, error = process.communicate()
            
            # Определяем статус
            if "SUCCESS" in output and "pong" in output:
                status = "SUCCESS"
                success_hosts.append(ip)
            else:
                status = "UNREACHABLE!"
                failed_hosts.append(ip)
            
            # Выводим результат
            print("=" * 60)
            print(f"{ip} ({host_name}) | {status}")
        
        # Выводим статистику
        total = len(hosts)
        success_count = len(success_hosts)
        failed_count = len(failed_hosts)
        
        print("=" * 60)
        print("СТАТИСТИКА:")
        print(f"  Доступно: {success_count} из {total} хостов")
        if failed_count > 0:
            print(f"  Недоступно: {failed_count}")
            print("\nНЕДОСТУПНЫЕ ХОСТЫ:")
            for ip in failed_hosts:
                host_name = self.host_names.get(ip, ip)
                print(f"  - {ip} ({host_name})")
        print("=" * 60)
    
    #==================================================================
    # function view_files()
    #==================================================================
    def view_files(self):
        """Просмотр директории"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ПРОСМОТР ДИРЕКТОРИИ")
        print("=" * 60)
        print("Пример: /etc/sst-iiko/  /opt/sst-iiko/img/")
        print("=" * 60)
        
        path = input("Введите путь (или '0' для отмены): ")
        if path == '0' or not path:
            return
        
        if not path.endswith('/'):
            path += '/'
        
        self.run_ansible(f"-m shell -a \"ls -lth {path} 2>/dev/null || echo '[ERROR] Директория не найдена'\" --become")
    
    #==================================================================
    # function copy_files()
    #==================================================================
    def copy_files(self):
        """Копирование файлов"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ФАЙЛЫ В ~/WORK/FILES/:")
        print("=" * 60)
        os.system("ls -lth ~/WORK/FILES/ 2>/dev/null || echo '[ERROR] ~/WORK/FILES/ не существует'")
        print("=" * 60)
        
        filename = input("Введите имя файла для копирования (или '0' для отмены): ")
        if filename == '0' or not filename:
            return
        
        source = os.path.expanduser(f"~/WORK/FILES/{filename}")
        if not os.path.exists(source):
            print(f"[ERROR] {source} не найден!")
            return
        
        dest = input("Введите путь для копирования (или '0' для отмены): ")
        if dest == '0' or not dest:
            return
        
        if not dest.endswith('/'):
            dest += '/'
        
        self.run_ansible(f"-m copy -a \"src={source} dest={dest}\" --become")
    
    #==================================================================
    # function delete_files()
    #==================================================================
    def delete_files(self):
        """Удаление файлов"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("УДАЛЕНИЕ ФАЙЛОВ")
        print("=" * 60)
        print("Введите путь для поиска:")
        print("Пример: /etc/sst-iiko/  /opt/sst-iiko/")
        print("=" * 60)
        
        path = input("Введите путь (или '0' для отмены): ")
        if path == '0' or not path:
            return
        
        if not path.endswith('/'):
            path += '/'
        
        print("Выберите способ удаления:")
        print("  1) По имени файла")
        print("  2) По MD5 сумме")
        print("  0) Отмена")
        
        method = input("Введите номер (0-2): ")
        if method == '0' or not method:
            return
        
        if method == '1':
            filename = input("Введите имя файла для удаления: ")
            if not filename:
                return
            full_path = f"{path}{filename}"
            confirm = input(f"Удалить '{full_path}'? (y/n): ")
            if confirm.lower() == 'y':
                self.run_ansible(f"-m file -a \"path='{full_path}' state=absent\" --become")
        
        elif method == '2':
            md5 = input("Введите MD5 сумму файла: ")
            if not md5:
                return
            self.run_ansible(f"-m shell -a \"find '{path}' -type f -exec md5sum {{}} \\; | grep '^{md5} ' | head -1 | awk '{{print $2}}' | xargs rm -f\" --become")
        
        else:
            print("[ERROR] Неверный выбор!")
    
    #==================================================================
    # function view_config()
    #==================================================================
    def view_config(self):
        """Просмотр конфига"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ПРОСМОТР КОНФИГА /etc/sst-iiko/settings.ini")
        print("=" * 60)
        print("  1) Весь конфиг")
        print("  2) Конкретные параметры")
        print("  3) Изменить параметры")
        print("  0) Назад")
        print("=" * 60)
        
        choice = input("Введите номер (0-3): ")
        
        if choice == '1':
            self.run_ansible("-m shell -a \"cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Файл не найден'\" --become")
        elif choice == '2':
            params = input("Введите параметры через пробел: ")
            if params:
                pattern = '|'.join(params.split())
                self.run_ansible(f"-m shell -a \"grep -E '^({pattern})=' /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Параметры не найдены'\" --become")
        elif choice == '3':
            self.edit_config()
    
    #==================================================================
    # function edit_config()
    #==================================================================
    def edit_config(self):
        """Изменение параметров в конфиге"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ИЗМЕНЕНИЕ ПАРАМЕТРОВ КОНФИГА")
        print("=" * 60)
        print("Введите параметр и новое значение")
        print("Пример: productDescriptionTypes=card, info")
        print("Пример: showFoodValues=Never")
        print("=" * 60)
        
        param_input = input("\nВведите параметр и значение (параметр=значение) или '0' для отмены: ")
        if param_input == '0' or not param_input:
            print("[CANCEL] Отменено")
            return
        
        if '=' not in param_input:
            print("[ERROR] Неверный формат! Используйте: параметр=значение")
            return
        
        param, value = param_input.split('=', 1)
        param = param.strip()
        value = value.strip()
        
        if not param or not value:
            print("[ERROR] Параметр и значение не могут быть пустыми!")
            return
        
        print("\n" + "=" * 60)
        print(f"Будет изменен параметр: {param}={value}")
        print("=" * 60)
        confirm = input("Продолжить? (y/N): ")
        if confirm.lower() != 'y':
            print("[CANCEL] Отменено")
            return
        
        cmd = f"grep -q '^{param}=' /etc/sst-iiko/settings.ini && sed -i 's/^{param}=.*/{param}={value}/' /etc/sst-iiko/settings.ini || echo '{param}={value}' >> /etc/sst-iiko/settings.ini && echo '[OK] {param}={value}'"
        
        self.run_ansible(f"-m shell -a \"{cmd}\" --become")
    
    #==================================================================
    # function restart_sst()
    #==================================================================
    def restart_sst(self):
        """Перезапуск SST"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ВНИМАНИЕ! Перезапуск SST!")
        print("=" * 60)
        print()
        
        confirm = input("Перезапустить SST на всех хостах группы? (y/N): ")
        if confirm.lower() != 'y':
            print("[CANCEL] Отменено")
            return
        
        print("\nПерезапуск SST...")
        print("-" * 60)
        
        # Перезапускаем активный сервис - используем однострочную команду
        cmd = "if systemctl status sst-iiko 2>/dev/null | grep -q 'Active: active'; then sudo systemctl restart sst-iiko && echo '[OK] sst-iiko restarted'; elif systemctl status xsst-iiko 2>/dev/null | grep -q 'Active: active'; then sudo systemctl restart xsst-iiko && echo '[OK] xsst-iiko restarted'; else echo '[WARN] No active SST service found'; fi"
        
        self.run_ansible(f"-m shell -a \"{cmd}\" --become")
    
    #==================================================================
    # function status_sst()
    #==================================================================
    def status_sst(self):
        """Статус SST - только важная информация"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        # Используем одинарные кавычки для внешней обертки
        cmd = 'echo "=== SST STATUS ===" && sst_status=$(systemctl status sst-iiko 2>/dev/null | grep -E "Active:" | sed "s/^.*Active: //") && xsst_status=$(systemctl status xsst-iiko 2>/dev/null | grep -E "Active:" | sed "s/^.*Active: //") && echo "    sst-iiko - $sst_status" && echo "    xsst-iiko - $xsst_status" && echo "" && echo "=== API INFO ===" && curl -sw "HTTP: %{http_code}\\n" localhost:10000 2>/dev/null | grep -E "Current state|Hardware|Fiscal|Network|Terminal|deviceName|Theme|Version|HTTP:" || echo "[ERROR] Port 10000 unavailable"'
        
        self.run_ansible(f"-m shell -a '{cmd}' --become")
    
    #==================================================================
    # function main_menu()
    #==================================================================
    def main_menu(self):
        """Главное меню"""
        while True:
            self.clear_screen()
            print("=" * 60)
            print("              УПРАВЛЕНИЕ КИОСКАМИ")
            print("=" * 60)
            print(f"  INI файл: {self.ini_file}")
            print(f"  Точка:    {self.target_host if self.target_host else 'не выбрана'}")
            if self.target_host:
                for g in self.flat_groups:
                    if g['name'] == self.target_host:
                        print(f"  Хостов:   {g['total_hosts']}")
                        break
            print("=" * 60)
            print("  1) Пинг хоста/группы")
            print("  2) Просмотр директории")
            print("  3) Копировать файлы")
            print("  4) Удалить файлы")
            print("  5) Просмотр/изменение конфига")
            print("  6) RESTART SST (ОСТОРОЖНО!)")
            print("  7) Статус SST")
            print("  8) Сменить точку")
            print("  0) Выход")
            print("=" * 60)
            
            choice = input("Введите номер (0-8): ")
            
            if choice == '0':
                print("Выход...")
                break
            elif choice == '1':
                self.ping()
            elif choice == '2':
                self.view_files()
            elif choice == '3':
                self.copy_files()
            elif choice == '4':
                self.delete_files()
            elif choice == '5':
                self.view_config()
            elif choice == '6':
                self.restart_sst()
            elif choice == '7':
                self.status_sst()
            elif choice == '8':
                self.select_host()
            else:
                print("[ERROR] Неверный выбор!")
            
            input("\nНажмите Enter для продолжения...")

def main():
    manager = KioskManager()
    
    # Очищаем экран при старте
    manager.clear_screen()
    
    print("=" * 60)
    print("              ЗАПУСК УПРАВЛЕНИЯ КИОСКАМИ")
    print("=" * 60)
    print()
    
    # Очищаем переменные окружения, мешающие SSH
    manager.cleanup_ssh_env()
    
    # Проверяем наличие inventory.ini
    if not os.path.exists("inventory.ini"):
        print("[ERROR] Файл inventory.ini не найден!")
        sys.exit(1)
    
    # Выбор хоста/группы
    if not manager.select_host():
        print("[ERROR] Не удалось выбрать точку!")
        sys.exit(1)
    
    # Запуск главного меню
    manager.main_menu()

if __name__ == '__main__':
    main()
