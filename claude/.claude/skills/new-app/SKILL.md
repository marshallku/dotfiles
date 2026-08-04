---
name: new-app
description: 홈랩 앱 공장 정문 — 앱 이름/타입/도메인을 받아 manifest repo의 kubernetes/apps/<name>/values.yaml을 만들고 save.sh로 커밋하면 ArgoCD ApplicationSet이 자동 배포하고 cloudflare-tunnel-ingress-controller가 도메인+DNS를 붙인다. "새 앱 배포 환경 만들어/공장에 앱 하나 찍어줘/이 앱 홈랩에 올려줘" 류 요청에 사용.
user-invocable: true
arguments: name
argument-hint: <name> [--type nextjs|web-api|api] [--domain <host>] [--api-domain <host>] [--image <prefix>] [--private] [--infisical <projectSlug>]
allowed-tools: Bash,Read,Grep,Glob,Edit,Write
effort: high
---

## 언제 쓰나

- `/new-app <name> ...` — GHCR 이미지가 있는 앱을 홈랩 k3s에 배포하고 공개 도메인까지 한 번에 연결할 때.
- 공장 파이프라인: **`kubernetes/apps/<name>/values.yaml` 커밋 → ArgoCD ApplicationSet이 앱 생성 → workload 차트 렌더 → cloudflare-tunnel이 도메인/DNS 자동 연결.**
- 소스 코드를 바이브코딩하는 건 앱 repo에서. 이 스킬은 **배포/도메인 레이어**만 담당한다.

## 전제 (Phase 0 인프라가 이미 있어야 함)

`marshallku/manifest` repo(`~/dev/manifest`)에 아래가 존재해야 한다 (없으면 중단하고 사용자에게 알림):

- `kubernetes/charts/workload/` — 파라미터화된 앱 차트
- `kubernetes/applicationset/factory-apps.yaml` — apps/* 감시 ApplicationSet (적용돼 있어야 함)
- `kubernetes/cloudflare-tunnel/` — 터널 ingress 컨트롤러 (IngressClass `cloudflare-tunnel`)

확인: `kubectl get ingressclass cloudflare-tunnel` / `kubectl -n argocd get applicationset factory-apps`.

## Step 0 — 입력 확정

인자에서 뽑고, 부족하면 사용자에게 **한 번에** 확인 (질문 최소화):

- `name` (필수) — DNS-safe 소문자/하이픈. 네임스페이스 = 이 이름.
- `--type` — `nextjs`(풀스택 web 1개) | `web-api`(web + api) | `api`(api 1개). 기본 `nextjs`.
- `--domain` — web 공개 호스트 (예: `<name>.marshallku.dev`). type에 web이 있으면 필요.
- `--api-domain` — api 공개 호스트 (예: `api-<name>.marshallku.dev`). api를 외부 노출할 때만.
- `--image` — 이미지 **태그 없는 접두**(예: `ghcr.io/marshallku/<name>`). 템플릿이 `-web:latest`/`-api:latest`를 붙인다 → **태그를 포함하지 말 것**(`...:v1`을 주면 `...:v1-web:latest`로 깨짐). 특정 태그/개별 이미지가 필요하면 접두 대신 각 surface의 `image:`를 직접 완성해 쓴다. 기본값 `ghcr.io/marshallku/<name>`.
- `--private` — GHCR 프라이빗 이미지면 지정 (네임스페이스에 `ghcr-secret` 필요).
- `--infisical <projectSlug>` — Infisical 시크릿을 쓸 때 (예: `<name>-prd`).

## Step 1 — values.yaml 생성

`~/dev/manifest/kubernetes/apps/<name>/values.yaml`을 workload 차트 계약(`kubernetes/charts/workload/README.md`)에 맞춰 작성한다. **values.yaml은 순수 YAML이다 — Helm은 values 파일을 렌더하지 않으므로 `{{ }}` 같은 조건문을 넣지 말고, 아래 규칙을 생성 시점에 직접 해소해 최종 값을 쓴다.**

**모든 type 공통 규칙:** `--private`가 **없으면**(public 이미지) 최상단에 `imagePullSecret: ""`를 넣어 차트 기본값 `ghcr-secret`을 비운다. `--private`면 이 줄을 넣지 않는다(차트가 `ghcr-secret`을 참조 → Step 2에서 시크릿을 심는다).

**type=nextjs** (풀스택 web 1개) — 예시는 public 기준:
```yaml
app: <name>
imagePullSecret: ""          # public이면 유지, --private면 이 줄 삭제
surfaces:
  web:
    image: <image>-web:latest
    port: 3000
    host: <domain>
```

**type=web-api** (web + api, web이 api를 클러스터 내부로 호출) — public이면 `imagePullSecret: ""` 포함:
```yaml
app: <name>
imagePullSecret: ""          # public이면 유지, --private면 삭제
surfaces:
  web:
    image: <image>-web:latest
    port: 3000
    host: <domain>
    env:
      - name: API_URL
        value: http://<name>-api:8080
  api:
    image: <image>-api:latest
    port: 8080
    host: <api-domain>          # 내부 전용이면 이 줄 생략
    healthPath: /api/health
    secretEnv: [ ]               # 시크릿 키를 여기 나열
```

**type=api** (api 1개) — public이면 `imagePullSecret: ""` 포함:
```yaml
app: <name>
imagePullSecret: ""          # public이면 유지, --private면 삭제
surfaces:
  api:
    image: <image>-api:latest
    port: 8080
    host: <api-domain or domain>
    healthPath: /health
```

`--infisical`가 있으면 아래를 덧붙이고, 소비할 키를 해당 surface의 `secretEnv`에 넣는다:
```yaml
secret:
  infisical:
    enabled: true
    projectSlug: <projectSlug>
    envSlug: prd
```

`helm template <name> ~/dev/manifest/kubernetes/charts/workload -f <그 values.yaml>`로 렌더가 깨지지 않는지 먼저 확인한다.

## Step 2 — 네임스페이스 부트스트랩 시크릿 (조건부)

차트가 Namespace를 만들지만 그건 앱이 Sync된 뒤이므로, 아래 부트스트랩 시크릿이 필요하면 **먼저 네임스페이스를 만든 뒤** 시크릿을 심는다. 시크릿이 하나도 필요 없으면(public 이미지 + Infisical 미사용) 이 단계 전체를 건너뛴다(사유 1줄 보고).

**공통 선행 — 네임스페이스 생성** (`--private` 또는 `--infisical` 중 하나라도 있으면):
```sh
kubectl create namespace <name> --dry-run=client -o yaml | kubectl apply -f -
```

- `--private` → `ghcr-secret` (GHCR 풀 시크릿). **PAT를 명령줄/트랜스크립트/`ps` argv에 절대 노출하지 말 것** — `read -rs`는 터미널 입력만 가리므로(`--docker-password=$PAT`는 kubectl argv에 노출됨), PAT가 외부 프로세스 argv에 안 들어가게 `printf`(builtin)로 dockerconfigjson을 임시파일에 만들어 `--from-file`로 넣는다:
  ```sh
  read -rs GH_PAT   # GHCR PAT 붙여넣기 (화면에 안 보임)
  umask 077; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT   # 중단돼도 비밀이 디스크에 안 남게
  printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' \
    "$(printf '%s:%s' '<gh-user>' "$GH_PAT" | base64 | tr -d '\n')" > "$tmp"
  kubectl -n <name> create secret generic ghcr-secret \
    --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson="$tmp"
  rm -f "$tmp"; unset GH_PAT
  ```
  (`printf`는 셸 builtin이라 argv를 안 만들고, `base64`는 stdin으로 읽어 PAT가 어떤 외부 프로세스 argv에도 안 남는다.) GitOps로 남기려면 위 secret을 `kubeseal`로 봉인해 커밋(`kubernetes/service/maji/sealed-ghcr-secret.yaml` 패턴). **부트스트랩 시크릿을 ApplicationSet가 자동 전달하지 않는 건 알려진 갭 — TODO.**
- `--infisical` → `infisical-universal-auth`. 이건 Infisical **머신 아이덴티티(Universal Auth)**의 `clientId`/`clientSecret`를 담은 Secret이며, InfisicalSecret CR의 `credentialsRef`가 이걸 가리킨다(`kubernetes/service/irang/infisical-secret.yaml` 참고 — 단 그 파일은 참조만 하고 생성법은 없음). 값은 Infisical 대시보드 → 프로젝트 → Machine Identities에서 발급받아 네임스페이스에 1회 생성:
  ```sh
  read -rs ICS   # clientSecret 붙여넣기 (화면에 안 보임)
  umask 077; t=$(mktemp); trap 'rm -f "$t"' EXIT      # 중단돼도 비밀이 디스크에 안 남게
  printf '%s' "$ICS" > "$t"   # printf builtin → argv 노출 없음
  kubectl -n <name> create secret generic infisical-universal-auth \
    --from-literal=clientId=<machine-identity-client-id> \
    --from-file=clientSecret="$t"
  rm -f "$t"; unset ICS
  ```
  (`clientId`는 비밀이 아니라 `--from-literal` OK. `clientSecret`만 argv를 피해 파일로 넣는다.)
  (ghcr-secret과 마찬가지로 부트스트랩 자동화는 TODO.)

public 이미지 + 시크릿 없음이면 이 단계는 건너뛴다 (사유 1줄 보고).

## Step 3 — 커밋 (반드시 save.sh)

`~/dev/manifest`에서. **`~/save.sh`는 `git add -A`라 워킹트리의 모든 변경을 커밋한다** — 먼저 프리플라이트로 이번 앱(`kubernetes/apps/<name>/`) 외 변경이 없는지 확인하고, 있으면 중단해 무관한 변경이 배포 커밋에 섞이지 않게 한다:
```sh
cd ~/dev/manifest
# apps/<name>/ 이외의 dirty 경로가 있으면 중단
if git status --porcelain | grep -v "kubernetes/apps/<name>/" | grep -q .; then
  echo "무관한 변경 존재 — 정리(commit/stash)하고 다시 시도"; git status --short; exit 1
fi
~/save.sh "Add <name> app to the factory (kubernetes/apps/<name>)"
```
원격이 앞서 있어 push가 rejected되면: `git reset --soft HEAD~1 && git stash -u && git pull --rebase && git stash pop` 후 `~/save.sh` 재실행. 직접 `git commit`/`git push` 금지.

## Step 4 — 라이브 검증 (실제로 뜨는지 본다)

ApplicationSet git 폴링(~2–3분) 후:
```sh
kubectl -n argocd get application <name>            # 생성 + Synced
kubectl -n <name> get deploy,pod,ingress            # 파드 Running
```
그다음 **실제로 공개된 호스트**를, 그 surface가 실제로 200을 주는 **경로**로 curl한다 — 웹이면 보통 `/`, api만 노출이면 `/`가 아니라 그 surface의 `healthPath`(예: `/health`, `/api/health`)를 쓴다(안 그러면 정상 API가 `/`에서 404를 줘 오판). host를 하나도 안 붙였으면(내부 전용) 이 curl은 생략하고 사유를 보고한다:
```sh
curl -fsS -m 8 "https://<public-host><경로>"   # <경로>는 / 로 시작(예: / 또는 /health). -f: 4xx/5xx면 non-zero
```
도메인/터널 상태는 `~/dev/manifest/scripts/cf.sh dns list <name>` / `~/dev/manifest/scripts/cf.sh tunnel routes homelab-factory`로 확인.

실패 시: ApplicationSet 컨트롤러 로그, 앱 Application의 `status.conditions`, 터널 컨트롤러 로그를 본다:
```sh
kubectl -n cloudflare-tunnel logs -l app.kubernetes.io/name=cloudflare-tunnel-ingress-controller --tail=50
```

## Step 5 — 보고

- 만든 `values.yaml` 경로, 커밋 해시, 라이브 URL, 검증 결과(파드 상태 + curl)를 요약한다.
- 앱 repo 쪽 CI(이미지 빌드 → `apps/<name>` 이미지 태그 bump)는 아직 없다면 별도 작업으로 안내 (maji/irang의 `deploy-*.yml` + `MANIFEST_REPO_TOKEN` 패턴).

## 아직 안 되는 것 (TODO)

- **DB 프로비저닝**: `database.enabled: true`로 홈랩 Postgres에 앱별 DB/role을 파고 `DATABASE_URL`을 주입하는 자동화는 별도 헬퍼 완성 후 이 스킬에 `--db` 플래그로 추가 예정.
- **앱 repo 스캐폴딩**: Dockerfile + deploy 워크플로 생성기는 추후.
