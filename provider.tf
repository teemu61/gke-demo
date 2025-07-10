terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.43.0"
    }
  }
}

# provider "google" {
#   region  = var.region
#   project = var.project
#   zone    = var.zone
# }

provider "google-beta" {
  region  = var.region
  project = var.project
  zone    = var.zone
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}


