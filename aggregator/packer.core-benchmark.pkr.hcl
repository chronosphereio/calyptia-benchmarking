variable "image_name" {
  type    = string
  default = "calyptia-core-benchmark-ubuntu-2004"
}

variable "image_family" {
  type    = string
  default = "calyptia-core-benchmark"
}

variable "gcp_project_id" {
  type        = string
  default     = "calyptia-infra"
  description = "ID of the Project in Google Cloud"
}

variable "root_volume_size_gb" {
  type    = number
  default = 250
}

# https://www.packer.io/docs/datasources/amazon/ami
data "amazon-ami" "base_image" {
  filters = {
    name                = "gold-calyptia-core-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["self"]
  region      = "us-east-1"
}

source "amazon-ebs" "calyptia_aggregator_comparison" {
  ami_name                    = var.image_name
  associate_public_ip_address = true
  instance_type               = "t3.medium"
  region                      = "us-east-1"
  source_ami                  = data.amazon-ami.base_image.id
  ssh_username                = "ubuntu"

  ami_groups = [
    # This causes the ami to be publicly-accessable.
    "all",
  ]

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = "${var.root_volume_size_gb}"
    volume_type = "gp3"
    # gp3: 3,000-16,000 IOPS
    iops = 15000
    # Minimum value of 125. Maximum value of 1000.
    throughput            = 750
    delete_on_termination = true
  }
}

source "googlecompute" "calyptia_aggregator_comparison" {
  image_family        = var.image_family
  image_name          = var.image_name
  image_description   = "Comparison of various tools"
  machine_type        = "n1-standard-1"
  project_id          = var.gcp_project_id
  source_image_family = "gold-calyptia-core"
  ssh_username        = "ubuntu"
  zone                = "us-east1-c"
  disk_size           = "${var.root_volume_size_gb}"
}

build {

  sources = ["source.amazon-ebs.calyptia_aggregator_comparison", "source.googlecompute.calyptia_aggregator_comparison"]

  provisioner "shell" {
    inline = ["/usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
    execute_command = "echo 'packer' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "./scripts/provision.sh"
  }

  provisioner "file" {
    destination = "/test/"
    source      = "./test/"
  }

  provisioner "file" {
    destination = "/config/"
    source      = "./config/"
  }

  provisioner "file" {
    destination = "/etc/fluent-bit/"
    source      = "./config/fluent-bit/"
  }

  # Provide various metadata from Packer we can use
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
