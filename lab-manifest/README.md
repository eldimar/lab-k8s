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
| `15-gateway.yaml` | Gateway | Listeners HTTP (redirect) + HTTPS por host, TLS terminado |
| `16-httproutes.yaml` | HTTPRoute x3 | Redirect HTTP→HTTPS e roteamento para `vote`/`result` |

### Por que StatefulSet e não Deployment para o banco

Um banco de dados com armazenamento persistente precisa de identidade de rede
estável e um volume dedicado por réplica com ciclo de vida atrelado ao pod —
é para isso que existe o `StatefulSet`. O `04-postgres-statefulset.yaml` usa
`volumeClaimTemplates` (em vez de um PVC solto referenciado por um
Deployment) para que o próprio controller gerencie o PVC (`postgres-data-db-0`).

### Por que Gateway API (e não Ingress) + TLS em vez de NodePort

`vote`/`result` agora são `ClusterIP` (não expostos diretamente); todo o
tráfego externo entra pelo `Gateway` (`15-gateway.yaml` + `16-httproutes.yaml`),
que também centraliza o TLS.

Optou-se por **Gateway API** em vez de `Ingress` porque o
[kubernetes/ingress-nginx foi descontinuado](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
(EOL em 31/03/2026, repositório arquivado, sem mais patches de segurança) — a
API `Ingress` do Kubernetes em si continua existindo, mas o controller mais
usado com ela não é mais mantido. O ecossistema está migrando para Gateway
API; a implementação usada aqui é o **NGINX Gateway Fabric** (sucessor
oficial, mesma tecnologia de proxy). `15-gateway.yaml` define um listener
HTTP (só para redirect) e um listener HTTPS dedicado por host, cada um com
seu certificado; `16-httproutes.yaml` faz o redirect HTTP→HTTPS (via filtro
`RequestRedirect` — não existe annotation equivalente ao `ssl-redirect` do
ingress-nginx em Gateway API) e o roteamento real para `vote`/`result`.

Os certificados são emitidos automaticamente pelo cert-manager
(`13-cert-manager-issuer.yaml` + `14-certificates.yaml`) via um
`ClusterIssuer` self-signed — adequado para um lab sem domínio público
(Let's Encrypt exige HTTP-01/DNS-01, que dependem de DNS público) — e
referenciados diretamente pelos listeners do `Gateway` via `certificateRefs`
(cert-manager não precisa de nenhuma integração especial com Gateway API
para isso). Em um ambiente real, troque por um `Issuer`/`ClusterIssuer` ACME.

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
- **Gateway API CRDs**, **NGINX Gateway Fabric** e **cert-manager** instalados
  no cluster (controllers cluster-wide, fora do escopo deste
  `kustomization.yaml` — mesma lógica da `StorageClass`: são addons do
  cluster, não recursos do app):

  ```bash
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/standard-install.yaml

  kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.7.0/deploy/crds.yaml
  kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.7.0/deploy/nodeport/deploy.yaml
  kubectl -n nginx-gateway wait --for=condition=available deployment/nginx-gateway --timeout=180s

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
kubectl -n voting-app get gateway voting-app
kubectl -n voting-app get httproute
kubectl -n voting-app get certificate    # READY=True quando o cert-manager emitiu os certs
```

O NGINX Gateway Fabric cria um Deployment + Service (`NodePort`) dedicados
por `Gateway`, chamados `<nome-do-gateway>-nginx` — aqui, `voting-app-nginx`.
O cluster `kind-labs` não foi criado com `extraPortMappings` para 80/443,
então não fica acessível direto do host — use `port-forward` para esse
Service:

```bash
kubectl -n voting-app port-forward svc/voting-app-nginx 8443:443
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
kind](https://kind.sigs.k8s.io/docs/user/ingress/) (o procedimento de
`extraPortMappings` é o mesmo, independente do controller).

> Em um EKS real (ver `../terraform`, não provisionado neste lab por causa do
> custo), o [AWS Gateway API
> Controller](https://github.com/aws/aws-application-networking-k8s) faz o
> mesmo papel do AWS Load Balancer Controller, mas para `Gateway`/`HTTPRoute`
> em vez de `Ingress` — provisiona um ALB automaticamente a partir do mesmo
> `Gateway` deste manifesto. Use também um `ClusterIssuer` ACME real em vez
> do self-signed, e uma `StorageClass` via `aws-ebs-csi-driver` (o addon já
> vem provisionado pelo Terraform), pois o EKS não tem uma default pronta.

## Limpeza

```bash
kubectl delete -k .
```
