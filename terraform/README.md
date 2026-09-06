# Terraform - EKS para o App de Votação

Provisiona a infraestrutura AWS necessária para rodar o app de votação:

- VPC dedicada (2 AZs, subnets públicas/privadas, 1 NAT Gateway)
- Cluster EKS (`voting-app-eks` por padrão)
- Managed Node Group EC2 (t3.medium, 1-3 nodes, ON_DEMAND)
- Addons gerenciados: coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver

State é local (`terraform.tfstate`), adequado para laboratório/teste.

## Backend remoto (recomendado para uso real)

`versions.tf` já traz um bloco `backend "s3"` pronto, comentado (desativado
por padrão neste lab — exigiria criar um bucket S3 só para isso, sem
necessidade enquanto o resto também não é aplicado). Ele usa `use_lockfile`
(Terraform >= 1.10), o locking nativo do backend S3 — dispensa a tabela
DynamoDB que o padrão S3+DynamoDB exigia antes.

Para ativar:

```bash
# 1. Crie o bucket (nome globalmente unico) com versionamento e criptografia
aws s3api create-bucket --bucket SEU_BUCKET_DE_STATE --region us-east-1
aws s3api put-bucket-versioning --bucket SEU_BUCKET_DE_STATE \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket SEU_BUCKET_DE_STATE \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 2. Descomente o bloco backend "s3" em versions.tf (ajuste bucket/region)

# 3. Migre o state local para o S3
terraform init -migrate-state
```

## Boas práticas aplicadas

- Secrets do cluster criptografados no etcd via KMS (`cluster_encryption_config`, default do módulo)
- IRSA/OIDC habilitado — o addon `aws-ebs-csi-driver` usa uma role IAM dedicada
  (least-privilege) via IRSA, necessária para o PVC do PostgreSQL funcionar
- Logging do control plane habilitado (audit, api, authenticator) no CloudWatch
- Nodes com IMDSv2 obrigatório e volume raiz criptografado (gp3)
- Nodes em subnets privadas; load balancers expostos via subnets públicas
- `authentication_mode = API_AND_CONFIG_MAP` (acesso via EKS Access Entries)

## Endpoint público do EKS

`cluster_endpoint_public_access_cidrs` não tem default — é proposital, para
não ter um "0.0.0.0/0 disponível de graça" caso alguém esqueça de definir.
`terraform plan`/`apply` falham até você definir em `terraform.tfvars`:

```hcl
cluster_endpoint_public_access_cidrs = ["SEU_IP_PUBLICO/32"]
```

Ou desabilite o acesso público totalmente (`cluster_endpoint_public_access = false`
em `eks.tf`) e acesse via VPN/bastion apenas pela rede privada.

## Gap conhecido: VPC Flow Logs

VPC Flow Logs não estão habilitados (identificado pelo `tfsec`). Dá visibilidade
de tráfego de rede útil para investigar incidentes, mas gera custo contínuo de
ingestão/armazenamento (CloudWatch Logs ou S3) — por isso não foi habilitado
por padrão neste lab. Para produção, habilite via `flow_log_*` no módulo
`terraform-aws-modules/vpc/aws` em `vpc.tf`.

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
