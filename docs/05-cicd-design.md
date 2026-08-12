# 05. CI/CD

## Overview

main 브랜치에 push되면 GitHub Actions가 네 서비스 이미지를 빌드해서 ECR에 올리고, 별도 매니페스트 레포의 이미지 태그를 갱신한다. ArgoCD가 그 레포를 폴링하며 클러스터 상태를 맞춘다.

## GitHub Actions에서 AWS로: 고정 키 대신 OIDC

워크플로우가 ECR에 push하려면 AWS 자격증명이 필요한데, 액세스 키를 GitHub Secrets에 박아두는 대신 OIDC federation을 썼다. GitHub Actions가 발급하는 토큰을 `terraform-ecr/github-oidc.tf`에 정의된 IAM 롤이 신뢰하고, 이 신뢰 조건은 `heeyeon-yang/iot-streaming-platform`의 main 브랜치로 좁혀놨다. 장기 자격증명이 어디에도 저장되지 않는다.

## 앱 레포와 매니페스트 레포 분리

`iot-streaming-platform`은 애플리케이션 코드와 인프라(Terraform)를 갖고, `iot-streaming-platform-manifests`는 배포 상태(Kustomize 매니페스트)만 갖는다. CI는 이미지를 빌드해서 후자에 커밋하고, ArgoCD는 후자만 본다. 앱 코드를 고치는 것과 배포 상태를 바꾸는 것이 서로 다른 레포의 서로 다른 커밋이 되기 때문에, 뭐가 실제로 클러스터에 반영됐는지가 그 레포 하나의 히스토리로 확인된다.

## 계정 ID 치환은 CI 단계에서

매니페스트 레포의 `base/kustomization.yaml`, `base/serviceaccounts.yaml`엔 `<AWS_ACCOUNT_ID>` 플레이스홀더가 커밋돼 있다. 이전 수동 배포 방식에서는 로컬에서 sed로 치환 후 `kubectl apply`했지만, ArgoCD는 레포 내용을 그대로 읽기 때문에 이 자리에 사람이 낄 여지가 없다. 그래서 워크플로우의 마지막 스텝이 매니페스트 레포를 clone한 직후 `sed`로 계정 ID를 실제 값으로 바꾸고 커밋한다.

## ArgoCD sync policy: automated + prune + selfHeal

`argocd/application.yaml`의 sync policy는 자동 sync, prune, selfHeal을 모두 켜놨다. 매니페스트 레포에서 리소스를 지우면 클러스터에서도 지워지고(prune), 누군가 `kubectl edit`으로 클러스터를 직접 건드려도 다음 sync에서 레포 상태로 되돌아간다(selfHeal) — 클러스터의 실제 상태와 Git의 선언 상태가 벌어지지 않게 하는 게 목적이다.
