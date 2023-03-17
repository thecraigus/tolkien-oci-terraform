
variable "tenancy_ocid" {
  default = "add tenancy ocid"
}

variable "user_ocid" {
  default = "add ocid"
}

variable "fingerprint" {
  default = "add fingerprint"
}

variable "private_key_path" {
  default = "C:\\Users\\clcar\\.ssh\\craig.cartlidge-03-05-15-47.pem"
}

variable "region" {
  default = "us-ashburn-1"
}

variable "compartment_ocid" {
  default = "add compartment ocid"
}

variable "ssh_public_key" {
  default = "add public key"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}


variable "num_instances" {
  default = "2"
}

variable "instance_shape" {
  default = "VM.Standard.E2.1.Micro"
}
variable "instance_ocpus" {
  default = 1
}

variable "instance_shape_config_memory_in_gbs" {
  default = 1
}

variable "flex_instance_image_ocid" {
  type = map(string)
  default = {
    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaa6tp7lhyrcokdtf7vrbmxyp2pctgg4uxvt4jz4vc47qoc2ec4anha"
  }
}

variable "web_tier_subnet_ocid" {
  default = "add web tier ocid"
}

variable "lb_tier_subnet_ocid" {
  default = "add lb tier ocid"
}

resource "oci_core_instance" "web_servers" {
  count               = var.num_instances
  availability_domain = "iBaU:US-ASHBURN-AD-1"
  fault_domain = "FAULT-DOMAIN-${count.index+1}"
  compartment_id      = var.compartment_ocid
  display_name        = "WebApp-${count.index}"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id                 = var.web_tier_subnet_ocid
    display_name              = "Primaryvnic"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = "WebApp-${count.index}"
  }

  source_details {
    source_type = "image"
    source_id   = var.flex_instance_image_ocid[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

resource "oci_load_balancer" "tolkien-lb-2" {
  shape          = "flexible"
  compartment_id = var.compartment_ocid

  subnet_ids = [
    var.lb_tier_subnet_ocid
  ]

  shape_details {
    maximum_bandwidth_in_mbps = 10
    minimum_bandwidth_in_mbps = 10
  }

  display_name = "tolkien-lb-2"
}


resource "oci_load_balancer_backend_set" "tolkien-lb-bes1" {
  name             = "lb-bes1"
  load_balancer_id = oci_load_balancer.tolkien-lb-2.id
  policy           = "ROUND_ROBIN"

  health_checker {
    port                = "8080"
    protocol            = "HTTP"
    url_path            = "/"
    return_code = "200"
  }
}

resource "oci_load_balancer_backend" "tolkien-lb-be1" {
  count            = var.num_instances
  load_balancer_id = oci_load_balancer.tolkien-lb-2.id
  backendset_name  = oci_load_balancer_backend_set.tolkien-lb-bes1.name
  ip_address       = oci_core_instance.web_servers[count.index].private_ip
  port             = 8080
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}


resource "oci_load_balancer_listener" "lb-listener1" {
  load_balancer_id         = oci_load_balancer.tolkien-lb-2.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.tolkien-lb-bes1.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = "2"
  }
}

resource "null_resource" "remote-exec" {
  depends_on = [
    oci_core_instance.web_servers,
  ]
  count = var.num_instances

  provisioner "remote-exec" {
    connection {
      agent       = false
      timeout     = "30m"
      host        = oci_core_instance.web_servers[count.index % var.num_instances].public_ip
      user        = "opc"
      private_key = file("C:\\Users\\clcar\\.ssh\\oci-tf-test")
    }

    inline = [
    "sudo yum install -y yum-utils",
    "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo",
    "sudo yum install docker-ce docker-ce-cli containerd.io -y",
    "sudo systemctl start docker",
    "sudo systemctl enable docker",
    "sudo docker pull clcartlidge/tolkienweb:latest",
    "sudo docker run -p 8080:8080 -d clcartlidge/tolkienweb:latest"
    ]
  }
}
