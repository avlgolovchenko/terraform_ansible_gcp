provider "google" {
    credentials = file("key.json")
    project = "rebrain"
    region = "europe-west3-c"
}

provider "aws" {
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    region = "eu-west-1"
}

data "aws_route53_zone" "primary" {
  name = "devops.rebrain.srwx.net"
}

resource "aws_route53_record" "avg_dns"{
    zone_id = data.aws_route53_zone.primary.zone_id
    name = "${var.login}.devops.rebrain.srwx.net"
    type = "A"
    ttl = "300"
    records = ["${google_compute_global_address.avlgolovchenko.address}"]
}

resource "random_id" "instance_id" {
    byte_length = 8
}

resource "google_compute_global_address" "avlgolovchenko" {
    name = "avlgolovchenko"
}

resource "google_compute_instance_group" "webservers" {
    name        = "avl-webservers"
    zone = "europe-west3-c"
    instances = [
        google_compute_instance.frontend.self_link,
    ]

    named_port {
        name = "http"
        port = "80"
    }
}

resource "google_compute_health_check" "autohealing" {
    name         = "avlcheck"
    timeout_sec        = 1
    check_interval_sec = 1
    http_health_check {
    port = 80
  }

}

resource "google_compute_url_map" "default" {
    name            = "avl-url-map"
    default_service = google_compute_backend_service.default.self_link
}

resource "google_compute_backend_service" "default" {
  name        = "avl-backend-service"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10
  backend {
    group = google_compute_instance_group.webservers.self_link
  }
  health_checks = [google_compute_health_check.autohealing.self_link]
}


resource "google_compute_target_http_proxy" "http-proxy" {
    name        = "avl-proxy"
    url_map     = google_compute_url_map.default.self_link
}

resource "google_compute_global_forwarding_rule" "gloable-rules" {
    name       = "avlgolovchenko-lb-${random_id.instance_id.hex}"
    load_balancing_scheme = "EXTERNAL"
    target     = google_compute_target_http_proxy.http-proxy.self_link
    ip_address = google_compute_global_address.avlgolovchenko.address
    port_range = "80"
}

resource "local_file" "ansible_vars" {
    filename = "${path.module}/playbook/roles/config/vars/main.yml"
    content = <<EOT
application_server_name: "${var.login}.${var.domain}"
EOT
}

resource "local_file" "playbook" {
    filename = "${path.module}/playbook/inventory"
    content = <<EOT
all:
    hosts:
        frontend:
            ansible_ssh_host: ${google_compute_instance.frontend.network_interface[0].access_config[0].nat_ip}
            ansible_user : ${var.login}
    EOT
    provisioner "local-exec" {
        command = "cd playbook/ && ansible-playbook -i inventory main.yaml"

    }
        depends_on = [
        local_file.ansible_vars, google_compute_instance.frontend
        ]
}

resource "google_compute_firewall" "default" {
  name    = "avl-firewall"
  network = "default"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

}

resource "google_compute_instance" "frontend" {
    name         = "avl-${random_id.instance_id.hex}"
    machine_type = "f1-micro"
    zone = "europe-west3-c"
    boot_disk {
        initialize_params {
            image = "ubuntu-1804-bionic-v20200129a"
        }
    }

    metadata = {
        ssh-keys = "${var.login}:${file("~/.ssh/id_rsa.pub")}"
    }

    network_interface {
        network = "default"
        access_config {
    }
    }
}