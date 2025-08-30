# Решение для системы продажи ОСАГО

## Обзор требований

### Функциональные требования:
- **Пользовательский путь**: Заполнение заявки → Получение предложений от всех страховых компаний
- **Real-time отображение**: Предложения отображаются немедленно по мере поступления
- **Максимальное время ожидания**: 60 секунд на предложение
- **Пиковая нагрузка**: 2,500 одновременных пользователей

### Технические требования:
- **API страховых компаний**: Однотипные REST API с двумя эндпоинтами
- **Выделенный сервис**: osago-aggregator для взаимодействия со страховыми компаниями
- **Отказоустойчивость**: Применение паттернов resilience

## Архитектурное решение

### 1. **osago-aggregator - Специализированный сервис ОСАГО**

#### **Функциональные обязанности:**
- Отправка заявок во все страховые компании одновременно
- Опрос статуса предложений (polling каждые 2-3 секунды)
- Агрегация и передача результатов в core-app
- Управление таймаутами (60 секунд)

#### **Техническое решение:**
**Язык и фреймворк**: Kotlin + SpringBoot
**Хранилище данных**: Redis для кэширования состояния заявок
**Архитектурные паттерны**: Асинхронная обработка + статeful операции

#### **Почему нужно собственное хранилище (Redis)?**
1. **Состояние заявок**: Необходимо отслеживать статус каждой заявки в каждой страховой компании
2. **Быстрый доступ**: Redis обеспечивает миллисекундные времена отклика
3. **TTL**: Автоматическое удаление устаревших заявок (через 65 секунд)
4. **Масштабируемость**: Поддержка 2,500+ одновременных заявок

#### **API для core-app:**
```http
POST /api/osago/applications
{
  "applicationId": "uuid",
  "vehicle": {...},
  "driver": {...},
  "insuranceCompanies": ["company1", "company2", ...]
}

GET /api/osago/applications/{applicationId}/offers
Response: {
  "applicationId": "uuid",
  "offers": [
    {
      "companyId": "company1",
      "status": "completed",
      "premium": 15000,
      "coverage": {...}
    },
    {
      "companyId": "company2", 
      "status": "processing",
      "estimatedTime": "45s"
    }
  ]
}

GET /api/osago/applications/{applicationId}/status
Response: {
  "completed": 3,
  "processing": 2,
  "failed": 1,
  "timeout": 1
}
```

### 2. **Средства интеграции**

#### **core-app ↔ osago-aggregator: REST API**
- **Обоснование**: Стандартный HTTP/REST для создания заявок и получения статуса
- **Частота запросов**: core-app опрашивает osago-aggregator каждые 2 секунды
- **Паттерны**: Rate Limiting, Timeout, Retry

#### **Web App ↔ core-app: WebSocket + REST**
- **WebSocket**: Real-time отправка обновлений предложений на фронтенд
- **REST**: Создание заявки и получение исторических данных
- **Обоснование**: Бизнес требует немедленного отображения предложений

#### **osago-aggregator ↔ Страховые компании: REST API**
- **Concurrent requests**: Параллельные запросы ко всем компаниям
- **Polling**: Опрос каждые 2-3 секунды до получения ответа или таймаута
- **Паттерны отказоустойчивости**: Полный набор

### 3. **API для веб-приложения**

#### **WebSocket Events:**
```javascript
// Подписка на обновления заявки
ws.send({
  "type": "subscribe",
  "applicationId": "uuid"
});

// Получение real-time обновлений
{
  "type": "offer_received",
  "applicationId": "uuid",
  "companyId": "company1",
  "offer": {
    "premium": 15000,
    "coverage": {...}
  }
}

{
  "type": "offer_timeout",
  "applicationId": "uuid", 
  "companyId": "company2"
}
```

#### **REST API:**
```http
POST /api/osago/applications
PUT /api/osago/applications/{id}/accept-offer
GET /api/osago/applications/{id}/history
```

### 4. **Паттерны отказоустойчивости**

#### **Rate Limiting**
**Где применяется:**
- core-app: Ограничение заявок ОСАГО (100 RPS per user)
- osago-aggregator: Ограничение запросов к страховым компаниям

**Конфигурация:**
```yaml
rate-limiting:
  core-app:
    osago-applications: "100/minute/user"
  osago-aggregator:
    insurance-company: "50/minute/company"
```

#### **Circuit Breaker**
**Где применяется:**
- osago-aggregator → каждая страховая компания (отдельный Circuit Breaker)

**Конфигурация:**
```yaml
circuit-breaker:
  failure-threshold: 5
  recovery-timeout: 30s
  half-open-max-calls: 3
```

**Логика:**
- CLOSED: Нормальная работа
- OPEN: При 5 неудачах подряд - блокировка на 30 секунд
- HALF-OPEN: Пробные запросы для восстановления

#### **Timeout**
**Где применяется:**
- osago-aggregator → страховые компании: 60 секунд
- core-app → osago-aggregator: 65 секунд
- Web App → core-app: 70 секунд

**Обоснование временных рамок:**
- Дает возможность каждому уровню корректно обработать таймаут нижнего уровня

#### **Retry**
**Где применяется:**
- osago-aggregator: Retry для failed requests к страховым компаниям

**Конфигурация:**
```yaml
retry:
  max-attempts: 3
  backoff: exponential
  initial-delay: 1s
  multiplier: 2
  max-delay: 8s
```

### 5. **Влияние множественных экземпляров сервисов**

#### **osago-aggregator (множественные экземпляры):**

**Проблема**: Состояние заявки должно быть доступно всем экземплярам
**Решение**: 
- **Централизованный Redis** cluster для состояния
- **Sticky sessions** НЕ нужны - любой экземпляр может обработать запрос
- **Distributed locking** в Redis для предотвращения duplicate polling

**Пример distributed lock:**
```kotlin
@Service
class OsagoPollingService {
    fun pollInsuranceCompany(applicationId: String, companyId: String) {
        val lockKey = "lock:$applicationId:$companyId"
        val acquired = redisTemplate.setIfAbsent(lockKey, "locked", Duration.ofSeconds(5))
        
        if (acquired == true) {
            try {
                // Опрос страховой компании
                pollCompanyApi(applicationId, companyId)
            } finally {
                redisTemplate.delete(lockKey)
            }
        }
        // Если лок не получен - другой экземпляр уже обрабатывает
    }
}
```

#### **core-app (множественные экземпляры):**

**WebSocket connection handling:**
- **Load Balancer с sticky sessions** для WebSocket соединений
- **Redis pub/sub** для broadcast обновлений между экземплярами

```kotlin
@Service
class OsagoNotificationService {
    fun notifyOfferReceived(applicationId: String, offer: Offer) {
        // Отправляем в Redis pub/sub для всех экземпляров
        redisTemplate.convertAndSend("osago:offers", 
            OfferNotification(applicationId, offer))
    }
    
    @EventListener
    fun handleOfferNotification(notification: OfferNotification) {
        // Каждый экземпляр получает уведомление и проверяет свои WebSocket соединения
        webSocketSessions
            .filter { it.applicationId == notification.applicationId }
            .forEach { session -> 
                session.sendMessage(notification.toWebSocketMessage())
            }
    }
}
```

### 6. **Обработка пиковой нагрузки (2,500 пользователей)**

#### **Расчет ресурсов:**

**osago-aggregator:**
- 2,500 заявок × 10 страховых компаний = 25,000 активных polling операций
- Polling каждые 3 секунды = ~8,333 запросов/сек к страховым компаниям
- **Количество экземпляров**: 3-5 экземпляров
- **Redis**: Cluster с 3 нодами для высокой доступности

**core-app:**
- WebSocket соединения: 2,500 активных соединений
- HTTP API: ~500 RPS (создание заявок + получение статуса)
- **Количество экземпляров**: 2-3 экземпляра с sticky sessions для WebSocket

#### **Monitoring и Alerting:**

**Ключевые метрики:**
- Response time по каждой страховой компании
- Circuit Breaker states
- Redis connection pool utilization
- WebSocket connection count
- Rate limiting hit ratio

### 7. **Преимущества решения**

1. **Real-time UX**: Пользователи видят предложения немедленно
2. **Отказоустойчивость**: Сбои отдельных страховых компаний не влияют на остальные
3. **Масштабируемость**: Горизонтальное масштабирование всех компонентов
4. **Observability**: Полная видимость в производительность каждой страховой компании
5. **Graceful degradation**: Система работает даже при недоступности части страховых компаний

### 8. **Риски и митигация**

#### **Риск 1: Overwhelm страховых компаний**
**Митигация**: Rate Limiting + Circuit Breaker + координация с партнерами по лимитам

#### **Риск 2: WebSocket connection leaks**
**Митигация**: Connection pooling + heartbeat + automatic cleanup

#### **Риск 3: Redis single point of failure**
**Митигация**: Redis Cluster + backup strategy + fallback к PostgreSQL

## Заключение

Предложенная архитектура обеспечивает:
- ✅ Real-time обновления предложений ОСАГО
- ✅ Поддержку 2,500+ одновременных пользователей  
- ✅ Отказоустойчивость через полный набор resilience паттернов
- ✅ Горизонтальное масштабирование всех компонентов
- ✅ Excellent observability и monitoring

Система готова к production нагрузкам и обеспечивает отличный пользовательский опыт при оформлении ОСАГО.
