terraform {
  required_version = ">= 1.6"

  # Backend remoto (recomendado para uso real - ver terraform/README.md).
  # Desativado por padrao neste lab: exige um bucket S3 ja existente
  # (nao provisionado aqui, e criar um so para isso teria custo/pegada
  # desnecessarios enquanto o restante do lab tambem nao e aplicado).
  #
  # `use_lockfile = true` usa o locking nativo do backend S3 (Terraform
  # >= 1.10) - dispensa a tabela DynamoDB que o padrao S3+DynamoDB exigia
  # antes.
  #
  # backend "s3" {
  #   bucket       = "SEU_BUCKET_DE_STATE"
  #   key          = "lab-k8s/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.eks.cluster_name,
      "--region", var.aws_region,
    ]
  }
}
