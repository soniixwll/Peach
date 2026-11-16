resource "google_firebase_project" "peach" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.core["firebase.googleapis.com"]]
}

resource "google_firebase_hosting_site" "peach" {
  provider = google-beta
  project  = google_firebase_project.peach.project
  site_id  = var.project_id

  depends_on = [google_project_service.core["firebasehosting.googleapis.com"]]
}
