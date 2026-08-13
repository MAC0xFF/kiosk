#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import subprocess
import tempfile
import urllib.request
import urllib.error
from typing import Optional, Dict, Any

class IikoAPIClient:
    """Клиент для работы с API IIKO"""
    
    def __init__(self):
        self.token: Optional[str] = None
        self.api_key: Optional[str] = None
        self.org_id: Optional[str] = None
        self.terminal_group: Optional[str] = None
        self.external_menu_id: Optional[str] = None
        
        # Данные приложения (из оригинального скрипта)
        self.app_id = "18ae92b1-3810-4cdb-beea-33a701152759"
        self.client_secret = "sWTLs5NBeIh-G99-P-XZbR1jmr-Gw-DAZNfIjvLKVXk="
        
        # Базовый URL API
        self.base_url = "https://api-ru.iiko.services"
    
    def _print_status(self, message: str, status: str = "info"):
        """Вывод сообщений с цветом"""
        colors = {
            "info": "\033[1;34m",    # BLUE
            "success": "\033[0;32m",  # GREEN
            "error": "\033[0;31m",    # RED
            "warning": "\033[1;33m",  # YELLOW
            "highlight": "\033[1;34m" # BLUE
        }
        reset = "\033[0m"
        print(f"{colors.get(status, '')}{message}{reset}")
    
    def _make_request(self, method: str, endpoint: str, data: Optional[Dict] = None, 
                     requires_auth: bool = True) -> Optional[Dict]:
        """Выполнение HTTP запроса к API используя urllib"""
        url = f"{self.base_url}{endpoint}"
        
        if requires_auth:
            if not self.token:
                self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
                return None
        
        try:
            # Подготовка данных
            if data:
                json_data = json.dumps(data).encode('utf-8')
            else:
                json_data = None
            
            # Создание запроса
            req = urllib.request.Request(url, data=json_data, method=method)
            req.add_header('Content-Type', 'application/json')
            
            if requires_auth:
                req.add_header('Authorization', f'Bearer {self.token}')
            
            # Выполнение запроса
            with urllib.request.urlopen(req) as response:
                response_data = response.read().decode('utf-8')
                return json.loads(response_data)
                
        except urllib.error.HTTPError as e:
            self._print_status(f"HTTP ошибка: {e.code} - {e.reason}", "error")
            return None
        except urllib.error.URLError as e:
            self._print_status(f"Ошибка соединения: {e.reason}", "error")
            return None
        except json.JSONDecodeError as e:
            self._print_status(f"Ошибка парсинга JSON: {e}", "error")
            return None
        except Exception as e:
            self._print_status(f"Ошибка запроса: {e}", "error")
            return None
    
    def _get_org_id(self) -> bool:
        """Получение ID организации от пользователя"""
        if self.org_id:
            self._print_status(f"Текущий ID организации: {self.org_id}", "highlight")
            choice = input("Нажмите Enter чтобы использовать текущий, или введите новый ID: ").strip()
            if choice:
                self.org_id = choice
        else:
            self.org_id = input("Введите ID организации: ").strip()
            if not self.org_id:
                self._print_status("ID организации не может быть пустым!", "error")
                return False
        return True
    
    def get_token(self):
        """Получение токена авторизации"""
        self._print_status("=== Получение токена авторизации ===", "warning")
        
        if not self.api_key:
            self.api_key = input("Введите ваш API ключ: ").strip()
            if not self.api_key:
                self._print_status("API ключ не может быть пустым!", "error")
                return
        
        data = {
            "appId": self.app_id,
            "clientSecret": self.client_secret,
            "apiLogin": self.api_key
        }
        
        response = self._make_request("POST", "/api/v2/access_token", data, requires_auth=False)
        
        if response and "token" in response:
            self.token = response["token"]
            self._print_status("Токен успешно получен!", "success")
            self._print_status(f"Токен: {self.token}", "highlight")
        else:
            self._print_status("Ошибка получения токена!", "error")
            self.token = None
    
    def get_organizations(self):
        """Получение списка организаций"""
        self._print_status("=== Получение списка организаций ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        data = {"returnAdditionalInfo": True, "includeDisabled": True}
        response = self._make_request("GET", "/api/1/organizations", data)
        
        if not response or "organizations" not in response:
            self._print_status("Ошибка получения списка организаций", "error")
            return
        
        # Формируем вывод
        temp_file = tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.txt', encoding='utf-8')
        for org in response["organizations"]:
            temp_file.write(f"ID: {org['id']}\nНазвание: {org['name']}\n---\n")
        temp_file.close()
        
        # Спрашиваем как просмотреть
        self._print_status("Как вы хотите просмотреть организации?", "warning")
        print("1) Просмотреть в терминале (сразу весь список)")
        print("2) Просмотреть через less (с поиском)")
        
        choice = input("Выберите вариант (1 или 2): ").strip()
        
        if choice == "2":
            self._print_status("Открываю less... Используйте / для поиска, q для выхода", "success")
            subprocess.run(["less", temp_file.name])
        else:
            self._print_status("=== Список организаций ===", "success")
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                print(f.read())
        
        # Запрашиваем ID организации
        org_id = input("\nВведите ID организации из списка (или Enter чтобы пропустить): ").strip()
        if org_id:
            self.org_id = org_id
            self._print_status(f"ID организации установлен: {self.org_id}", "success")
        
        # Удаляем временный файл
        os.unlink(temp_file.name)
    
    def get_terminal_groups(self):
        """Получение групп терминалов"""
        self._print_status("=== Получение групп терминалов ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        data = {"organizationIds": [self.org_id], "includeDisabled": False}
        response = self._make_request("POST", "/api/1/terminal_groups", data)
        
        if response:
            # Формируем красивый вывод
            result = {}
            if "terminalGroups" in response:
                result["terminalGroups"] = [
                    {"id": item["id"], "name": item["name"]} 
                    for item in response["terminalGroups"][0]["items"]
                ]
            if "terminalGroupsInSleep" in response:
                result["terminalGroupsInSleep"] = [
                    {"id": item["id"], "name": item["name"]} 
                    for item in response["terminalGroupsInSleep"][0]["items"]
                ]
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения групп терминалов", "error")
    
    def get_payment_types(self):
        """Получение типов оплаты"""
        self._print_status("=== Получение типов оплаты ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        data = {"organizationIds": [self.org_id]}
        response = self._make_request("POST", "/api/1/payment_types", data)
        
        if response and "paymentTypes" in response:
            result = []
            for pt in response["paymentTypes"]:
                if "terminalGroups" in pt:
                    del pt["terminalGroups"]
                result.append({
                    "id": pt.get("id"),
                    "name": pt.get("name"),
                    "applicableMarketingCampaigns": pt.get("applicableMarketingCampaigns"),
                    "paymentTypeKind": pt.get("paymentTypeKind")
                })
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения типов оплаты", "error")
    
    def get_customer_info(self):
        """Получение информации о клиенте"""
        self._print_status("=== Получение информации о клиенте ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        phone = input("Введите номер телефона (формат +79103972345): ").strip()
        if not phone:
            self._print_status("Номер телефона не может быть пустым!", "error")
            return
        
        data = {"phone": phone, "type": "phone", "organizationId": self.org_id}
        response = self._make_request("POST", "/api/1/loyalty/iiko/customer/info", data)
        
        if response:
            print(json.dumps(response, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения информации о клиенте", "error")
    
    def get_nomenclature(self):
        """Получение номенклатуры"""
        self._print_status("=== Получение номенклатуры ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        self._print_status("Получение номенклатуры...", "info")
        data = {"organizationId": self.org_id}
        response = self._make_request("POST", "/api/1/nomenclature", data)
        
        if response:
            filename = os.path.expanduser("~/nomenclature.txt")
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(response, f, indent=2, ensure_ascii=False)
            self._print_status(f"Номенклатура сохранена в {filename}", "success")
            
            choice = input("Хотите просмотреть файл через less? (y/n): ").strip().lower()
            if choice == 'y':
                subprocess.run(["less", filename])
        else:
            self._print_status("Ошибка получения номенклатуры", "error")
    
    def get_external_menus(self):
        """Получение внешнего ID меню Iiko Web"""
        self._print_status("=== Получение внешнего ID меню Iiko Web ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        response = self._make_request("POST", "/api/2/menu", {})
        
        if response:
            print(json.dumps(response, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения внешнего ID меню", "error")
    
    def get_menu_by_id(self):
        """Получение меню по внешнему ID"""
        self._print_status("=== Получение меню по внешнему ID ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        menu_id = input("Введите внешний ID меню: ").strip()
        if not menu_id:
            self._print_status("ID меню не может быть пустым!", "error")
            return
        
        self._print_status("Получение меню...", "info")
        data = {"organizationIds": [self.org_id], "externalMenuId": menu_id}
        response = self._make_request("POST", "/api/2/menu/by_id", data)
        
        if response:
            filename = os.path.expanduser("~/menu.txt")
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(response, f, indent=2, ensure_ascii=False)
            self._print_status(f"Меню сохранено в {filename}", "success")
            
            choice = input("Хотите просмотреть файл через less? (y/n): ").strip().lower()
            if choice == 'y':
                subprocess.run(["less", filename])
        else:
            self._print_status("Ошибка получения меню", "error")
    
    def reset_org_id(self):
        """Сброс ID организации"""
        self.org_id = None
        self._print_status("ID организации сброшен", "success")
    
    def show_status(self):
        """Отображение текущего статуса"""
        self._print_status("=== Текущий статус ===", "warning")
        
        if not self.token:
            self._print_status("Токен: не получен", "error")
        else:
            self._print_status("Токен: получен", "success")
        
        if self.api_key:
            self._print_status(f"API ключ: {self.api_key}", "highlight")
        
        if not self.org_id:
            self._print_status("ID организации: не установлен", "error")
        else:
            self._print_status(f"ID организации: {self.org_id}", "highlight")
        
        if not self.terminal_group:
            self._print_status("Группа терминалов: не установлена", "error")
        else:
            self._print_status(f"Группа терминалов: {self.terminal_group}", "highlight")
        
        if not self.external_menu_id:
            self._print_status("Внешний ID меню Iiko Web: не установлен", "error")
        else:
            self._print_status(f"Внешний ID меню Iiko Web: {self.external_menu_id}", "highlight")
    
    def clear_screen(self):
        """Очистка экрана"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def show_menu(self):
        """Отображение главного меню"""
        self.clear_screen()
        self._print_status("========================================", "success")
        self._print_status("         IIKO API TOOL v1.0            ", "success")
        self._print_status("========================================", "success")
        print("")
        self.show_status()
        print("")
        self._print_status("Доступные операции:", "warning")
        print("1) Получить токен авторизации")
        print("2) Получить список организаций")
        print("3) Получить группы терминалов")
        print("4) Получить типы оплаты")
        print("5) Получить информацию о клиенте")
        print("6) Получить номенклатуру (сохраняется в файл)")
        print("7) Получить внешний ID меню Iiko Web")
        print("8) Получить меню по внешнему ID (сохраняется в файл)")
        print("9) Сбросить ID организации")
        print("10) Показать статус")
        print("0) Выход")
        print("")
        self._print_status("========================================", "success")
        print("")
    
    def run(self):
        """Запуск основного цикла программы"""
        while True:
            self.show_menu()
            choice = input("Выберите операцию (0-10): ").strip()
            
            actions = {
                '1': self.get_token,
                '2': self.get_organizations,
                '3': self.get_terminal_groups,
                '4': self.get_payment_types,
                '5': self.get_customer_info,
                '6': self.get_nomenclature,
                '7': self.get_external_menus,
                '8': self.get_menu_by_id,
                '9': self.reset_org_id,
                '10': self.show_status,
                '0': lambda: None,
                'q': lambda: None,
                'Q': lambda: None
            }
            
            if choice in actions:
                if choice in ['0', 'q', 'Q']:
                    self._print_status("До свидания!", "success")
                    break
                actions[choice]()
            else:
                self._print_status("Неверный выбор! Пожалуйста, выберите 0-10", "error")
            
            print("")
            input("Нажмите Enter чтобы продолжить...")


if __name__ == "__main__":
    try:
        client = IikoAPIClient()
        client.run()
    except KeyboardInterrupt:
        print("\n\nДо свидания!")
    except Exception as e:
        print(f"Критическая ошибка: {e}")
