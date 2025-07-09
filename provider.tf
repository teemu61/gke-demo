terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.43.0"
    }
  }
}


provider "google" {
  region  = var.region
  project = var.project
  #   credentials = file("tcb-project-371706-b114ce01e529.json")
  zone = var.zone

}
