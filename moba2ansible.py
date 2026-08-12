#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import subprocess
import re
from collections import defaultdict

class KioskManager:
    def __init__(self):
        self.ini_file = None
        self.target_host = None
        self.groups = []
        self.group_hosts = {}
        self.tree = {}
        self.flat_groups = []
        
    def find_ini_files(self):
        """Находит все .ini файлы в текущей директории"""
        files = []
        for f in os.listdir('.'):
            if f.endswith('.ini') and os.path.isfile(f):
                files.append(f)
        return sorted(files)
    
    def parse_ini_with_hierarchy(self, filepath):
        """Парсит INI файл с сохранением иерархии"""
        if not os.path.exists(filepath):
            print(f"[ERROR] Файл {filepath} не найден!")
            return None
        
        groups = {}
        children = defaultdict(list)
        current_group = None
        is_parent = {}
        
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
                            ip_match = re.match(r'^(\d+\.\d+\.\d+\.\d+)', host_line)
                            if ip_match:
                                ip = ip_match.group(1)
                                if ip not in groups[current_group]:
                                    groups[current_group].append(ip)
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
            # Находим корневые группы (у которых нет родителей)
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
            
            # Считаем общее количество хостов в поддереве
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
    
    def select_ini_file(self):
        """Выбор INI файла"""
        files = self.find_ini_files()
        
        if not files:
            print("[ERROR] Нет .ini файлов в текущей директории!")
            return False
        
        print("=" * 60)
        print("                   ВЫБЕРИ INI ФАЙЛ")
        print("=" * 60)
        
        for i, f in enumerate(files, 1):
            tree, groups = self.parse_ini_with_hierarchy(f)
            if tree:
                total_hosts = sum(len(h) for h in groups.values()) if groups else 0
                group_count = len(groups) if groups else 0
                print(f"  {i:2}) {f:<30} (групп: {group_count:3}, хостов: {total_hosts:4})")
            else:
                print(f"  {i:2}) {f:<30} (ошибка парсинга)")
        
        print("=" * 60)
        print("  0) Выход")
        print("=" * 60)
        
        try:
            choice = input("Введите номер (0-{}): ".format(len(files)))
            if not choice:
                return False
            
            choice = int(choice)
            if choice == 0:
                sys.exit(0)
            elif 1 <= choice <= len(files):
                self.ini_file = files[choice - 1]
                return True
            else:
                print("[ERROR] Неверный выбор!")
                return False
        except ValueError:
            print("[ERROR] Введите число!")
            return False
    
    def print_tree(self, tree, prefix='', is_last=True):
        """Выводит дерево с отступами"""
        lines = []
        items = list(tree.items())
        for i, (name, data) in enumerate(items):
            is_last_item = (i == len(items) - 1)
            
            # Определяем тип
            host_count = len(data.get('hosts', []))
            child_count = len(data.get('children', {}))
            total_hosts = self._count_hosts(data)
            
            if child_count > 0:
                icon = '[DIR]'
            else:
                icon = '[HOST]'
            
            # Формируем строку
            if is_last_item:
                line = f"{prefix}└── {icon} {name}"
                new_prefix = prefix + "    "
            else:
                line = f"{prefix}├── {icon} {name}"
                new_prefix = prefix + "│   "
            
            # Добавляем информацию о хостах
            if host_count > 0:
                line += f" ({host_count} hosts)"
            elif child_count > 0 and total_hosts > 0:
                line += f" (total {total_hosts} hosts)"
            
            lines.append(line)
            
            # Рекурсивно выводим детей
            if data.get('children'):
                lines.extend(self.print_tree(data['children'], new_prefix, is_last_item))
        
        return lines
    
    def select_host(self):
        """Выбор хоста/группы с иерархическим отображением"""
        if not self.ini_file:
            print("[ERROR] INI файл не выбран!")
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
        print("GROUP HIERARCHY:")
        print("-" * 60)
        
        # Выводим дерево
        tree_lines = self.print_tree(tree)
        for line in tree_lines:
            print(line)
        
        print("-" * 60)
        print("  0) Выход")
        print("  F) Выбрать другой INI файл")
        print("=" * 60)
        
        # Показываем нумерованный список всех групп
        print("\nAVAILABLE GROUPS:")
        print("-" * 60)
        
        # Сортируем по пути для сохранения иерархии
        sorted_groups = sorted(self.flat_groups, key=lambda x: x['path'])
        
        for i, g in enumerate(sorted_groups, 1):
            indent = "  " * (g['path'].count('/'))
            icon = "[DIR]" if g['child_count'] > 0 else "[HOST]"
            print(f"{indent}{i:3}) {icon} {g['name']} ({g['total_hosts']} hosts)")
        
        print("-" * 60)
        print("  0) Выход")
        print("  F) Выбрать другой INI файл")
        print("=" * 60)
        
        try:
            choice = input("Введите номер (1-{}, 0-выход, F-сменить INI): ".format(len(sorted_groups)))
            
            if choice.upper() == 'F':
                if self.select_ini_file():
                    return self.select_host()
                return False
            
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
            print("[ERROR] Введите число или F!")
            return False
    
    def cleanup_ssh_env(self):
        """Очищает переменные окружения, мешающие SSH"""
        # Удаляем переменные, которые могут указывать на несуществующий конфиг
        problematic_vars = ['ANSIBLE_SSH_ARGS', 'GIT_SSH_COMMAND', 'SSH_CONFIG']
        for var in problematic_vars:
            if var in os.environ:
                print(f"[INFO] Удаляем переменную {var}={os.environ[var]}")
                del os.environ[var]
        
        # Также проверяем ~/.ssh/config на наличие ссылки на config_mobaxterm
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
                    # Создаем новый пустой конфиг
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
        
        # Формируем команду
        cmd = f"ansible -i {self.ini_file} {self.target_host} {args}"
        
        print(f"\n[RUN] Выполняю: {cmd}")
        print("-" * 60)
        os.system(cmd)
        print("-" * 60)
    
    def ping(self):
        """Пинг хостов"""
        self.run_ansible("-m ping")
    
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
        print("  0) Назад")
        print("=" * 60)
        
        choice = input("Введите номер (0-2): ")
        
        if choice == '1':
            self.run_ansible("-m shell -a \"cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Файл не найден'\" --become")
        elif choice == '2':
            params = input("Введите параметры через пробел: ")
            if params:
                pattern = '|'.join(params.split())
                self.run_ansible(f"-m shell -a \"grep -E '^({pattern})=' /etc/sst-iiko/settings.ini 2>/dev/null || echo '[ERROR] Параметры не найдены'\" --become")
    
    def restart_sst(self):
        """Перезапуск SST"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        print("=" * 60)
        print("ВНИМАНИЕ! Перезапуск SST!")
        print("=" * 60)
        
        confirm = input("Вы уверены? (y/N): ")
        if confirm.lower() != 'y':
            print("[CANCEL] Отменено")
            return
        
        self.run_ansible("-m shell -a \"\nif systemctl is-enabled sst-iiko 2>/dev/null | grep -q enabled; then\n    sudo systemctl restart sst-iiko\n    echo '[OK] sst-iiko перезапущен'\nelif systemctl is-enabled xsst-iiko 2>/dev/null | grep -q enabled; then\n    sudo systemctl restart xsst-iiko\n    echo '[OK] xsst-iiko перезапущен'\nelse\n    echo '[ERROR] Сервис SST не найден'\nfi\" --become")
    
    def status_sst(self):
        """Статус SST"""
        if not self.ini_file or not self.target_host:
            print("[ERROR] Не выбрана точка!")
            return
        
        self.run_ansible("-m shell -a \"\necho '--- Статус сервисов ---'\nsystemctl status sst-iiko xsst-iiko 2>/dev/null | grep -E 'Loaded|Active|Main PID' || echo '[ERROR] Сервисы не найдены'\necho ''\necho '--- Проверка порта 10000 ---'\ncurl -s -o /dev/null -w 'HTTP Code: %{http_code}\\n' localhost:10000 2>/dev/null || echo '[ERROR] Порт 10000 недоступен'\" --become")
    
    def main_menu(self):
        """Главное меню"""
        while True:
            os.system('clear')
            print("=" * 60)
            print("              УПРАВЛЕНИЕ КИОСКАМИ")
            print("=" * 60)
            print(f"  INI файл: {self.ini_file if self.ini_file else 'не выбран'}")
            print(f"  Точка:    {self.target_host if self.target_host else 'не выбрана'}")
            if self.target_host:
                # Показываем количество хостов в выбранной группе
                for g in self.flat_groups:
                    if g['name'] == self.target_host:
                        print(f"  Хостов:   {g['total_hosts']}")
                        break
            print("=" * 60)
            print("  1) Пинг хоста/группы")
            print("  2) Просмотр директории")
            print("  3) Копировать файлы")
            print("  4) Удалить файлы")
            print("  5) Просмотр конфига")
            print("  6) RESTART SST (ОСТОРОЖНО!)")
            print("  7) Статус SST")
            print("  8) Сменить точку")
            print("  I) Сменить INI файл")
            print("  0) Выход")
            print("=" * 60)
            
            choice = input("Введите номер (0-8, I): ")
            
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
            elif choice.upper() == 'I':
                if self.select_ini_file():
                    self.select_host()
            else:
                print("[ERROR] Неверный выбор!")
            
            input("\nНажмите Enter для продолжения...")

def main():
    manager = KioskManager()
    
    # Очищаем переменные окружения, мешающие SSH
    manager.cleanup_ssh_env()
    
    # Выбор INI файла
    if not manager.select_ini_file():
        print("[ERROR] Не удалось выбрать INI файл!")
        sys.exit(1)
    
    # Выбор хоста/группы
    if not manager.select_host():
        print("[ERROR] Не удалось выбрать точку!")
        sys.exit(1)
    
    # Запуск главного меню
    manager.main_menu()

if __name__ == '__main__':
    main()
