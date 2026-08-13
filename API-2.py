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
