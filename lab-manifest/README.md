# Manifestos Kubernetes - App de Votação

Deploy completo do [example-voting-app](https://github.com/dockersamples/example-voting-app)
no namespace `voting-app`.

## Componentes

| Manifesto | Recurso | Descrição |
|---|---|---|
| `00-namespace.yaml` | Namespace | `voting-app` |
| `02-postgres-secret.yaml` | Secret | Credenciais do Postgres |
| `03-postgres-pvc.yaml` | PVC | 5Gi para dados do Postgres (usa a StorageClass default do cluster) |
| `04-postgres-deployment.yaml` / `05-postgres-service.yaml` | Deployment + Service `db` | PostgreSQL 15 |
| `06-redis-deployment.yaml` / `07-redis-service.yaml` | Deployment + Service `redis` | Fila/cache |
| `08-vote-deployment.yaml` / `09-vote-service.yaml` | Deployment + Service (NodePort) | Frontend de votação |
| `10-worker-deployment.yaml` | Deployment | Consome Redis, grava no Postgres |
| `11-result-deployment.yaml` / `12-result-service.yaml` | Deployment + Service (NodePort) | Frontend de resultados |

## Importante: hostnames fixos

As imagens `dockersamples/examplevotingapp_vote`, `_worker` e `_result` têm a
connection string do Postgres e o host do Redis fixos no código
(`Server=db;Username=postgres;Password=postgres` e host `redis`). Por isso os
Services **precisam** se chamar exatamente `db` e `redis`, e o usuário/senha
do Postgres precisam ser `postgres`/`postgres` — não são configuráveis via env
sem rebuildar as imagens.

## Pré-requisitos

- `kubectl` apontando para o cluster local `kind-labs` (`kubectl config
  current-context`)
- A PVC do Postgres usa a `StorageClass` default do cluster (no kind:
  `standard`, via `rancher.io/local-path`) — nenhum addon extra necessário

## Deploy

```bash
kubectl apply -k .
```

Ou individualmente, na ordem dos arquivos (o prefixo numérico já reflete a
ordem de dependência).

## Acessar a aplicação

```bash
kubectl -n voting-app get svc vote result
kubectl -n voting-app get nodes -o wide   # IP interno do node
```

Os Services `vote` (`nodePort: 30080`) e `result` (`nodePort: 30081`) são do
tipo `NodePort` — em kind, sem cloud provider, `LoadBalancer` ficaria preso em
`Pending` para sempre. No Linux, o IP interno do node (container docker) é
acessível direto do host:

```bash
curl http://<INTERNAL-IP-do-node>:30080   # vote
curl http://<INTERNAL-IP-do-node>:30081   # result
```

Alternativa que sempre funciona, independente do ambiente:

```bash
kubectl -n voting-app port-forward svc/vote 8080:80
kubectl -n voting-app port-forward svc/result 8081:80
```

> Em um EKS real (ver `../terraform`, não provisionado neste lab por causa do
> custo), troque os Services de `vote`/`result` para `type: LoadBalancer` — o
> AWS Cloud Controller Manager provisiona um NLB automaticamente (gera custo
> contínuo). Também será necessário uma `StorageClass` via
> `aws-ebs-csi-driver` (o addon já vem provisionado pelo Terraform), pois o
> EKS não tem uma default pronta.

## Limpeza

```bash
kubectl delete -k .
```
