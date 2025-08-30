# Примеры GraphQL запросов для client-info

## Сравнение REST vs GraphQL

### Проблема с REST API

**Сценарий**: Получить базовую информацию о клиенте + его документы + родственников

**REST подход** (3 отдельных запроса):
```http
GET /v1/clients/123
GET /v1/clients/123/documents  
GET /v1/clients/123/relatives
```

**Проблемы REST**:
- 3 отдельных HTTP запроса
- Увеличение RPS в 3 раза
- Network latency × 3
- Overfetching: получаем все поля даже если нужны только некоторые
- Underfetching: если нужны дополнительные данные - еще больше запросов

---

## GraphQL решения

### 1. Базовый запрос (аналог REST GET /clients/{id})

```graphql
query GetBasicClient($id: ID!) {
  client(id: $id) {
    id
    name
    age
  }
}
```

**Переменные:**
```json
{
  "id": "123"
}
```

**Преимущества**: Точно те поля, которые нужны

---

### 2. Комплексный запрос (заменяет 3 REST запроса)

```graphql
query GetClientWithRelatedData($id: ID!) {
  client(id: $id) {
    # Базовая информация
    id
    name
    age
    
    # Документы (вместо отдельного REST запроса)
    documents {
      id
      type
      number
      issueDate
      expiryDate
      status
    }
    
    # Родственники (вместо отдельного REST запроса)  
    relatives {
      id
      name
      relationType
      isEmergencyContact
    }
  }
}
```

**Преимущества**: 
- 1 запрос вместо 3
- Снижение RPS в 3 раза
- Atomic operation - либо все данные, либо ошибка

---

### 3. Сценарий ОСАГО: минимальные данные для заявки

```graphql
query GetClientForOSAGO($id: ID!) {
  client(id: $id) {
    name
    age
    
    # Только паспорт и водительские права
    documents(documentType: PASSPORT) {
      number
      issueDate
      expiryDate
    }
    
    driverLicense: documents(documentType: DRIVER_LICENSE) {
      number
      issueDate
      expiryDate
    }
    
    # Только домашний адрес
    addresses(type: HOME) {
      country
      region  
      city
      street
      building
      apartment
    }
    
    # Контакты
    contacts {
      phone
      email
    }
  }
}
```

**Преимущества**: 
- Только нужные для ОСАГО данные
- Фильтрация на сервере
- Минимальный объем передаваемых данных

---

### 4. Сценарий страхования жизни: полная информация

```graphql
query GetClientForLifeInsurance($id: ID!) {
  client(id: $id) {
    id
    name
    age
    
    # Все документы
    documents {
      type
      number
      issueDate
      expiryDate
      status
      verificationStatus
    }
    
    # Родственники-бенефициары
    relatives(isInsuranceBeneficiary: true) {
      name
      relationType
      age
      contacts {
        phone
        email
      }
    }
    
    # Финансовая информация
    financialInfo {
      monthlyIncome
      employmentStatus
      employer
      creditRating
    }
    
    # История страхования
    insuranceHistory {
      policyType
      premium
      status
      insuranceCompany
    }
    
    # Медицинские справки
    medicalCertificates: documents(documentType: MEDICAL_CERTIFICATE) {
      issueDate
      issuedBy
      status
    }
  }
}
```

**Преимущества**:
- Вся нужная информация в одном запросе
- Фильтрация родственников и документов
- Расширенные данные без дополнительных запросов

---

### 5. Mobile App: оптимизированный запрос

```graphql
query GetClientForMobile($id: ID!) {
  client(id: $id) {
    name
    
    # Только активные документы
    documents(status: ACTIVE) {
      type
      number
      # Без дат - экономим трафик
    }
    
    # Только экстренные контакты
    emergencyContacts: relatives(isEmergencyContact: true) {
      name
      relationType
      contacts {
        phone
      }
    }
    
    # Только основной адрес
    primaryAddress: addresses(isDefault: true) {
      city
      street
      building
    }
  }
}
```

**Преимущества**:
- Минимальный трафик для мобильных устройств
- Только критически важные данные
- Быстрая загрузка

---

### 6. Поиск клиентов с пагинацией

```graphql
query SearchClients($name: String, $first: Int, $after: String) {
  clients(
    name: $name
    first: $first
    after: $after
    orderBy: NAME_ASC
  ) {
    edges {
      node {
        id
        name
        age
        contacts {
          phone
          email
        }
      }
      cursor
    }
    pageInfo {
      hasNextPage
      hasPreviousPage
      startCursor
      endCursor
    }
    totalCount
  }
}
```

**Переменные:**
```json
{
  "name": "Иван",
  "first": 10,
  "after": "cursor123"
}
```

**Преимущества**:
- Эффективная пагинация
- Точный контроль количества результатов
- Метаинформация о пагинации

---

### 7. Batch запрос: несколько клиентов

```graphql
query GetMultipleClients {
  client1: client(id: "123") {
    name
    age
    documents {
      type
      status
    }
  }
  
  client2: client(id: "456") {
    name
    age
    relatives {
      name
      relationType
    }
  }
  
  client3: client(id: "789") {
    name
    contacts {
      phone
      email
    }
  }
}
```

**Преимущества**:
- Множественные запросы в одном HTTP request
- Разные поля для разных клиентов
- Эффективное использование сети

---

## Mutations: Создание и обновление данных

### 8. Создание клиента

```graphql
mutation CreateNewClient($input: CreateClientInput!) {
  createClient(input: $input) {
    client {
      id
      name
      age
      createdAt
    }
    errors {
      message
      code
      field
    }
  }
}
```

**Переменные:**
```json
{
  "input": {
    "name": "Иван Петров",
    "age": 35,
    "contacts": {
      "phone": "+7 900 123-45-67",
      "email": "ivan@example.com",
      "preferredContactMethod": "PHONE"
    },
    "addresses": [
      {
        "type": "HOME",
        "country": "Россия",
        "region": "Московская область",
        "city": "Москва",
        "street": "Тверская",
        "building": "10",
        "apartment": "5",
        "postalCode": "125009",
        "isDefault": true
      }
    ]
  }
}
```

### 9. Добавление документа

```graphql
mutation AddPassport($input: AddDocumentInput!) {
  addClientDocument(input: $input) {
    document {
      id
      type
      number
      issueDate
      client {
        name
      }
    }
    errors {
      message
      field
    }
  }
}
```

**Переменные:**
```json
{
  "input": {
    "clientId": "123",
    "type": "PASSPORT",
    "number": "1234 567890",
    "issueDate": "2020-01-15",
    "expiryDate": "2030-01-15",
    "issuedBy": "ОУФМС России"
  }
}
```

---

## Производительность: сравнение сценариев

### REST API (текущее состояние)
```
Сценарий "Получить клиента + документы + родственников":
- Запросов: 3
- RPS нагрузка: 3x базовой
- Network roundtrips: 3
- Передаваемые данные: ~500 полей × 3 = 1500 полей (включая ненужные)
```

### GraphQL API (предлагаемое решение)
```
Тот же сценарий:
- Запросов: 1  
- RPS нагрузка: 1x базовой
- Network roundtrips: 1
- Передаваемые данные: только нужные поля (например, 50 из 500)
```

### Экономия ресурсов
- **RPS**: снижение в 3 раза
- **Network latency**: снижение в 3 раза  
- **Трафик**: снижение в 10 раз (50 vs 500 полей)
- **Гибкость**: каждый consumer запрашивает только нужные данные

---

## Выводы

GraphQL решает основные проблемы REST API для client-info:

1. **Снижение RPS** - объединение множественных запросов в один
2. **Гибкость выборки** - каждый сценарий запрашивает только нужные данные  
3. **Производительность** - минимизация трафика и network roundtrips
4. **Developer Experience** - типизированная схема, introspection, tooling
5. **Эволюция API** - добавление новых полей без breaking changes
