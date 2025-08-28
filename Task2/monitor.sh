#!/bin/bash

# Скрипт для мониторинга HPA и ресурсов в реальном времени

echo "🔄 Мониторинг HPA и использования ресурсов"
echo "⚠️  Для остановки нажмите Ctrl+C"
echo ""

while true; do
    clear
    echo "📊 МОНИТОРИНГ KUBERNETES - $(date)"
    echo "=================================================="
    echo ""
    
    echo "🚀 HPA Status:"
    kubectl get hpa scaletestapp-hpa
    echo ""
    
    echo "📈 Resource Usage:"
    kubectl top pods -l app=scaletestapp
    echo ""
    
    echo "🔢 Pod Count:"
    kubectl get pods -l app=scaletestapp --no-headers | wc -l | tr -d ' '
    echo ""
    
    echo "📋 Pods List:"
    kubectl get pods -l app=scaletestapp -o wide
    echo ""
    
    echo "⏱️  Обновление каждые 5 секунд..."
    sleep 5
done
