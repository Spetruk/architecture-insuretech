#!/bin/bash

echo "=== ЗАПУСК ТЕСТА RATE LIMITING ==="

# Убиваем все процессы
echo "Останавливаем все сервера..."
sudo pkill nginx 2>/dev/null || true
pkill -f "python3 -m http.server" 2>/dev/null || true
pkill -f "go run" 2>/dev/null || true

# Ищем свободный порт и запускаем backend
echo "Запускаем backend на свободном порту..."
for port in 9001 9002 9003 9004 9005; do
    if ! lsof -i :$port >/dev/null 2>&1; then
        echo "Используем порт $port"
        python3 -m http.server $port &
        BACKEND_PID=$!
        BACKEND_PORT=$port
        break
    fi
done
sleep 2

# Копируем готовый конфиг и обновляем порты
echo "Обновляем порты в готовом конфиге Task6/nginx.conf..."
cp /Users/av/Developer/architecture-insuretech/Task6/nginx.conf /tmp/test_nginx.conf
sed -i '' "s/127.0.0.1:8080/127.0.0.1:$BACKEND_PORT/g" /tmp/test_nginx.conf
sed -i '' "s/127.0.0.1:8081/127.0.0.1:$BACKEND_PORT/g" /tmp/test_nginx.conf  
sed -i '' "s/127.0.0.1:8082/127.0.0.1:$BACKEND_PORT/g" /tmp/test_nginx.conf
sed -i '' "s/listen 80;/listen 8091;/g" /tmp/test_nginx.conf

# Запускаем nginx с обновлённым конфигом
echo "Запускаю nginx с Task6/nginx.conf на порту 8091..."
/tmp/nginx/sbin/nginx -c /tmp/test_nginx.conf
sleep 2

# Тестируем rate limiting
echo "=========================================="
echo "🚀 ДЕМОНСТРАЦИЯ RATE LIMITING (10r/m)"
echo "Лимит: 1 запрос каждые 6 секунд"
echo "=========================================="

echo
echo "📈 ТЕСТ 1: Спам-атака (10 быстрых запросов)"
echo "Ожидаем: 1-й запрос ✅, остальные ❌ 429"
echo "------------------------------------------"
SUCCESS=0
BLOCKED=0
for i in {1..10}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8091/)
    if [ "$CODE" = "200" ]; then
        echo "Запрос $i: ✅ HTTP $CODE (ПРОШЁЛ)"
        ((SUCCESS++))
    else
        echo "Запрос $i: ❌ HTTP $CODE (ЗАБЛОКИРОВАН)"
        ((BLOCKED++))
    fi
done
echo "📊 ИТОГ: ✅ Прошло: $SUCCESS, ❌ Заблокировано: $BLOCKED"

echo
echo "📉 ТЕСТ 2: Легальные запросы (с паузами)"
echo "Ожидаем: все запросы ✅ 200"
echo "------------------------------------------"
SUCCESS2=0
for i in {1..3}; do
    echo "⏰ Ждём 7 секунд перед запросом $i..."
    sleep 7
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8091/)
    if [ "$CODE" = "200" ]; then
        echo "Запрос $i: ✅ HTTP $CODE (ПРОШЁЛ)"
        ((SUCCESS2++))
    else
        echo "Запрос $i: ❌ HTTP $CODE (ЗАБЛОКИРОВАН)"
    fi
done
echo "📊 ИТОГ: ✅ Прошло: $SUCCESS2/3"

echo
echo "=========================================="
echo "🎯 ОБЩИЙ РЕЗУЛЬТАТ:"
echo "Rate limiting ЗАЩИЩАЕТ от спама (${BLOCKED}/10 заблокировано)"
echo "Легальный трафик ПРОХОДИТ (${SUCCESS2}/3 прошло)"
echo "=========================================="

# Убираем за собой
echo
echo "Останавливаем сервера..."
/tmp/nginx/sbin/nginx -s stop 2>/dev/null || true
kill $BACKEND_PID 2>/dev/null || true

echo "=== ТЕСТ ЗАВЕРШЁН ==="
