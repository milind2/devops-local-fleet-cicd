terraform {
  required_version = ">= 1.7.0"

  backend "local" {                     # state stays on this machine
    path = "terraform.tfstate"          # terraform/terraform.tfstate (git-ignored)
  }

  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "multipass" {}
