from locust import HttpUser, between, task

class WebsiteUser(HttpUser):
    wait_time = between(1, 5)
    
    @task
    def index(self):
        self.client.get("/")
        
    @task(3)  # Более частый запрос для создания большей нагрузки
    def index_heavy(self):
        # Делаем несколько запросов подряд для увеличения использования памяти
        for _ in range(10):
            self.client.get("/")
