# Manifestos Kubernetes - App de Votação

Deploy completo do [example-voting-app](https://github.com/dockersamples/example-voting-app)
no namespace `voting-app`.

## Componentes

| Manifesto | Recurso | Descrição |
|---|---|---|
| `00-namespace.yaml` | Namespace | `voting-app` |
| `01-storageclass.yaml` | StorageClass | `gp3` via `ebs.csi.aws.com`, criptografada |
| `02-postgres-secret.yaml` | Secret | Credenciais do Postgres |
| `03-postgres-pvc.yaml` | PVC | 5Gi para dados do Postgres |
| `04-postgres-deployment.yaml` / `05-postgres-service.yaml` | Deployment + Service `db` | PostgreSQL 15 |
| `06-redis-deployment.yaml` / `07-redis-service.yaml` | Deployment + Service `redis` | Fila/cache |
| `08-vote-deployment.yaml` / `09-vote-service.yaml` | Deployment + Service (LoadBalancer/NLB) | Frontend de votação |
| `10-worker-deployment.yaml` | Deployment | Consome Redis, grava no Postgres |
| `11-result-deployment.yaml` / `12-result-service.yaml` | Deployment + Service (LoadBalancer/NLB) | Frontend de resultados |

## Importante: hostnames fixos

As imagens `dockersamples/examplevotingapp_vote`, `_worker` e `_result` têm a
connection string do Postgres e o host do Redis fixos no código
(`Server=db;Username=postgres;Password=postgres` e host `redis`). Por isso os
Services **precisam** se chamar exatamente `db` e `redis`, e o usuário/senha
do Postgres precisam ser `postgres`/`postgres` — não são configuráveis via env
sem rebuildar as imagens.

## Segurança dos containers

Todos os containers rodam com `allowPrivilegeEscalation: false` e capabilities
dropadas. `redis`, `vote`, `result` e `worker` também rodam com
`runAsNonRoot`, `runAsUser` fixo e `readOnlyRootFilesystem: true` (validado
via deploy de teste — `vote` e `worker` precisaram de um `emptyDir` em `/tmp`
para isso funcionar). O `db` é a única exceção: o entrypoint oficial da
imagem `postgres:15-alpine` precisa rodar como root para ajustar
permissões do data dir antes de trocar para o usuário `postgres` — validado
empiricamente que `runAsNonRoot`/`readOnlyRootFilesystem`/`drop: ALL` quebram
o start dela. As imagens `vote`, `result` e `worker` são pinadas por digest
(`@sha256:...`) em vez de depender só da tag `latest`, já que o mantenedor
não publica tags de versão para elas.

## Pré-requisitos

- Cluster EKS provisionado (ver `../terraform`) com o addon `aws-ebs-csi-driver`
  ativo (necessário para o PVC do Postgres)
- `kubectl` configurado apontando para o cluster:
  ```bash
  aws eks update-kubeconfig --region us-east-1 --name voting-app-eks
  ```

## Deploy

```bash
kubectl apply -k .
```

Ou individualmente, na ordem dos arquivos (o prefixo numérico já reflete a
ordem de dependência).

## Acessar a aplicação

```bash
kubectl -n voting-app get svc vote result
```

Os Services `vote` e `result` são do tipo `LoadBalancer` com a annotation
`service.beta.kubernetes.io/aws-load-balancer-type: "nlb"` — o AWS Cloud
Controller Manager provisiona um Network Load Balancer para cada um
automaticamente (**gera custo contínuo** enquanto os Services existirem).
O `EXTERNAL-IP`/hostname do NLB aparece no `kubectl get svc` acima assim que
o provisionamento terminar (pode levar 1-2 minutos).

Alternativa sem custo de LB, para um teste rápido:

```bash
kubectl -n voting-app port-forward svc/vote 8080:80
kubectl -n voting-app port-forward svc/result 8081:80
```

## Storage

A `StorageClass` usa `reclaimPolicy: Retain`: ao deletar o PVC/namespace, o
volume EBS **não** é apagado automaticamente (evita perda acidental de dados).
Para evitar volume órfão (custo) depois de um teste, apague manualmente o
volume EBS após o `kubectl delete`/`terraform destroy`, ou troque para
`reclaimPolicy: Delete`.

> **Cuidado com multi-AZ:** o node group (ver `../terraform`) tem nodes em
> 2 AZs. Um volume EBS é preso à AZ onde foi criado; a `StorageClass` usa
> `volumeBindingMode: WaitForFirstConsumer` para provisionar na mesma AZ do
> node onde o pod do Postgres for agendado primeiro, mas se esse node for
> removido e não sobrar nenhum node na mesma AZ, o pod fica `Pending`. Para
> produção, considere um node group dedicado de storage em AZ única ou
> Multi-AZ com replicação (ex: réplicas de leitura do Postgres).

## Limpeza

```bash
kubectl delete -k .
```
