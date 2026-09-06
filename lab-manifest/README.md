# Manifestos Kubernetes - App de Votação

Deploy completo do [example-voting-app](https://github.com/dockersamples/example-voting-app)
no namespace `voting-app`.

## Componentes

| Manifesto | Recurso | Descrição |
|---|---|---|
| `00-namespace.yaml` | Namespace | `voting-app` |
| `02-postgres-secret.yaml` | Secret | Credenciais do Postgres |
| `04-postgres-statefulset.yaml` | StatefulSet `db` | PostgreSQL 15 (PVC via `volumeClaimTemplates`, 5Gi, StorageClass default do cluster) |
| `05-postgres-service.yaml` | Service `db` (headless) | Governing service do StatefulSet |
| `06-redis-deployment.yaml` / `07-redis-service.yaml` | Deployment + Service `redis` | Fila/cache |
| `08-vote-deployment.yaml` / `09-vote-service.yaml` | Deployment + Service (ClusterIP) | Frontend de votação |
| `10-worker-deployment.yaml` | Deployment | Consome Redis, grava no Postgres |
| `11-result-deployment.yaml` / `12-result-service.yaml` | Deployment + Service (ClusterIP) | Frontend de resultados |
| `13-cert-manager-issuer.yaml` | ClusterIssuer | Emissor self-signed (cert-manager) |
| `14-certificates.yaml` | Certificate x2 | Certificados TLS de `vote`/`result`, gerenciados pelo cert-manager |
| `15-ingress.yaml` | Ingress | Expõe `vote`/`result` via HTTPS (host-based routing) |

### Por que StatefulSet e não Deployment para o banco

Um banco de dados com armazenamento persistente precisa de identidade de rede
estável e um volume dedicado por réplica com ciclo de vida atrelado ao pod —
é para isso que existe o `StatefulSet`. O `04-postgres-statefulset.yaml` usa
`volumeClaimTemplates` (em vez de um PVC solto referenciado por um
Deployment) para que o próprio controller gerencie o PVC (`postgres-data-db-0`).

### Por que Ingress + TLS em vez de NodePort

`vote`/`result` agora são `ClusterIP` (não expostos diretamente); todo o
tráfego externo entra pelo Ingress (`15-ingress.yaml`), que também
centraliza o TLS. Os certificados são emitidos automaticamente pelo
cert-manager (`13-cert-manager-issuer.yaml` + `14-certificates.yaml`) via um
`ClusterIssuer` self-signed — adequado para um lab sem domínio público
(Let's Encrypt exige HTTP-01/DNS-01, que dependem de DNS público). Em um
ambiente real, troque por um `Issuer`/`ClusterIssuer` ACME.

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
- **ingress-nginx** e **cert-manager** instalados no cluster (controllers
  cluster-wide, fora do escopo deste `kustomization.yaml` — mesma lógica da
  `StorageClass`: são addons do cluster, não recursos do app):

  ```bash
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
  kubectl -n ingress-nginx wait --for=condition=available deployment/ingress-nginx-controller --timeout=180s

  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
  kubectl -n cert-manager wait --for=condition=available deployment --all --timeout=180s
  ```

## Deploy

```bash
kubectl apply -k .
```

Ou individualmente, na ordem dos arquivos (o prefixo numérico já reflete a
ordem de dependência).

## Acessar a aplicação

```bash
kubectl -n voting-app get ingress voting-app
kubectl -n voting-app get certificate    # READY=True quando o cert-manager emitiu os certs
```

O cluster `kind-labs` não foi criado com `extraPortMappings` para 80/443, então
o Ingress não fica acessível direto do host — use `port-forward` para o
controller:

```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8443:443
```

E resolva os hosts para `127.0.0.1` (`/etc/hosts` ou `--resolve` do curl):

```bash
curl -k --resolve vote.voting-app.local:8443:127.0.0.1 https://vote.voting-app.local:8443
curl -k --resolve result.voting-app.local:8443:127.0.0.1 https://result.voting-app.local:8443
```

O `-k` é necessário porque o certificado é self-signed (ver seção acima) —
navegadores vão mostrar aviso de "conexão não segura", esperado em lab.
Para recriar o cluster com as portas 80/443 mapeadas (acesso direto sem
port-forward), veja a [documentação do ingress-nginx para
kind](https://kind.sigs.k8s.io/docs/user/ingress/).

> Em um EKS real (ver `../terraform`, não provisionado neste lab por causa do
> custo), use o **AWS Load Balancer Controller** para que o mesmo `Ingress`
> provisione um ALB automaticamente (`ingressClassName: alb`), e um
> `ClusterIssuer` ACME real em vez do self-signed. Também será necessário uma
> `StorageClass` via `aws-ebs-csi-driver` (o addon já vem provisionado pelo
> Terraform), pois o EKS não tem uma default pronta.

## Limpeza

```bash
kubectl delete -k .
```
