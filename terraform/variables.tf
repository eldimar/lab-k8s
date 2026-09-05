variable "aws_region" {
  description = "Regiao AWS onde o cluster EKS sera criado"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
  default     = "voting-app-eks"
}

variable "cluster_version" {
  description = "Versao do Kubernetes para o cluster EKS"
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones utilizadas pela VPC"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (nodes)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (load balancers / NAT)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "node_instance_types" {
  description = "Tipos de instancia EC2 do managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade minima de nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade maxima de nodes"
  type        = number
  default     = 3
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs autorizados a acessar o endpoint publico da API do EKS.
    Por padrao esta liberado para 0.0.0.0/0 (qualquer origem), o que NAO
    e recomendado fora de laboratorio. Restrinja para o(s) IP(s) publico(s)
    de quem vai rodar kubectl, ex: ["203.0.113.10/32"].
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_capacity_type" {
  description = "Tipo de capacidade do node group (ON_DEMAND ou SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "tags" {
  description = "Tags comuns aplicadas aos recursos"
  type        = map(string)
  default = {
    Project     = "voting-app"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
