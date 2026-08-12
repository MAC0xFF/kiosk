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
        self.tree = {}
        self.host_details = {}
        
    def find_ini_files(self):
        """Находит все .ini файлы в текущей директории"""
        files = []
        for f in os.listdir('.'):
            if f.endswith('.ini') and os.path.isfile(f):
                files.append(f)
        return sorted(files)
    
    def parse_ini_file(self, filepath):
        """Парсит INI файл и строит дерево групп"""
        if not os.path.exists(filepath):
            print(f"❌ Файл {filepath} не найден!")
            return None, None
        
        groups = {}
        current_group = None
        children = defaultdict(list)
        hosts = defaultdict(list)
        is_parent = {}
        
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            
            # Ищем секцию
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
                    is_parent[current_group] = False
                    # Читаем хосты в группе
                    i += 1
                    while i < len(lines):
                        host_line = lines[i].strip()
                        if host_line.startswith('[') and host_line.endswith(']'):
                            break
                        if host_line and not host_line.startswith('#'):
                            # Извлекаем IP
                            ip_match = re.match(r'^(\d+\.\d+\.\d+\.\d+)', host_line)
                            if ip_match:
                                hosts[current_group].append(ip_match.group(1))
                        i += 1
                    continue
            i += 1
        
        # Определяем родительские группы
        for parent in children.keys():
            if parent in is_parent:
                is_parent[parent] = True
        
        # Строим дерево
        tree = {}
        for group in is_parent.keys():
            if is_parent[group]:
                continue
            # Находим корневую группу (у которой нет родителя)
            parent_found = False
            for parent, child_list in children.items():
                if group in child_list:
                    parent_found = True
                    break
            if not parent_found:
                # Это корневая группа
                tree[group] = self._build_subtree(group, children, hosts)
        
        return tree, hosts
    
    def _build_subtree(self, group, children, hosts):
        """Рекурсивно строит поддерево"""
        subtree = {}
        subtree['hosts'] = hosts.get(group, [])
        subtree['children'] = {}
        
        for child in children.get(group, []):
            subtree['children'][child] = self._build_subtree(child, children, hosts)
        
        return subtree
    
    def print_tree(self, tree, prefix='', is_last=True):
        """Выводит дерево с отступами"""
        lines = []
        items = list(tree.items())
        for i, (name, data) in enumerate(items):
            is_last_item = (i == len(items) - 1)
            
            # Определяем иконку
            if data['children']:
                icon = '📁'
                if data['hosts']:
                    icon = '📁'
            else:
                icon = '📄'
            
            # Выводим строку
            if i == len(items) - 1:
                line = f"{prefix}└── {icon} {name}"
                new_prefix = prefix + "    "
            else:
                line = f"{prefix}├── {icon} {name}"
                new_prefix = prefix + "│   "
            
            # Добавляем количество хостов
            if data['hosts']:
                line += f" ({len(data['hosts'])} хостов)"
            elif data['children']:
                total_hosts = self._count_hosts(data)
                if total_hosts > 0:
                    line += f" (всего {total_hosts} хостов)"
            
            lines.append(line)
            
            # Рекурсивно выводим детей
            if data['children']:
                lines.extend(self.print_tree(data['children'], new_prefix, is_last_item))
        
        return lines
    
    def _count_hosts(self, data):
        """Подсчитывает общее количество хостов в группе и подгруппах"""
        count = len(data.get('hosts', []))
        for child in data.get('children', {}).values():
            count += self._count_hosts(child)
        return count
    
    def get_flat_groups(self, tree, prefix=''):
        """Возвращает плоский список групп с путями"""
        groups = []
        for name, data in tree.items():
            path = f"{prefix}/{name}" if prefix else name
            groups.append({
                'name': name,
                'path': path,
                'hosts': data.get('hosts', []),
                'children': list(data.get('children', {}).keys())
            })
            if data.get('children'):
                groups.extend(self.get_flat_groups(data['children'], path))
        return groups
    
    def select_ini_file(self):
        """Выбор INI файла"""
        files = self.find_ini_files()
        
        if not files:
            print("❌ Нет .ini файлов в текущей директории!")
            return False
        
        print("=" * 60)
        print("                   ВЫБЕРИ INI ФАЙЛ")
        print("=" * 60)
        
        for i, f in enumerate(files, 1):
            print(f"  {i:2}) {f}")
        
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
                print("❌ Неверный выбор!")
                return False
        except ValueError:
            print("❌ Введите число!")
            return False
    
    def select_host(self):
        """Выбор хоста/группы с древовидной структурой"""
        if not self.ini_file:
            print("❌ INI файл не выбран!")
            return False
        
        tree, hosts = self.parse_ini_file(self.ini_file)
        if not tree:
            print("❌ Не удалось разобрать INI файл!")
            return False
        
        # Выводим дерево
        print("=" * 60)
        print("              ВЫБЕРИ ХОСТ ИЛИ ГРУППУ")
        print("=" * 60)
        print(f"  INI файл: {self.ini_file}")
        print("=" * 60)
        print("📊 ДЕРЕВО ГРУПП:")
        print("-" * 60)
        
        tree_lines = self.print_tree(tree)
        for line in tree_lines:
            print(line)
        
        print("-" * 60)
        print("  0) Выход")
        print("  F) Выбрать другой INI файл")
        print("=" * 60)
        
        # Получаем плоский список групп
        flat_groups = self.get_flat_groups(tree)
        
        # Показываем нумерованный список
        print("\n📋 ДОСТУПНЫЕ ГРУППЫ ДЛЯ ВЫБОРА:")
        print("-" * 60)
        
        for i, g in enumerate(flat_groups, 1):
            host_count = len(g['hosts'])
            child_count = len(g['children'])
            icon = "📁" if child_count > 0 else "📄"
            print(f"  {i:3}) {icon} {g['path']} ({host_count} хостов)")
        
        print("-" * 60)
        print("  0) Выход")
        print("  F) Выбрать другой INI файл")
        print("=" * 60)
        
        try:
            choice = input("Введите номер (1-{}, 0-выход, F-сменить INI): ".format(len(flat_groups)))
            
            if choice.upper() == 'F':
                return self.select_ini_file() and self.select_host()
            
            if not choice:
                return False
            
            choice = int(choice)
            if choice == 0:
                sys.exit(0)
            elif 1 <= choice <= len(flat_groups):
                selected = flat_groups[choice - 1]
                self.target_host = selected['name']
                print(f"✅ Выбрана группа: {selected['path']}")
                print(f"   Хостов: {len(selected['hosts'])}")
                return True
            else:
                print("❌ Неверный выбор!")
                return False
        except ValueError:
            print("❌ Введите число или F!")
            return False
    
    def run_ansible(self, args):
        """Запускает ansible с аргументами"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        cmd = f"ansible -i {self.ini_file} {self.target_host} {args}"
        print(f"▶️ {cmd}")
        os.system(cmd)
    
    def ping(self):
        """Пинг хостов"""
        self.run_ansible("-m ping")
    
    def view_files(self):
        """Просмотр директории"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        print("=" * 60)
        print("📂 Просмотр директории")
        print("=" * 60)
        print("Пример: /etc/sst-iiko/  /opt/sst-iiko/img/")
        print("=" * 60)
        
        path = input("Введите путь (или '0' для отмены): ")
        if path == '0' or not path:
            return
        
        if not path.endswith('/'):
            path += '/'
        
        self.run_ansible(f"-m shell -a \"ls -lth {path} 2>/dev/null || echo '❌ Директория не найдена'\" --become")
    
    def copy_files(self):
        """Копирование файлов"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        print("=" * 60)
        print("📁 ФАЙЛЫ В ~/WORK/FILES/:")
        print("=" * 60)
        os.system("ls -lth ~/WORK/FILES/ 2>/dev/null || echo '❌ ~/WORK/FILES/ не существует'")
        print("=" * 60)
        
        filename = input("Введите имя файла для копирования (или '0' для отмены): ")
        if filename == '0' or not filename:
            return
        
        source = f"$HOME/WORK/FILES/{filename}"
        if not os.path.exists(os.path.expanduser(f"~/WORK/FILES/{filename}")):
            print(f"❌ {source} не найден!")
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
            print("❌ Не выбрана точка!")
            return
        
        print("=" * 60)
        print("🗑️ УДАЛЕНИЕ ФАЙЛОВ")
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
            print("❌ Неверный выбор!")
    
    def view_config(self):
        """Просмотр конфига"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        print("=" * 60)
        print("📄 ПРОСМОТР КОНФИГА /etc/sst-iiko/settings.ini")
        print("=" * 60)
        print("  1) Весь конфиг")
        print("  2) Конкретные параметры")
        print("  0) Назад")
        print("=" * 60)
        
        choice = input("Введите номер (0-2): ")
        
        if choice == '1':
            self.run_ansible("-m shell -a \"cat /etc/sst-iiko/settings.ini 2>/dev/null || echo '❌ Файл не найден'\" --become")
        elif choice == '2':
            params = input("Введите параметры через пробел: ")
            if params:
                pattern = '|'.join(params.split())
                self.run_ansible(f"-m shell -a \"grep -E '^({pattern})=' /etc/sst-iiko/settings.ini 2>/dev/null || echo '❌ Параметры не найдены'\" --become")
    
    def restart_sst(self):
        """Перезапуск SST"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        print("=" * 60)
        print("\033[1;33m⚠️ ВНИМАНИЕ! Перезапуск SST!\033[0m")
        print("=" * 60)
        
        confirm = input("Вы уверены? (y/N): ")
        if confirm.lower() != 'y':
            print("❌ Отменено")
            return
        
        self.run_ansible("-m shell -a \"\nif systemctl is-enabled sst-iiko 2>/dev/null | grep -q enabled; then\n    sudo systemctl restart sst-iiko\n    echo '✅ sst-iiko перезапущен'\nelif systemctl is-enabled xsst-iiko 2>/dev/null | grep -q enabled; then\n    sudo systemctl restart xsst-iiko\n    echo '✅ xsst-iiko перезапущен'\nelse\n    echo '❌ Сервис SST не найден'\nfi\" --become")
    
    def status_sst(self):
        """Статус SST"""
        if not self.ini_file or not self.target_host:
            print("❌ Не выбрана точка!")
            return
        
        self.run_ansible("-m shell -a \"\necho '--- Статус сервисов ---'\nsystemctl status sst-iiko xsst-iiko 2>/dev/null | grep -E 'Loaded|Active|Main PID' || echo '❌ Сервисы не найдены'\necho ''\necho '--- Проверка порта 10000 ---'\ncurl -s -o /dev/null -w 'HTTP Code: %{http_code}\\n' localhost:10000 2>/dev/null || echo '❌ Порт 10000 недоступен'\" --become")
    
    def main_menu(self):
        """Главное меню"""
        while True:
            os.system('clear')
            print("=" * 60)
            print("              🖥️ УПРАВЛЕНИЕ КИОСКАМИ")
            print("=" * 60)
            print(f"  INI файл: {self.ini_file if self.ini_file else 'не выбран'}")
            print(f"  Точка:    {self.target_host if self.target_host else 'не выбрана'}")
            print("=" * 60)
            print("  1) Пинг хоста/группы")
            print("  2) Просмотр директории")
            print("  3) Копировать файлы")
            print("  4) Удалить файлы")
            print("  5) Просмотр конфига")
            print("  6) 🔄 RESTART SST (ОСТОРОЖНО!)")
            print("  7) 📊 Статус SST")
            print("  8) 🔄 Сменить точку")
            print("  I) 🔄 Сменить INI файл")
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
                print("❌ Неверный выбор!")
            
            input("\nНажмите Enter для продолжения...")

def main():
    manager = KioskManager()
    
    # Выбор INI файла
    if not manager.select_ini_file():
        print("❌ Не удалось выбрать INI файл!")
        sys.exit(1)
    
    # Выбор хоста/группы
    if not manager.select_host():
        print("❌ Не удалось выбрать точку!")
        sys.exit(1)
    
    # Запуск главного меню
    manager.main_menu()

if __name__ == '__main__':
    main()
