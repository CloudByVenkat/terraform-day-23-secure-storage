terraform {
  required_version = "~> 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.62.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}
provider "azurerm" {
  features {}
}
