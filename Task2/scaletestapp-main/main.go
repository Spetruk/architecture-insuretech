package main

import (
	"fmt"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"net/http"
	"os"
)

var reqCounter = prometheus.NewCounter(
	prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "No of request handled",
	},
)

func main() {

	prometheus.MustRegister(reqCounter)

	router := http.NewServeMux()

	router.Handle("/metrics", promhttp.Handler())

	router.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		reqCounter.Inc()
		podName := os.Getenv("HOSTNAME")
		if podName == "" {
			podName = "Неизвестен"
		}
		fmt.Fprintf(w, "Идентификатор пода: %s\n", podName)
	})

	http.ListenAndServe(":8080", router)

}
