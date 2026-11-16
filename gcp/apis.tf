resource "google_project_service" "core" {
  for_each = local.core_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "demo" {
  for_each = var.enable_demo_apis ? local.demo_services : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
