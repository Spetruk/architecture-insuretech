#!/bin/bash

# Скрипт для проброса порта к приложению в Kubernetes

echo "🚀 Запуск port-forward для scaletestapp..."
echo "📊 Приложение будет доступно по адресу: http://localhost:8080"
echo "📈 Метрики Prometheus: http://localhost:8080/metrics"
echo ""
echo "⚠️  Для остановки нажмите Ctrl+C"
echo ""

kubectl port-forward service/scaletestapp-service 8080:8080
