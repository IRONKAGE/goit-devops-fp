resource "helm_release" "prometheus_stack" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = var.namespace
  create_namespace = true
  timeout          = 900

  # Перевизначаємо ім'я сервісу Grafana,
  # щоб команда з ТЗ `kubectl port-forward svc/grafana...` спрацювала ідеально!
  set {
    name  = "grafana.fullnameOverride"
    value = "grafana"
  }

  # Передаємо захищений пароль для Grafana
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  # Вимикаємо деякі важкі алерти, щоб не перевантажити ваш EKS кластер
  set {
    name  = "prometheus.prometheusSpec.scrapeInterval"
    value = "30s"
  }
}
