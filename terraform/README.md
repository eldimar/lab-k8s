# Terraform - EKS para o App de Votação

Provisiona a infraestrutura AWS necessária para rodar o app de votação:

- VPC dedicada (2 AZs, subnets públicas/privadas, 1 NAT Gateway)
- Cluster EKS (`voting-app-eks` por padrão)
- Managed Node Group EC2 (t3.medium, 1-3 nodes, ON_DEMAND)
- Addons gerenciados: coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver

State é local (`terraform.tfstate`), adequado para laboratório/teste. Para uso
real, migrar para backend remoto (S3 + DynamoDB).

## Boas práticas aplicadas

- Secrets do cluster criptografados no etcd via KMS (`cluster_encryption_config`, default do módulo)
- IRSA/OIDC habilitado — o addon `aws-ebs-csi-driver` usa uma role IAM dedicada
  (least-privilege) via IRSA, necessária para o PVC do PostgreSQL funcionar
- Logging do control plane habilitado (audit, api, authenticator) no CloudWatch
- Nodes com IMDSv2 obrigatório e volume raiz criptografado (gp3)
- Nodes em subnets privadas; load balancers expostos via subnets públicas
- `authentication_mode = API_AND_CONFIG_MAP` (acesso via EKS Access Entries)

## Atenção: endpoint público do EKS

Por padrão, `cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]`, ou seja,
o endpoint da API fica acessível publicamente de qualquer IP (apenas com
autenticação IAM, mas ainda assim uma superfície de ataque desnecessária).

**Antes de aplicar em algo além de um teste rápido**, restrinja para o seu IP:

```hcl
cluster_endpoint_public_access_cidrs = ["SEU_IP_PUBLICO/32"]
```

Ou desabilite o acesso público totalmente (`cluster_endpoint_public_access = false`)
e acesse via VPN/bastion apenas pela rede privada.

## Pré-requisitos

- Terraform >= 1.6
- Credenciais AWS configuradas (`aws configure` ou variáveis de ambiente)
- AWS CLI instalado (usado pelo provider `kubernetes` para autenticação e pelo
  comando `update-kubeconfig`)

## Uso

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste se necessário

terraform init
terraform plan
terraform apply
```

Após o `apply`, configure o `kubectl`:

```bash
$(terraform output -raw configure_kubectl)
```

## Destruir

```bash
terraform destroy
```
