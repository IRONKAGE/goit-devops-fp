resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = var.namespace
  create_namespace = true

  # Вмикаємо DEV-режим (автоматичний Unseal та root-токен "root")
  set {
    name  = "server.dev.enabled"
    value = "true"
  }

  # Вмикаємо гарний Web UI для демонстрації
  set {
    name  = "ui.enabled"
    value = "true"
  }

  # Зменшуємо запити до ресурсів (щоб не з'їсти весь кластер)
  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }
}
