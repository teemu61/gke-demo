resource "google_compute_network" "vpc" {
  project                 = var.project
  name                    = "gke-vpc"
  auto_create_subnetworks = false
  lifecycle { ignore_changes = all }
}

resource "google_compute_network" "vpc2" {
  project                 = var.project
  name                    = "gke-vpc2"
  auto_create_subnetworks = false
  lifecycle { ignore_changes = all }
}

resource "google_compute_network" "vpc3" {
  project                 = var.project
  name                    = "gke-vpc3"
  auto_create_subnetworks = false
  lifecycle { ignore_changes = all }
}

resource "google_compute_subnetwork" "subnet" {
  project       = var.project
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "192.168.0.0/24"
  }
  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "192.168.1.0/24"
  }
  lifecycle { ignore_changes = all }
}

resource "google_compute_subnetwork" "subnet2" {
  project       = var.project
  name          = "gke-subnet2"
  ip_cidr_range = "10.1.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc2.id
  secondary_ip_range {
    range_name    = "services-range2"
    ip_cidr_range = "192.168.2.0/24"
  }
  secondary_ip_range {
    range_name    = "pod-ranges2"
    ip_cidr_range = "192.168.3.0/24"
  }
  lifecycle { ignore_changes = all }
}

resource "google_compute_subnetwork" "subnet3" {
  project       = var.project
  name          = "gke-subnet3"
  ip_cidr_range = "10.2.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc3.id
  secondary_ip_range {
    range_name    = "services-range3"
    ip_cidr_range = "192.168.4.0/24"
  }
  secondary_ip_range {
    range_name    = "pod-ranges3"
    ip_cidr_range = "192.168.5.0/24"
  }
  lifecycle { ignore_changes = all }
}


resource "google_service_account" "service-account-for-gke-demo" {
  project      = var.project
  account_id   = "terraform-demo-aft"
  display_name = "Service Account for GKE nodes"
}

resource "google_container_cluster" "primary" {
  project                  = var.project_id
  name                     = "test-cluster"
  location                 = var.location
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1
  networking_mode          = "VPC_NATIVE"
  enable_multi_networking  = true
  datapath_provider        = "ADVANCED_DATAPATH"

  # This must NOT overlap with "10.0.0.0/16"
  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.13.0.0/28"
  }

  # Enable just-host to access gke cluster
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.4/32"
      display_name = "net1"
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  project    = var.project_id
  name       = "primary-node-pool"
  location   = var.location
  cluster    = google_container_cluster.primary.name
  node_count = 4

  # Define an additional network to support multi-network Pods
  network_config {
    enable_private_nodes = true
    additional_node_network_configs {
      network    = google_compute_network.vpc2.name
      subnetwork = google_compute_subnetwork.subnet2.name
    }
    additional_node_network_configs {
      network    = google_compute_network.vpc3.name
      subnetwork = google_compute_subnetwork.subnet3.name
    }
    additional_pod_network_configs {
      subnetwork          = google_compute_subnetwork.subnet2.name
      secondary_pod_range = "pod-ranges2"
      max_pods_per_node   = 4
    }
    additional_pod_network_configs {
      subnetwork          = google_compute_subnetwork.subnet3.name
      secondary_pod_range = "pod-ranges3"
      max_pods_per_node   = 4
    }
  }
  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/compute",
    ]
    labels       = { env = "dev" }
    machine_type = "e2-standard-4"
    preemptible  = true
    metadata     = { disable-legacy-endpoints = "true" }
  }
}

# Create jump host . We will allow this jump host to access GKE cluster.
resource "google_compute_address" "my_internal_ip_addr" {
  project      = var.project
  address_type = "INTERNAL"
  region       = var.region
  subnetwork   = google_compute_subnetwork.subnet.name
  name         = "jump-host-internal-ip"
  address      = "10.0.0.4"
  description  = "An internal IP address for my jump host"
}

resource "google_compute_instance" "jump-host-vm" {
  project      = var.project
  zone         = var.zone
  name         = "jump-host"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = google_compute_address.my_internal_ip_addr.address
  }
  metadata = {
    "startup-script" = <<EOF
    #!/bin/bash
    #install tinyproxy
    sudo apt-get update -y
    sudo apt-get install tinyproxy -y
    sudo cp /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf.bak
    sudo sed -i '/Allow 127.0.0.1/a Allow localhost' /etc/tinyproxy/tinyproxy.conf
    sudo systemctl start tinyproxy
    EOF
  }
}

# Creare Firewall to access jump host via iap
resource "google_compute_firewall" "rules" {
  project = var.project
  name    = "allow-ssh"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20", "192.168.10.60/32"]
}

resource "google_compute_firewall" "rules2" {
  project = var.project
  name    = "allow-icmp1"
  network = google_compute_network.vpc2.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rules3" {
  project = var.project
  name    = "allow-icmp2"
  network = google_compute_network.vpc.name
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}


# Create IAP SSH permissions for your test instance
resource "google_project_iam_member" "project" {
  project = var.project
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:terraform-demo-aft@woven-operative-454517-f9.iam.gserviceaccount.com"

  depends_on = [
    google_service_account.service-account-for-gke-demo
  ]
}

# create cloud router for nat gateway
resource "google_compute_router" "router" {
  project = var.project
  name    = "nat-router"
  network = google_compute_network.vpc.name
  region  = var.region
}

# Create Nat Gateway with module
module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = var.project_id
  region     = var.region
  router     = google_compute_router.router.name
  name       = "nat-config"
}

# resource "kubernetes_namespace" "testing" {
#   metadata {
#     name = "testing"
#   }
# }

# resource "kubernetes_manifest" "configmap" {
#   manifest = yamldecode(file("./manifests/configmap.yaml"))
# }
