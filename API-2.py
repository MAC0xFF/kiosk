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
        self.terminal_group_id: Optional[str] = None
        self.external_menu_id: Optional[str] = None
        self.pay_program_id: Optional[str] = None
        self.payment_type_id: Optional[str] = None
        self.wallet_id: Optional[str] = None
        
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
            error_msg = f"HTTP ошибка: {e.code} - {e.reason}"
            if e.code == 401:
                error_msg += " (Неверный API ключ или токен истек)"
                # Сбрасываем токен при ошибке авторизации
                self.token = None
            self._print_status(error_msg, "error")
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
        self._print_status("=== Получение токена авторизации по TransportApiKey ===", "warning")
        
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
            # Предлагаем ввести API ключ заново
            retry = input("Хотите ввести API ключ заново? (y/n): ").strip().lower()
            if retry == 'y':
                self.api_key = None
                self.get_token()
    
    def get_organizations(self):
        """Получение списка организаций"""
        self._print_status("=== Получение TransportOrganizationId ===", "warning")
        
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
            self._print_status(f"TransportOrganizationId установлен: {self.org_id}", "success")
        
        # Удаляем временный файл
        os.unlink(temp_file.name)
    
    def get_terminal_groups(self):
        """Получение групп терминалов"""
        self._print_status("=== Получение TerminalGroupID ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        data = {"organizationIds": [self.org_id], "includeDisabled": False}
        response = self._make_request("POST", "/api/1/terminal_groups", data)
        
        if response:
            try:
                # Проверяем структуру ответа
                terminal_groups = []
                
                if "terminalGroups" in response and response["terminalGroups"]:
                    for group in response["terminalGroups"]:
                        if "items" in group:
                            for item in group["items"]:
                                terminal_groups.append({
                                    "id": item.get("id"),
                                    "name": item.get("name")
                                })
                
                if "terminalGroupsInSleep" in response and response["terminalGroupsInSleep"]:
                    for group in response["terminalGroupsInSleep"]:
                        if "items" in group:
                            for item in group["items"]:
                                terminal_groups.append({
                                    "id": item.get("id"),
                                    "name": item.get("name")
                                })
                
                if terminal_groups:
                    # Выводим классический JSON
                    print(json.dumps(terminal_groups, indent=2, ensure_ascii=False))
                    print("")
                    
                    # Предлагаем ввести ID напрямую
                    tg_id = input("Введите ID группы терминалов: ").strip()
                    if tg_id:
                        # Проверяем, есть ли такой ID в списке
                        found = False
                        for tg in terminal_groups:
                            if tg["id"] == tg_id:
                                self.terminal_group_id = tg_id
                                self._print_status(f"TerminalGroupID установлен: {self.terminal_group_id}", "success")
                                found = True
                                break
                        if not found:
                            self._print_status("ID не найден в списке! TerminalGroupID не установлен.", "error")
                    else:
                        self._print_status("ID не введен! TerminalGroupID не установлен.", "error")
                else:
                    self._print_status("Группы терминалов не найдены", "warning")
                    
            except (KeyError, IndexError, TypeError) as e:
                self._print_status(f"Ошибка обработки ответа: {e}", "error")
                print("Ответ API:", json.dumps(response, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения групп терминалов", "error")
    
    def get_payment_types_and_programs(self):
        """Получение типов оплаты и программ лояльности"""
        self._print_status("=== Получение PayProgramId и PaymentTypeId ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        data = {"organizationIds": [self.org_id]}
        response = self._make_request("POST", "/api/1/payment_types", data)
        
        if response and "paymentTypes" in response:
            # Выводим полный ответ в JSON
            print(json.dumps(response["paymentTypes"], indent=2, ensure_ascii=False))
            print("")
            
            # Показываем доступные ID для выбора
            print("Доступные ID для выбора:")
            for pt in response["paymentTypes"]:
                print(f"  ID: {pt.get('id')} - {pt.get('name')}")
            print("")
            
            # Предлагаем ввести ID для PaymentTypeId
            pt_id = input("Введите ID типа оплаты для PaymentTypeId (или Enter чтобы пропустить): ").strip()
            if pt_id:
                # Проверяем, есть ли такой ID в списке
                found = False
                for pt in response["paymentTypes"]:
                    if pt["id"] == pt_id:
                        self.payment_type_id = pt_id
                        self._print_status(f"PaymentTypeId установлен: {self.payment_type_id}", "success")
                        found = True
                        
                        # Дополнительно проверяем наличие программы лояльности
                        if "applicableMarketingCampaigns" in pt and pt["applicableMarketingCampaigns"]:
                            campaigns = pt["applicableMarketingCampaigns"]
                            if campaigns and len(campaigns) > 0:
                                # Берем первую программу лояльности
                                self.pay_program_id = campaigns[0].get("id")
                                self._print_status(f"PayProgramId автоматически установлен: {self.pay_program_id}", "success")
                        
                        break
                if not found:
                    self._print_status("ID не найден в списке! PaymentTypeId не установлен.", "error")
            else:
                self._print_status("ID не введен! PaymentTypeId не установлен.", "error")
        else:
            self._print_status("Ошибка получения типов оплаты", "error")
    
    def get_external_menus(self):
        """Получение внешнего ID меню Iiko Web"""
        self._print_status("=== Получение External ID IikoWeb menu ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        response = self._make_request("POST", "/api/2/menu", {})
        
        if response:
            # Пытаемся найти externalMenuId в ответе
            if isinstance(response, dict):
                if "externalMenuId" in response:
                    self.external_menu_id = response["externalMenuId"]
                    self._print_status(f"External ID IikoWeb menu получен: {self.external_menu_id}", "success")
                elif "externalMenuIds" in response and response["externalMenuIds"]:
                    self.external_menu_id = response["externalMenuIds"][0]
                    self._print_status(f"External ID IikoWeb menu получен: {self.external_menu_id}", "success")
                else:
                    print(json.dumps(response, indent=2, ensure_ascii=False))
                    # Предлагаем ввести вручную
                    menu_id = input("\nВведите External ID IikoWeb menu вручную: ").strip()
                    if menu_id:
                        self.external_menu_id = menu_id
                        self._print_status(f"External ID IikoWeb menu установлен: {self.external_menu_id}", "success")
            else:
                print(json.dumps(response, indent=2, ensure_ascii=False))
        else:
            self._print_status("Ошибка получения внешнего ID меню", "error")
    
    def get_menu_by_id(self):
        """Получение меню по внешнему ID"""
        self._print_status("=== Получение меню из IikoWeb по внешнему ID ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        if not self.external_menu_id:
            menu_id = input("Введите внешний ID меню: ").strip()
            if not menu_id:
                self._print_status("ID меню не может быть пустым!", "error")
                return
        else:
            self._print_status(f"Текущий External ID IikoWeb menu: {self.external_menu_id}", "highlight")
            menu_id = input("Нажмите Enter чтобы использовать текущий, или введите новый ID: ").strip()
            if not menu_id:
                menu_id = self.external_menu_id
        
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
    
    def get_nomenclature(self):
        """Получение номенклатуры из бэкофиса"""
        self._print_status("=== Получение номенклатуры из бэкофиса ===", "warning")
        
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
    
    def get_wallet_id(self):
        """Получение Wallet ID"""
        self._print_status("=== Получение WalletId ===", "warning")
        
        if not self.token:
            self._print_status("Ошибка: Токен не получен. Сначала получите токен.", "error")
            return
        
        if not self._get_org_id():
            return
        
        # Здесь должен быть реальный запрос для получения Wallet ID
        # Пока предлагаем ввести вручную
        wallet_id = input("Введите Wallet ID: ").strip()
        if wallet_id:
            self.wallet_id = wallet_id
            self._print_status(f"WalletId установлен: {self.wallet_id}", "success")
    
    def reset_org_id(self):
        """Сброс всех ID"""
        self.org_id = None
        self.terminal_group_id = None
        self.external_menu_id = None
        self.pay_program_id = None
        self.payment_type_id = None
        self.wallet_id = None
        self.token = None
        self.api_key = None
        self._print_status("Все ID и токен сброшены", "success")
    
    def show_status(self):
        """Отображение текущего статуса"""
        self._print_status("=== Текущий статус ===", "warning")
        
        # Token
        if not self.token:
            self._print_status("1) Token: не получен", "error")
        else:
            self._print_status(f"1) Token: получен", "success")
        
        # TransportApiKey
        if not self.api_key:
            self._print_status("1) TransportApiKey: не установлен", "error")
        else:
            self._print_status(f"1) TransportApiKey: {self.api_key}", "highlight")
        
        # TransportOrganizationId
        if not self.org_id:
            self._print_status("2) TransportOrganizationId: не установлен", "error")
        else:
            self._print_status(f"2) TransportOrganizationId: {self.org_id}", "highlight")
        
        # TerminalGroupID
        if not self.terminal_group_id:
            self._print_status("3) TerminalGroupID: не установлен", "error")
        else:
            self._print_status(f"3) TerminalGroupID: {self.terminal_group_id}", "highlight")
        
        # External ID IikoWeb menu
        if not self.external_menu_id:
            self._print_status("4) External ID IikoWeb menu: не установлен", "error")
        else:
            self._print_status(f"4) External ID IikoWeb menu: {self.external_menu_id}", "highlight")
        
        # PayProgramId
        if not self.pay_program_id:
            self._print_status("5) PayProgramId: не установлен", "error")
        else:
            self._print_status(f"5) PayProgramId: {self.pay_program_id}", "highlight")
        
        # PaymentTypeId
        if not self.payment_type_id:
            self._print_status("5) PaymentTypeId: не установлен", "error")
        else:
            self._print_status(f"5) PaymentTypeId: {self.payment_type_id}", "highlight")
        
        # WalletId
        if not self.wallet_id:
            self._print_status("6) WalletId: не установлен", "error")
        else:
            self._print_status(f"6) WalletId: {self.wallet_id}", "highlight")
    
    def clear_screen(self):
        """Очистка экрана"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def _format_status(self, value, default="не установлен"):
        """Форматирование статуса с цветом"""
        if value:
            return f"\033[0;32m{value}\033[0m"  # GREEN
        else:
            return f"\033[0;31m{default}\033[0m"  # RED
    
    def show_menu(self):
        """Отображение главного меню"""
        self.clear_screen()
        self._print_status("========================================", "success")
        self._print_status("         IIKO API TOOL v1.0            ", "success")
        self._print_status("========================================", "success")
        print("")
        self._print_status("Доступные операции:", "warning")
        print("")
        
        # Пункт 1 - Получить токен
        if self.token and self.api_key:
            print(f"1) Получить токен авторизации по TransportApiKey (\033[0;32mтокен получен, ApiKey: {self.api_key}\033[0m)")
        else:
            print(f"1) Получить токен авторизации по TransportApiKey (\033[0;31mтокен не получен\033[0m)")
        
        # Пункт 2 - TransportOrganizationId
        if self.org_id:
            print(f"2) Получить TransportOrganizationId (\033[0;32m{self.org_id}\033[0m)")
        else:
            print(f"2) Получить TransportOrganizationId (\033[0;31mне установлен\033[0m)")
        
        # Пункт 3 - TerminalGroupID
        if self.terminal_group_id:
            print(f"3) Получить TerminalGroupID (\033[0;32m{self.terminal_group_id}\033[0m)")
        else:
            print(f"3) Получить TerminalGroupID (\033[0;31mне установлен\033[0m)")
        
        # Пункт 4 - External ID IikoWeb menu
        if self.external_menu_id:
            print(f"4) Получить External ID IikoWeb menu (\033[0;32m{self.external_menu_id}\033[0m)")
        else:
            print(f"4) Получить External ID IikoWeb menu (\033[0;31mне установлен\033[0m)")
        
        # Пункт 5 - PayProgramId и PaymentTypeId
        print("5) Получить PayProgramId и PaymentTypeId")
        if self.pay_program_id:
            print(f"    (PayProgramId: \033[0;32m{self.pay_program_id}\033[0m)")
        else:
            print(f"    (PayProgramId: \033[0;31mне установлен\033[0m)")
        if self.payment_type_id:
            print(f"    (PaymentTypeId: \033[0;32m{self.payment_type_id}\033[0m)")
        else:
            print(f"    (PaymentTypeId: \033[0;31mне установлен\033[0m)")
        
        # Пункт 6 - WalletId
        if self.wallet_id:
            print(f"6) Получить WalletId (\033[0;32m{self.wallet_id}\033[0m)")
        else:
            print(f"6) Получить WalletId (\033[0;31mне установлен\033[0m)")
        
        # Пункты 7-10
        print("7) Получить номенклатуру из бэкофиса (сохраняется в файл)")
        print("8) Получить меню из IikoWeb по внешнему ID (сохраняется в файл)")
        print("9) Сбросить OrganizationId")
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
                '4': self.get_external_menus,
                '5': self.get_payment_types_and_programs,
                '6': self.get_wallet_id,
                '7': self.get_nomenclature,
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
